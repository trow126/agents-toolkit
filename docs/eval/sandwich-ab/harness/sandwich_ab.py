#!/usr/bin/env python3
"""sandwich-ab — Opus 単独（A）/ サンドイッチ（B）/ Sol 単独（C）の比較 harness（雛形）。

設計: docs/eval/sandwich-ab-design.md。題材・test・結果は private overlay と eval_root に置き、公開 repo には置かない。

usage:
  sandwich_ab.py check      [--config PATH]                     前提の確認（モデルは呼ばない）
  sandwich_ab.py verify-task [--config PATH] <S01> [--draft]    題材の ready 条件（§4.2）を機械検証（モデルは呼ばない）
  sandwich_ab.py schedule   [--config PATH] [--arms A,B,C] [--reps 2] [--rep-start 1] [--seed N] [--tasks S01,...]
  sandwich_ab.py run        [--config PATH] [--dry-run] [--limit N] [--parallel N]
  sandwich_ab.py grade      [--config PATH] <rid>               1 run を採り直す（モデルは呼ばない）
  sandwich_ab.py blind-pack [--config PATH] [--seed N]          盲検 review の pack を作る
  sandwich_ab.py blind-review [--config PATH] [--dry-run]       pack ごとに、config の blind_reviewers 全員（Opus と Codex）が採点

1 run = 1 題材 × 1 アーム × 1 反復。run ごとに bare mirror から detached worktree を作り、base から始める。
受け入れテストと隠しテストは採点時だけ作業ツリーの写しに置き、どのアームのプロンプトにも入れない。
結果は eval_root/results.jsonl に 1 行ずつ追記する。記録済みの rid は飛ばすので再開できる。
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "agents-toolkit/eval/sandwich/config.json"
RATE_LIMIT = re.compile(r"rate.?limit|usage.?limit|too many requests|\b429\b", re.I)
AUTH_ERROR = re.compile(r"not logged in|please (run )?(/)?login|unauthori[sz]ed|\b401\b|token (has )?expired|invalid api key|"
                        r"authentication (failed|required|error)", re.I)
EXCLUDE_FROM_DIFF = [":(exclude)uv.lock", ":(exclude).venv", ":(exclude)tests/_acceptance", ":(exclude)tests/_hidden"]
# 採点用の写しに持ち込まないもの。.venv は editable install が元の作業ツリーを指すので、写しで uv sync し直す
# （そうしないとミュータントを当てた写しの src ではなく、元の作業ツリーの src が import される）。
COPY_IGNORE = shutil.ignore_patterns(".venv", "__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache")
LOCK = threading.Lock()
STOP = threading.Event()  # 致命的な基盤エラー（CLI の版の変化など）で新しい run を始めない


# ---------------------------------------------------------------- utilities
def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def log(msg: str) -> None:
    with LOCK:
        print(f"{now()} {msg}", flush=True)


def sh(cmd, cwd=None, timeout=None, check=True, stdin_text=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, input=stdin_text, capture_output=True, text=True, timeout=timeout, env=env)
    if check and r.returncode != 0:
        raise RuntimeError(f"{cmd!r} failed ({r.returncode}): {r.stderr[-2000:]}")
    return r


def xpath(p: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(p)))


def load_config(path: Path) -> dict:
    if not path.exists():
        sys.exit(f"config not found: {path} (copy {HERE / 'config.example.json'} there)")
    cfg = json.loads(path.read_text())
    for key in ("eval_root", "tasks_dir", "tests_dir", "toolkit_bin", "templates_dir"):
        cfg[key] = xpath(cfg[key])
    return cfg


def load_tasks(cfg: dict, ids: list[str] | None = None, ready_only: bool = True) -> list[dict]:
    tasks = []
    for f in sorted(cfg["tasks_dir"].glob("S*.json")):
        t = json.loads(f.read_text())
        if ids and t["id"] not in ids:
            continue
        if ready_only and t.get("status") != "ready":
            continue
        tasks.append(t)
    return tasks


def template(cfg: dict, name: str) -> str:
    return (cfg["templates_dir"] / name).read_text()


def bullets(items) -> str:
    return "\n".join(f"- {x}" for x in items) or "- なし"


def junit_counts(xml: Path) -> tuple[int, int]:
    if not xml.exists():
        return 0, 0
    root = ET.parse(xml).getroot()
    suites = [root] if root.tag == "testsuite" else list(root)
    total = sum(int(s.get("tests", 0)) for s in suites)
    bad = sum(int(s.get(k, 0)) for s in suites for k in ("failures", "errors", "skipped"))
    return total - bad, total


# ---------------------------------------------------------------- workspace
def mirror(cfg: dict, repo: str) -> Path:
    """元の repo（~/<repo>、または config の repo_paths）からは読むだけ。mirror に対して worktree を作る。"""
    m = cfg["eval_root"] / "src" / f"{repo}.git"
    with LOCK:
        if not m.exists():
            m.parent.mkdir(parents=True, exist_ok=True)
            src = xpath(cfg.get("repo_paths", {}).get(repo, str(Path.home() / repo)))
            sh(["git", "clone", "-q", "--mirror", str(src), str(m)])
    return m


def wt_fingerprint(wt: Path) -> str:
    """作業ツリーの内容の指紋（tracked の diff と、ignore されない未追跡ファイルの内容）。read-only 呼び出しの前後で比べる。"""
    import hashlib
    h = hashlib.sha256(sh(["git", "-C", str(wt), "diff", "HEAD", "--binary"], check=False).stdout.encode())
    for f in sorted(sh(["git", "-C", str(wt), "ls-files", "--others", "--exclude-standard"], check=False).stdout.splitlines()):
        if "__pycache__" in f or ".pytest_cache" in f:
            continue
        p = wt / f
        h.update(f.encode() + (p.read_bytes() if p.is_file() else b""))
    return h.hexdigest()


def make_worktree(cfg: dict, task: dict, rid: str, sub: str = "runs") -> Path:
    run_dir = cfg["eval_root"] / sub / rid
    wt = run_dir / "wt"
    m = mirror(cfg, task["repo"])
    with LOCK:
        if wt.exists():
            sh(["git", "-C", str(m), "worktree", "remove", "--force", str(wt)], check=False)
            shutil.rmtree(wt, ignore_errors=True)
        sh(["git", "-C", str(m), "worktree", "prune"])
        run_dir.mkdir(parents=True, exist_ok=True)
        sh(["git", "-C", str(m), "worktree", "add", "-q", "--detach", str(wt), task["base"]])
    sh(["uv", "sync", "-q"], cwd=wt, timeout=cfg["timeouts_s"]["uv_sync"], check=False)
    return wt


def state_dir(wt: Path) -> Path:
    d = Path(sh(["git", "-C", str(wt), "rev-parse", "--absolute-git-dir"]).stdout.strip()) / "agents-toolkit"
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---------------------------------------------------------------- model calls
def claude_call(cfg: dict, arm: dict, prompt: str, cwd: Path, out: Path, *, write: bool, schema: Path | None = None,
                toolset: list[str] | None = None) -> dict:
    """claude -p を 1 回呼ぶ。生の JSON を out に残し、費用・token・時間を返す。

    managed policy が defaultMode=bypassPermissions かつ allowManagedPermissionRulesOnly なので、--allowedTools は
    権限を絞らない（2026-10-03 に確認）。使えるツールの集合は --tools で固定する（Skill・Task・Workflow・Web を出さない。
    特に Skill 経由で Codex に委任されると arm A が Opus 単独でなくなる）。"""
    tools = cfg["claude_impl_tools"] if write else cfg["claude_readonly_tools"]
    if toolset is None:
        toolset = cfg["claude_impl_toolset"] if write else cfg["claude_readonly_toolset"]
    # stream-json はツール呼び出しも残るので、汚染検査（contamination）に使える。最後の result 行が集計値。
    cmd = ["claude", "-p", "--model", arm["claude_model"], "--output-format", "stream-json", "--verbose",
           *cfg.get("claude_common_args", []),
           "--max-budget-usd", str(cfg["claude_max_budget_usd_per_call"])]
    if arm.get("claude_effort"):
        cmd += ["--effort", arm["claude_effort"]]
    if schema is not None:
        # claude の --json-schema は "$schema"（draft 2020-12 の宣言）を受け付けない（2026-10-03 のスモークで確認）ので外して渡す
        sj = json.loads(schema.read_text())
        sj.pop("$schema", None)
        cmd += ["--json-schema", json.dumps(sj, ensure_ascii=False)]
    cmd += ["--tools", ",".join(toolset)]
    if not write:
        cmd += ["--disallowedTools", "Edit", "Write", "NotebookEdit"]
    if toolset:
        cmd += ["--allowedTools", *tools]
    t0 = time.monotonic()
    try:
        r = sh(cmd, cwd=cwd, timeout=cfg["timeouts_s"]["claude"], check=False, stdin_text=prompt)
        raw, rc, err = r.stdout, r.returncode, r.stderr
    except subprocess.TimeoutExpired:
        raw, rc, err = "", "timeout", ""
    out.write_text(raw)
    if err:
        out.with_suffix(".stderr").write_text(err)
    j = {}
    for line in raw.splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(ev, dict) and ev.get("type") == "result":
            j = ev
    usage = j.get("usage") or {}
    return {
        "exit": rc, "wall_s": round(time.monotonic() - t0), "subtype": j.get("subtype"), "is_error": j.get("is_error"),
        "num_turns": j.get("num_turns"), "cost_usd": j.get("total_cost_usd"),
        "input_tokens": usage.get("input_tokens"), "cache_read_tokens": usage.get("cache_read_input_tokens"),
        "cache_write_tokens": usage.get("cache_creation_input_tokens"), "output_tokens": usage.get("output_tokens"),
        "result": j.get("result"), "structured": j.get("structured_output"),
        "rate_limited": bool(rc not in (0, "timeout") and RATE_LIMIT.search(raw[-4000:] + err[-2000:])),
        "auth_error": bool(rc not in (0, "timeout") and AUTH_ERROR.search(raw[-4000:] + err[-2000:])),
    }


def codex_usage(jsonl: Path) -> dict:
    tot = {"input_tokens": 0, "cached_input_tokens": 0, "cache_write_input_tokens": 0, "output_tokens": 0,
           "reasoning_output_tokens": 0}
    if not jsonl.exists():
        return tot
    for line in jsonl.read_text(errors="replace").splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "turn.completed":
            for k in tot:
                tot[k] += int((ev.get("usage") or {}).get(k) or 0)
    return tot


def contract_for(task: dict, rid: str, arm: dict, plan: str | None) -> dict:
    goal = f"# {task['title']}\n\n{task['body']}"
    if plan:
        goal += "\n\n---\n\n以下は、このタスクのために書かれた実装計画です。計画に従って実装してください。\n\n" + plan
    return {
        "id": rid, "goal": goal,
        "acceptance_criteria": [
            "タスク本文の要件を scope の中で実装する",
            "本文に書かれた interface（関数名・引数・戻り値）を変えない",
            "変更した振る舞いを検証する test を追加または更新する",
            *[f"`{c}` が成功する" for c in task["required_checks"]],
        ],
        "scope_paths": task["scope_paths"], "required_checks": task["required_checks"],
        "diff_budget": task["diff_budget"], "allowed_dependency_changes": [],
        "non_goals": ["scope_paths の外のファイル（docs、README、設定）の更新", "依頼されていないリファクタや整形"],
        "invariants": ["既存の test を削除、skip、弱体化しない", "commit しない"],
        "protected_paths_extra": [],
        "route": {"model": arm["codex_model"], "effort": arm["codex_effort"]},
    }


def codex_round(cfg: dict, wt: Path, cpath: Path, rid: str) -> dict:
    binp = cfg["toolkit_bin"]
    sh([sys.executable, str(binp / "delegation-evidence-check"), "--repo", str(wt), "--clear"], check=False)
    t0 = time.monotonic()
    try:
        d = sh([sys.executable, str(binp / "codex-delegate"), str(cpath), "--repo", str(wt)],
               timeout=cfg["timeouts_s"]["codex"], check=False)
        rc, dlog = d.returncode, d.stderr
    except subprocess.TimeoutExpired:
        rc, dlog = "timeout", ""
        sh(["pkill", "-f", f"codex exec -C {wt} "], check=False)
    wall = round(time.monotonic() - t0)
    sd = state_dir(wt)
    v = sh([sys.executable, str(binp / "verify-delegation"), str(cpath), "--repo", str(wt)],
           timeout=cfg["timeouts_s"]["check"] * 2, check=False)
    ev_path, res_path = sd / f"evidence-{rid}.json", sd / f"result-{rid}.json"
    ev = json.loads(ev_path.read_text()) if ev_path.exists() else {}
    report = json.loads(res_path.read_text()) if res_path.exists() else {}
    tail = (sd / f"exec-{rid}.stderr").read_text(errors="replace")[-4000:] if (sd / f"exec-{rid}.stderr").exists() else ""
    return {
        "model": json.loads(cpath.read_text())["route"]["model"],
        "exit": rc, "wall_s": wall, "gate_passed": ev.get("passed", False), "gate_exit": v.returncode,
        "violations": ev.get("violations"), "status": report.get("status"),
        "stopped": (report.get("stopped") or {}).get("trigger"), **codex_usage(sd / f"exec-{rid}.jsonl"),
        "rate_limited": bool(rc not in (0, "timeout") and RATE_LIMIT.search(tail + dlog)),
        "auth_error": bool(rc not in (0, "timeout") and AUTH_ERROR.search(tail + dlog)),
    }


# ---------------------------------------------------------------- grading
def diff_stats(repo: Path, base: str, scope: list[str]) -> dict:
    """base からの差分（未追跡の新規ファイルを含む）。写しの .git は元の worktree と gitdir を共有するので、
    index は一時ファイル（GIT_INDEX_FILE）を使い、元の worktree の index を変えない。"""
    index = repo.parent / f"{repo.name}.gitindex"  # 作業ツリーの外に置く（diff に混ざらないように）
    env = os.environ | {"GIT_INDEX_FILE": str(index)}
    git = ["git", "-C", str(repo), "-c", "core.quotepath=off"]
    sh([*git, "read-tree", base], env=env)
    spec = ["--", ".", *EXCLUDE_FROM_DIFF]
    # add の pathspec に ignore 済みのパス（.venv）を名指しすると git が exit 1 になるので、add では .venv を外す
    sh([*git, "add", "-A", "--", ".", *[x for x in EXCLUDE_FROM_DIFF if x != ":(exclude).venv"]], env=env)
    num = sh([*git, "diff", "--cached", "--numstat", base, *spec], env=env).stdout
    files, lines = [], 0
    for row in num.splitlines():
        a, d, path = row.split("\t", 2)
        files.append(path)
        lines += (int(a) if a != "-" else 0) + (int(d) if d != "-" else 0)
    from fnmatch import fnmatch
    out = [f for f in files if not any(fnmatch(f, p) for p in scope)]
    patch = sh([*git, "diff", "--cached", base, *spec], env=env).stdout
    index.unlink(missing_ok=True)
    return {"files": files, "n_files": len(files), "lines": lines, "out_of_scope": out, "patch": patch}


def run_tests(cfg: dict, repo: Path, targets: list[str], xml: Path) -> tuple[int, int]:
    if not targets:
        return 0, 0
    sh(["uv", "run", "--no-sync", "pytest", "-q", "-p", "no:cacheprovider", f"--junitxml={xml}", *targets],
       cwd=repo, timeout=cfg["timeouts_s"]["check"], check=False)
    return junit_counts(xml)


def copy_for_grading(cfg: dict, wt: Path, out_dir: Path, tag: str) -> Path:
    g = out_dir / f"grade-{tag}"
    shutil.rmtree(g, ignore_errors=True)
    shutil.copytree(wt, g, symlinks=True, ignore=COPY_IGNORE)
    sh(["uv", "sync", "-q"], cwd=g, timeout=cfg["timeouts_s"]["uv_sync"], check=False)
    return g


def grade(cfg: dict, task: dict, wt: Path, out_dir: Path, tag: str = "final") -> dict:
    """作業ツリーの写しで採点する。作業ツリーそのものは変えない。"""
    g = copy_for_grading(cfg, wt, out_dir, tag)
    ds = diff_stats(g, task["base"], task["scope_paths"])
    (out_dir / f"{tag}.diff").write_text(ds.pop("patch"))
    checks = []
    for c in task["required_checks"]:
        try:
            rc = sh(["bash", "-lc", c], cwd=g, timeout=cfg["timeouts_s"]["check"], check=False).returncode
        except subprocess.TimeoutExpired:
            rc = 124
        checks.append({"cmd": c, "exit": rc})
    tdir = cfg["tests_dir"] / task["id"]
    res = {"diff": ds, "checks": checks, "checks_passed": all(c["exit"] == 0 for c in checks)}
    for kind, sub in (("acceptance", "_acceptance"), ("hidden", "_hidden")):
        dst = g / "tests" / sub
        dst.mkdir(parents=True, exist_ok=True)
        (dst / "__init__.py").touch()
        for rel in task.get(f"{kind}_tests", []):
            shutil.copy2(tdir / rel, dst / Path(rel).name)
        p, t = run_tests(cfg, g, [f"tests/{sub}"] if task.get(f"{kind}_tests") else [], out_dir / f"{tag}-{kind}.xml")
        res[kind] = {"passed": p, "total": t, "all": t > 0 and p == t}
    res["mutants"] = mutant_score(cfg, task, g, ds["files"], out_dir, tag) if task.get("mutants") else None
    if res["mutants"] is not None:
        # テスト追加の題材（S04・S06・S16）は、隠しテストの代わりにミュータントで判定する（設計書 §3・§4.2・§5）。
        # 全ミュータントを落とせたら「隠しテスト pass」。patch が当たらない（対象コードを変えた）ものは落とせなかった扱い。
        m = res["mutants"]
        res["hidden"] = {"passed": m["killed"], "total": m["total"], "all": m["total"] > 0 and m["killed"] == m["total"],
                         "source": "mutants"}
    shutil.rmtree(g, ignore_errors=True)
    return res


def mutant_score(cfg: dict, task: dict, g: Path, changed: list[str], out_dir: Path, tag: str,
                 agent_tests: list[str] | None = None) -> dict:
    """test-add 題材: エージェントが追加・変更した test が、隠しミュータントを落とせるか。"""
    if agent_tests is None and task.get("mutant_test_files"):
        # 本文が指定した test ファイルだけで判定する。エージェントが既存の test ファイルを触っても、
        # その既存 test が落とすミュータントを加点しない（S04・S06 で base の既存 test が一部のミュータントを落とすため）
        agent_tests = [f for f in task["mutant_test_files"] if (g / f).exists()]
    if agent_tests is None:
        agent_tests = [f for f in changed if f.startswith("tests/") and f.endswith(".py") and (g / f).exists()]
    killed = []
    for i, rel in enumerate(task["mutants"]):
        patch = cfg["tests_dir"] / task["id"] / rel
        if sh(["git", "-C", str(g), "apply", str(patch)], check=False).returncode != 0:
            killed.append(None)  # patch が当たらない = エージェントが対象コードを変えた。集計では別扱い
            continue
        p, t = run_tests(cfg, g, agent_tests, out_dir / f"{tag}-mutant{i}.xml")
        killed.append(t > 0 and p < t)
        sh(["git", "-C", str(g), "apply", "-R", str(patch)], check=False)
    applied = [k for k in killed if k is not None]
    return {"killed": sum(applied), "applied": len(applied), "total": len(killed), "agent_tests": agent_tests}


def contamination(cfg: dict, run_dir: Path) -> bool:
    """エージェントの記録に overlay の test パスが出てきたら汚染として記録する（その run は集計から外す）。
    別の run の作業ツリー・diff（eval_root/runs/<他の rid>）、盲検 pack・対応表への言及も汚染とする。"""
    # "_acceptance" 単体は R4 の src（parse_submission_acceptance_times）に出るので、tests/ 付きで探す
    needles = {str(cfg["tests_dir"]), "eval/sandwich/tests", "eval/sandwich/tasks", "tests/_hidden", "tests/_acceptance",
               "blind-map", str(cfg["eval_root"] / "blind"), str(cfg["eval_root"] / "prep"), str(cfg["eval_root"] / "dev")}
    # Codex は上位ディレクトリの AGENTS.md を探すので runs/AGENTS.md は出てよい。rid の形のものだけを見る
    runs_re = re.compile(re.escape(str(cfg["eval_root"] / "runs")) + r"/(S\d+-[A-Z]-r\d+)")
    logs = list(run_dir.glob("claude-*.json")) + list((run_dir / "state").glob("exec-*.jsonl"))
    for f in logs:
        text = f.read_text(errors="replace")
        if any(n in text for n in needles):
            return True
        if any(m.group(1) != run_dir.name for m in runs_re.finditer(text)):
            return True
    return False


# ---------------------------------------------------------------- arms
def solo_prompt(cfg: dict, task: dict) -> str:
    return template(cfg, "solo-prompt.md").format(
        title=task["title"], body=task["body"], interface=bullets(task["interface"]),
        scope_paths=bullets(task["scope_paths"]), required_checks=bullets(task["required_checks"]),
        diff_budget_files=task["diff_budget"]["files"], diff_budget_lines=task["diff_budget"]["lines"])


def arm_a(cfg, task, rid, wt, run_dir, rec):
    arm = cfg["arms"]["A"]
    rec["claude"] = [claude_call(cfg, arm, solo_prompt(cfg, task), wt, run_dir / "claude-impl.json", write=True)]
    if rec["claude"][0]["subtype"] not in (None, "success"):
        rec["interventions"].append(f"claude:{rec['claude'][0]['subtype']}")


def arm_b(cfg, task, rid, wt, run_dir, rec):
    arm = cfg["arms"]["B"]
    plan_tpl = template(cfg, "plan.md")
    for key, val in {"task_id": task["id"], "scope_paths": ", ".join(task["scope_paths"]),
                     "diff_budget_files": task["diff_budget"]["files"], "diff_budget_lines": task["diff_budget"]["lines"],
                     "required_check": " && ".join(task["required_checks"])}.items():
        plan_tpl = plan_tpl.replace("{" + key + "}", str(val))
    plan_prompt = template(cfg, "plan-prompt.md").format(solo=solo_prompt(cfg, task), plan_template=plan_tpl)
    fp = wt_fingerprint(wt)
    plan = claude_call(cfg, arm, plan_prompt, wt, run_dir / "claude-plan.json", write=False)
    if wt_fingerprint(wt) != fp:  # Bash 経由の書き込み（bypass のため禁止できない）を記録する
        rec["interventions"].append("claude:readonly_write:plan")
    rec["claude"] = [plan | {"stage": "plan"}]
    plan_text = plan.get("result") or ""
    (run_dir / "plan.md").write_text(plan_text)
    if not plan_text.strip():
        rec["interventions"].append("plan:empty")
        return
    sd = state_dir(wt)
    cpath = sd / f"contract-{rid}.json"
    contract = contract_for(task, rid, arm, plan_text)
    cpath.write_text(json.dumps(contract, ensure_ascii=False, indent=2))
    schema = cfg["templates_dir"] / "review-verdict.schema.json"
    rec["codex"], rec["reviews"], rec["round_grades"] = [], [], []
    for rnd in range(1, arm["max_codex_rounds"] + 1):
        cr = codex_round(cfg, wt, cpath, rid)
        rec["codex"].append(cr)
        if cr["rate_limited"] or cr["auth_error"]:
            rec["rate_limited"] = cr["rate_limited"]
            return
        # 工程内レビューの前に隠しテストを当てる（記録だけ。Codex にも reviewer にも渡さない）
        rec["round_grades"].append(grade(cfg, task, wt, run_dir, tag=f"round{rnd}"))
        if cr["status"] == "stopped":
            rec["interventions"].append(f"codex:stopped:{cr['stopped']}")
            return
        diff = (run_dir / f"round{rnd}.diff").read_text()
        ev = sd / f"evidence-{rid}.json"
        review_prompt = template(cfg, "review.md") + "\n\n" + "\n\n".join([
            f"## タスク\n\n# {task['title']}\n\n{task['body']}",
            f"## 計画\n\n{plan_text}",
            f"## diff（base {task['base'][:12]} から）\n\n```diff\n{diff}\n```",
            f"## Codex の完了報告\n\n```json\n{(sd / f'result-{rid}.json').read_text() if (sd / f'result-{rid}.json').exists() else '{}'}\n```",
            f"## gate（verify-delegation）\n\n```json\n{ev.read_text() if ev.exists() else '{}'}\n```",
        ])
        fp = wt_fingerprint(wt)
        rv = claude_call(cfg, arm, review_prompt, wt, run_dir / f"claude-review{rnd}.json", write=False, schema=schema)
        if wt_fingerprint(wt) != fp:
            rec["interventions"].append(f"claude:readonly_write:review{rnd}")
        verdict = rv.get("structured") or {}
        rec["claude"].append(rv | {"stage": f"review{rnd}", "structured": None, "result": None})
        rec["reviews"].append(verdict)
        v = verdict.get("verdict")
        must = [f for f in verdict.get("findings", []) if f.get("severity") == "must_fix"]
        if v == "APPROVED" or (v == "WARNING" and not must):
            return
        if v == "BLOCKED" or v is None:
            rec["interventions"].append(f"review:{v or 'unparsed'}")
            return
        if rnd == arm["max_codex_rounds"]:
            rec["interventions"].append("review:max_rounds")
            return
        contract = json.loads(cpath.read_text())
        contract["goal"] += f"\n\n---\n\n## レビュー指摘（{rnd} 回目）。must_fix をすべて直すこと\n\n" + "\n".join(
            f"- [{f['category']}] {f['location']}: {f['fix']}" for f in must)
        cpath.write_text(json.dumps(contract, ensure_ascii=False, indent=2))


def arm_c(cfg, task, rid, wt, run_dir, rec):
    arm = cfg["arms"]["C"]
    cpath = state_dir(wt) / f"contract-{rid}.json"
    cpath.write_text(json.dumps(contract_for(task, rid, arm, None), ensure_ascii=False, indent=2))
    cr = codex_round(cfg, wt, cpath, rid)
    rec["codex"] = [cr]
    rec["rate_limited"] = cr["rate_limited"]
    if cr["status"] == "stopped":
        rec["interventions"].append(f"codex:stopped:{cr['stopped']}")


ARMS = {"A": arm_a, "B": arm_b, "C": arm_c}


def run_one(cfg: dict, task: dict, arm_id: str, rep: int, dry: bool) -> dict | None:
    rid = f"{task['id']}-{arm_id}-r{rep}"
    if dry:
        log(f"DRY {rid}: worktree {task['repo']}@{task['base'][:12]} -> arm {arm_id} ({cfg['arms'][arm_id]['label']})")
        return None
    wt = make_worktree(cfg, task, rid)
    run_dir = wt.parent
    rec = {"rid": rid, "task": task["id"], "arm": arm_id, "rep": rep, "kind": task["kind"],
           "leak_trap": task["leak_trap"], "started_at": now(), "interventions": [], "rate_limited": False}
    rec["versions"] = cli_versions()
    t0 = time.monotonic()
    ARMS[arm_id](cfg, task, rid, wt, run_dir, rec)
    rec["wall_s"] = round(time.monotonic() - t0)
    if any(c.get("rate_limited") for c in rec.get("claude", [])):
        rec["rate_limited"] = True
    rec["auth_error"] = any(c.get("auth_error") for c in rec.get("claude", []) + rec.get("codex", []))
    if rec.get("rate_limited") or rec["auth_error"]:
        return rec
    sd = state_dir(wt)
    shutil.copytree(sd, run_dir / "state", dirs_exist_ok=True)
    rec["final"] = grade(cfg, task, wt, run_dir)
    rec["contaminated"] = contamination(cfg, run_dir)
    if not rec["final"]["checks_passed"]:
        rec["interventions"].append("checks:failed")
    if rec["final"]["diff"]["out_of_scope"]:
        rec["interventions"].append("scope:violated")
    return rec


def cli_versions() -> dict:
    return {c: sh([c, "--version"], check=False).stdout.strip() for c in ("claude", "codex")}


# ---------------------------------------------------------------- commands
def cmd_check(cfg: dict, _a) -> int:
    problems = []
    for c in ("claude", "codex", "uv", "git"):
        if shutil.which(c) is None:
            problems.append(f"{c} not on PATH (login shell で実行する: bash -lc)")
    if shutil.which("codex"):
        print("codex:", sh(["codex", "--version"], check=False).stdout.strip())
    if shutil.which("claude"):
        print("claude:", sh(["claude", "--version"], check=False).stdout.strip())
    prof = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "toolkit-implementer.config.toml"
    if not prof.exists():
        problems.append(f"Codex profile missing: {prof} (bootstrap.sh --apply)")
    for name in ("plan.md", "plan-prompt.md", "solo-prompt.md", "review.md", "review-verdict.schema.json", "blind-review.md"):
        if not (cfg["templates_dir"] / name).exists():
            problems.append(f"template missing: {name}")
    all_tasks = load_tasks(cfg, ready_only=False)
    ready = [t for t in all_tasks if t.get("status") == "ready"]
    print(f"tasks: {len(all_tasks)} ({len(ready)} ready)")
    for t in ready:
        tdir = cfg["tests_dir"] / t["id"]
        for rel in t.get("acceptance_tests", []) + t.get("hidden_tests", []) + t.get("mutants", []):
            if not (tdir / rel).exists():
                problems.append(f"{t['id']}: missing {tdir / rel}")
        if not t.get("acceptance_tests"):
            problems.append(f"{t['id']}: no acceptance_tests")
        if t["leak_trap"] and not (t.get("hidden_tests") or t.get("mutants")):
            problems.append(f"{t['id']}: leak_trap without hidden_tests or mutants")
        if not xpath(cfg.get("repo_paths", {}).get(t["repo"], str(Path.home() / t["repo"]))).exists():
            problems.append(f"{t['id']}: repo {t['repo']} not found")
        vj = cfg["eval_root"] / "prep" / t["id"] / "verify.json"
        if not vj.exists() or not json.loads(vj.read_text()).get("ready"):
            problems.append(f"{t['id']}: verify-task が PASS していない（{vj}）")
    for p in problems:
        print("FAIL:", p)
    print("OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


def cmd_schedule(cfg: dict, a) -> int:
    tasks = load_tasks(cfg, a.tasks.split(",") if a.tasks else None)
    reps = range(a.rep_start, a.rep_start + a.reps)
    jobs = [{"task": t["id"], "arm": arm, "rep": rep} for t in tasks for arm in a.arms.split(",") for rep in reps]
    random.Random(a.seed).shuffle(jobs)
    out = cfg["eval_root"] / "schedule.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    old = json.loads(out.read_text()) if out.exists() else None
    if old and a.rep_start > 1:  # INCONCLUSIVE の追加反復: 既存の schedule の後ろに足す
        old.setdefault("extensions", []).append({"seed": a.seed, "created_at": now(), "reps": list(reps)})
        old["jobs"] += jobs
        out.write_text(json.dumps(old, indent=1))
    else:
        out.write_text(json.dumps({"seed": a.seed, "created_at": now(), "jobs": jobs}, indent=1))
    print(f"{len(jobs)} jobs -> {out}")
    return 0


def cmd_run(cfg: dict, a) -> int:
    sched = json.loads((cfg["eval_root"] / "schedule.json").read_text())["jobs"]
    results = cfg["eval_root"] / "results.jsonl"
    done = set()
    if results.exists():
        done = {json.loads(x)["rid"] for x in results.read_text().splitlines() if x.strip() and "harness_error" not in x}
    tasks = {t["id"]: t for t in load_tasks(cfg)}
    jobs = [j for j in sched if f"{j['task']}-{j['arm']}-r{j['rep']}" not in done and j["task"] in tasks][: a.limit or None]
    vfile = cfg["eval_root"] / "versions.json"
    v0 = cli_versions()
    if vfile.exists() and json.loads(vfile.read_text()) != v0:
        log(f"STOP: CLI の版が開始時と違う {json.loads(vfile.read_text())} -> {v0}（設計書 §9）")
        return 3
    vfile.write_text(json.dumps(v0))
    log(f"{len(jobs)} runs to do ({len(done)} recorded) versions={v0}")
    errors: list[bool] = []

    def work(j):
        for attempt in range(1, 13):
            if STOP.is_set():
                return
            if not a.dry_run and cli_versions() != v0:
                STOP.set()
                log(f"STOP: CLI の版が実行中に変わった（{cli_versions()}）。新しい run を始めない")
                return
            try:
                rec = run_one(cfg, tasks[j["task"]], j["arm"], j["rep"], a.dry_run)
            except Exception as exc:  # noqa: BLE001 - 記録して続ける
                rec = {"rid": f"{j['task']}-{j['arm']}-r{j['rep']}", "harness_error": f"{type(exc).__name__}: {exc}"[-1500:]}
            if rec is None:
                return
            if rec.get("auth_error"):
                STOP.set()
                log(f"STOP: 認証エラー {rec['rid']}（記録しない）。ログインはしない。owner に報告する")
                return
            if rec.get("rate_limited"):
                log(f"rate limited {rec['rid']} (try {attempt}); sleeping 30 min")
                time.sleep(1800)
                continue
            err = rec.get("harness_error", "")
            with LOCK:
                errors.append(bool(err))
                if re.search(r"No space left|Disk quota", err) or errors[-3:] == [True, True, True]:
                    STOP.set()
                    log(f"STOP: 基盤エラーが続いた／ディスク不足: {err[:300]}")
            with LOCK, results.open("a") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            fin = rec.get("final") or {}
            log(f"done {rec['rid']}: checks={fin.get('checks_passed')} acc={fin.get('acceptance')} hidden={fin.get('hidden')} "
                f"int={rec.get('interventions')} err={rec.get('harness_error', '')[:120]}")
            return

    with ThreadPoolExecutor(a.parallel or cfg.get("parallel", 1)) as pool:
        list(pool.map(work, jobs))
    return 3 if STOP.is_set() else 0


def cmd_grade(cfg: dict, a) -> int:
    task_id = a.rid.split("-")[0]
    task = load_tasks(cfg, [task_id])[0]
    run_dir = cfg["eval_root"] / "runs" / a.rid
    print(json.dumps(grade(cfg, task, run_dir / "wt", run_dir, tag="regrade"), ensure_ascii=False, indent=1))
    return 0


def patch_files(patch: Path) -> list[str]:
    files = []
    for line in patch.read_text().splitlines():
        if line.startswith("+++ b/"):
            files.append(line[6:].strip())
    return files


def cmd_verify_task(cfg: dict, a) -> int:
    """§4.2 の ready 条件を機械検証する。base で acceptance が落ちる / 参照解で check・acceptance・hidden が全件 pass /
    罠版（参照解の上に当てる trap patch）で hidden が落ちる。テスト追加の題材は、ミュータントが base に当たり、
    base の既存 test では落ちず、参照解の test で全部落ちることも確かめる。結果は eval_root/prep/<id>/verify.json。"""
    task = load_tasks(cfg, [a.task], ready_only=False)[0]
    tdir = cfg["tests_dir"] / task["id"]
    prep = cfg["eval_root"] / "prep" / task["id"]
    out = prep / "grades"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    rep: dict = {"task": task["id"], "at": now(), "problems": []}
    bad = rep["problems"].append
    for key in ("acceptance_tests", "hidden_tests", "mutants"):
        for rel in task.get(key, []):
            if not (tdir / rel).exists():
                bad(f"missing {key}: {rel}")
    has_hidden = bool(task.get("hidden_tests") or task.get("mutants"))
    for key in ("reference", "trap") if has_hidden else ("reference",):  # 隠しテストの無い題材（S05）は trap 不要
        if not task.get(key) or not (tdir / task[key]).exists():
            bad(f"missing {key} patch")
    if not task.get("acceptance_tests"):
        bad("no acceptance_tests")
    if task["leak_trap"] and not (task.get("hidden_tests") or task.get("mutants")):
        bad("leak_trap without hidden_tests or mutants")
    if rep["problems"]:
        return finish_verify(prep, rep)
    wt = make_worktree(cfg, task, task["id"], sub="prep")

    def summ(g):
        return {k: g[k] for k in ("checks", "checks_passed", "acceptance", "hidden", "mutants")} | {
            "diff": {k: g["diff"][k] for k in ("files", "lines", "out_of_scope")}}

    gb = grade(cfg, task, wt, out, "base")
    rep["base"] = summ(gb)
    if not gb["checks_passed"]:
        bad(f"base: 必須 check が落ちる {gb['checks']}")
    if gb["acceptance"]["all"]:
        bad("base: acceptance が全件 pass してしまう")
    if task.get("mutants"):
        g = copy_for_grading(cfg, wt, out, "base-existing")
        existing = [f for f in (task.get("mutant_test_files") or patch_files(tdir / task["reference"]))
                    if f.startswith("tests/") and (g / f).exists()]
        ms = mutant_score(cfg, task, g, [], out, "base-existing", agent_tests=existing)
        shutil.rmtree(g, ignore_errors=True)
        rep["base_existing_tests_vs_mutants"] = ms
        if ms["applied"] != ms["total"]:
            bad("mutant patch が base に当たらない")
        if existing and ms["killed"]:
            bad(f"base の既存 test（{existing}）が mutant を {ms['killed']} 個落としてしまう")
    r = sh(["git", "-C", str(wt), "apply", str(tdir / task["reference"])], check=False)
    if r.returncode:
        bad(f"reference が当たらない: {r.stderr[-500:]}")
        return finish_verify(prep, rep)
    gr = grade(cfg, task, wt, out, "reference")
    rep["reference"] = summ(gr)
    if not gr["checks_passed"]:
        bad(f"reference: 必須 check が落ちる {gr['checks']}")
    if not gr["acceptance"]["all"]:
        bad(f"reference: acceptance {gr['acceptance']}")
    if gr["hidden"]["total"] and not gr["hidden"]["all"]:
        bad(f"reference: hidden {gr['hidden']}")
    if gr["diff"]["out_of_scope"]:
        bad(f"reference: scope 外 {gr['diff']['out_of_scope']}")
    if gr["diff"]["n_files"] > task["diff_budget"]["files"] or gr["diff"]["lines"] > task["diff_budget"]["lines"]:
        rep["warning"] = f"reference が差分予算を超える（{gr['diff']['n_files']} files / {gr['diff']['lines']} lines）"
    if not has_hidden:
        return finish_verify(prep, rep)
    r = sh(["git", "-C", str(wt), "apply", str(tdir / task["trap"])], check=False)
    if r.returncode:
        bad(f"trap が reference の上に当たらない: {r.stderr[-500:]}")
        return finish_verify(prep, rep)
    gt = grade(cfg, task, wt, out, "trap")
    rep["trap"] = summ(gt)
    if not gt["hidden"]["total"] or gt["hidden"]["all"]:
        bad(f"trap: hidden が落ちない {gt['hidden']}")
    if not a.keep:
        m = mirror(cfg, task["repo"])
        sh(["git", "-C", str(m), "worktree", "remove", "--force", str(wt)], check=False)
    return finish_verify(prep, rep)


def finish_verify(prep: Path, rep: dict) -> int:
    rep["ready"] = not rep["problems"]
    prep.mkdir(parents=True, exist_ok=True)
    (prep / "verify.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1))
    print(json.dumps(rep, ensure_ascii=False, indent=1))
    print("READY" if rep["ready"] else "NOT READY")
    return 0 if rep["ready"] else 1


def valid_rids(cfg: dict) -> set[str]:
    results = cfg["eval_root"] / "results.jsonl"
    if not results.exists():
        return set()
    rows = [json.loads(x) for x in results.read_text().splitlines() if x.strip()]
    return {r["rid"] for r in rows if "harness_error" not in r and not r.get("contaminated") and not r.get("rate_limited")}


def cmd_blind_pack(cfg: dict, a) -> int:
    rng = random.Random(a.seed)
    out = cfg["eval_root"] / "blind"
    out.mkdir(parents=True, exist_ok=True)
    mapping = {}
    tasks = {t["id"]: t for t in load_tasks(cfg)}
    ok = valid_rids(cfg)
    for tid, task in tasks.items():
        runs = sorted(p.parent.name for p in (cfg["eval_root"] / "runs").glob(f"{tid}-*-r*/final.diff") if p.parent.name in ok)
        if not runs:
            continue
        for vset in ("v1", "v2"):
            order = runs[:]
            rng.shuffle(order)
            parts = [template(cfg, "blind-review.md"), f"## タスク {tid}（set {vset}）\n\n# {task['title']}\n\n{task['body']}",
                     f"scope: {', '.join(task['scope_paths'])}"]
            for i, rid in enumerate(order):
                letter = chr(ord("A") + i)
                mapping[f"{tid}-{vset}-{letter}"] = rid
                diff = (cfg["eval_root"] / "runs" / rid / "final.diff").read_text()
                parts.append(f"## 候補 {letter}\n\n```diff\n{diff}\n```")
            (out / f"{tid}-{vset}.md").write_text("\n\n".join(parts))
    (cfg["eval_root"] / "blind-map.json").write_text(json.dumps(mapping, indent=1))
    print(f"packs -> {out}; map -> {cfg['eval_root'] / 'blind-map.json'}（reviewer に見せない）")
    return 0


def codex_text_call(cfg: dict, rv: dict, prompt: str, cwd: Path, out: Path) -> dict:
    """盲検採点用の Codex 呼び出し（read-only sandbox、git repo の外の空ディレクトリで実行）。"""
    last = out.with_suffix(".last.txt")
    cmd = ["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-C", str(cwd), "-m", rv["codex_model"],
           "-c", f"model_reasoning_effort={rv['codex_effort']}", "--json", "-o", str(last), "-"]
    t0 = time.monotonic()
    try:
        r = sh(cmd, cwd=cwd, timeout=cfg["timeouts_s"]["codex"], check=False, stdin_text=prompt)
        raw, rc, err = r.stdout, r.returncode, r.stderr
    except subprocess.TimeoutExpired:
        raw, rc, err = "", "timeout", ""
    out.write_text(raw)
    used_tools = '"command_execution"' in raw or '"file_change"' in raw
    out.with_suffix(".jsonl").write_text(raw)
    return {"exit": rc, "wall_s": round(time.monotonic() - t0), "result": last.read_text() if last.exists() else "",
            "used_tools": used_tools, **codex_usage(out.with_suffix(".jsonl")),
            "rate_limited": bool(rc not in (0, "timeout") and RATE_LIMIT.search(err[-3000:] + raw[-3000:])),
            "auth_error": bool(rc not in (0, "timeout") and AUTH_ERROR.search(err[-3000:] + raw[-3000:]))}


def parse_score(text: str) -> dict:
    for m in reversed(list(re.finditer(r"```(?:json)?\s*(\{.*?\})\s*```", text or "", re.S))):
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    m = re.search(r"\{.*\}", text or "", re.S)
    try:
        return json.loads(m.group(0)) if m else {}
    except json.JSONDecodeError:
        return {}


def cmd_blind_review(cfg: dict, a) -> int:
    """盲検 pack を、config の blind_reviewers の全員（既定: Opus と Codex の別系統モデル）が独立に採点する（二重採点）。
    reviewer はツールを使わない（Claude は --tools ""、Codex は read-only で空ディレクトリ）。対応表は渡さない。"""
    packs = sorted((cfg["eval_root"] / "blind").glob("S*-v*.md"))
    reviewers = cfg["blind_reviewers"]
    cwd = cfg["eval_root"] / "blind-cwd"
    cwd.mkdir(parents=True, exist_ok=True)
    jobs = [(p, rv) for p in packs for rv in reviewers]

    def one(job):
        p, rv = job
        out = p.with_name(f"{p.stem}.{rv['name']}.score.json")
        if out.exists() or STOP.is_set():
            return
        if a.dry_run:
            log(f"DRY blind review {p.name} by {rv['name']}")
            return
        letters = re.findall(r"^## 候補 ([A-Z])$", p.read_text(), re.M)
        for attempt in range(1, 4):
            raw = p.with_name(f"{p.stem}.{rv['name']}.raw{attempt}.json")
            if rv["kind"] == "claude":
                r = claude_call(cfg, rv, p.read_text(), cwd, raw, write=False, toolset=[])
            else:
                r = codex_text_call(cfg, rv, p.read_text(), cwd, raw)
            if r.get("auth_error"):
                STOP.set()
                log(f"STOP: 認証エラー（blind {rv['name']}）")
                return
            if r.get("rate_limited"):
                log(f"rate limited blind {p.name} {rv['name']}; sleeping 30 min")
                time.sleep(1800)
                continue
            s = parse_score(r.get("result") or "")
            if set(letters) <= set((s.get("scores") or {})):
                s["_meta"] = {"reviewer": rv["name"], "attempt": attempt, "cost_usd": r.get("cost_usd"),
                              "used_tools": r.get("used_tools", False),
                              "usage": {k: r.get(k) for k in ("input_tokens", "cached_input_tokens", "output_tokens",
                                                               "cache_read_tokens", "cache_write_tokens")}}
                out.write_text(json.dumps(s, ensure_ascii=False, indent=1))
                log(f"scored {p.name} by {rv['name']} (try {attempt})")
                return
            log(f"unparsed score {p.name} by {rv['name']} (try {attempt})")
        out.with_suffix(".failed").write_text("unparsed after 3 tries")

    with ThreadPoolExecutor(cfg.get("parallel", 1)) as pool:
        list(pool.map(one, jobs))
    return 3 if STOP.is_set() else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    s = sub.add_parser("schedule")
    s.add_argument("--arms", default="A,B,C")
    s.add_argument("--reps", type=int, default=2)
    s.add_argument("--rep-start", type=int, default=1)
    s.add_argument("--seed", type=int, default=20261003)
    v = sub.add_parser("verify-task")
    v.add_argument("task")
    v.add_argument("--keep", action="store_true")
    s.add_argument("--tasks")
    r = sub.add_parser("run")
    r.add_argument("--dry-run", action="store_true")
    r.add_argument("--limit", type=int)
    r.add_argument("--parallel", type=int)
    g = sub.add_parser("grade")
    g.add_argument("rid")
    b = sub.add_parser("blind-pack")
    b.add_argument("--seed", type=int, default=7)
    br = sub.add_parser("blind-review")
    br.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.config)
    os.environ["AGENTS_TOOLKIT_SLACK_NOTIFY"] = "off"  # 各 claude -p の Stop hook で Slack 通知を出さない
    return {"check": cmd_check, "verify-task": cmd_verify_task, "schedule": cmd_schedule, "run": cmd_run,
            "grade": cmd_grade, "blind-pack": cmd_blind_pack, "blind-review": cmd_blind_review}[a.cmd](cfg, a)


if __name__ == "__main__":
    sys.exit(main())

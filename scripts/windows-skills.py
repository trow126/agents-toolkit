#!/usr/bin/env python3
"""windows-skills — Claude desktop app (Windows) 向け skill copy の生成・配布・検証 (agents-toolkit).

usage:
  windows-skills.py validate [--repo DIR]
  windows-skills.py render --skill NAME --out DIR [--distro D] [--repo DIR]
  windows-skills.py {dry-run,apply,check} [--target DIR] [--distro D] [--repo DIR]

bootstrap.sh --windows-{dry-run,apply,check} から呼ばれる。install/windows-skills.tsv に列挙した
skill だけを、source（WSL へ symlink 配布しているものと同じ）から変換して
<target>/skills/<skill>/ へコピーする。source は二重管理しない: Windows 版は毎回ここで生成する。

変換（*.md のみ。その他のファイルはそのままコピー）:
  - code span・fenced code block 行の `~/.claude/bin/<helper> [<args>]` と `<helper> <args>`
    （helper は windows-skills.tsv の宣言）を `wsl -d <distro> -- bash -lc '~/.claude/bin/<helper> <args>'` にする
  - 先頭（SKILL.md は frontmatter の直後）に「生成物・手で編集しない」marker comment を入れる
  - helper を使う skill の SKILL.md には H1 の直後に Windows での実行規則の節を入れる
配布先の各 skill directory には .agents-toolkit-generated.json（生成元 commit・生成日時・file hash）を置く。

安全規則:
  - 管理するのは windows-skills.tsv の skill directory と、marker を持つ旧配布 directory だけ
  - marker の無い既存 directory（手書き）・symlink・marker の hash と合わない（手で編集された）
    directory があれば、apply は何も書かずに停止する
  - target（Windows の .claude）は自動検出（cmd.exe の %USERPROFILE%）か --target /
    AGENTS_TOOLKIT_WINDOWS_CLAUDE_DIR。存在しなければ停止する（作らない）
exit: 0 = ok, 1 = drift / 停止 / エラー
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True

LIST_REL = "install/windows-skills.tsv"
MANIFEST_REL = "install/manifest.tsv"
MARKER = ".agents-toolkit-generated.json"
STAGING_PREFIX = ".agents-toolkit-staging-"
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
HELPER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
DISTRO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
FENCE_RE = re.compile(r"^(`{3,}|~{3,})")
CODE_SPAN_RE = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)")
BIN_PATH_RE = re.compile(r"^~/\.claude/bin/([A-Za-z0-9_.-]+)(\s+\S.*)?$", re.DOTALL)
BARE_HELPER_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_.-]*)(\s+\S.*)$", re.DOTALL)
SKIP_DIRS = {"__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache", ".venv"}
VALIDATE_DISTRO = "Ubuntu"
VALIDATE_HOME = "/home/user"


class StopError(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    skill: str
    source: str
    helpers: tuple[str, ...]
    line: int


# ---- list --------------------------------------------------------------------------------------
def manifest_claude_sources(repo: Path) -> dict[str, str]:
    """skill name -> source of the manifest line that link-dir distributes it to ~/.claude/skills."""
    result: dict[str, str] = {}
    for raw in (repo / MANIFEST_REL).read_text(encoding="utf-8").splitlines():
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            continue
        mode, source, target = fields
        m = re.fullmatch(r"\.claude/skills/([^/]+)", target)
        if mode == "link-dir" and m:
            result[m.group(1)] = source
    return result


def frontmatter_name(text: str) -> str | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    for line in text[4:end].splitlines():
        if line.startswith("name:"):
            return line.split(":", 1)[1].strip().strip("\"'")
    return None


def load_list(repo: Path) -> list[Entry]:
    path = repo / LIST_REL
    if not path.is_file():
        raise StopError(f"{LIST_REL} が見つかりません")
    claude_sources = manifest_claude_sources(repo)
    errors: list[str] = []
    entries: list[Entry] = []
    seen: set[str] = set()
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        where = f"{LIST_REL}:{line_no}"
        if len(fields) != 3 or not all(fields):
            errors.append(f"{where}: skill<TAB>source<TAB>helpers の3列（空欄不可）が必要です")
            continue
        skill, source, helpers_field = fields
        if not SKILL_NAME_RE.fullmatch(skill):
            errors.append(f"{where}: 不正な skill 名: {skill}")
            continue
        if skill in seen:
            errors.append(f"{where}: skill が重複しています: {skill}")
        seen.add(skill)
        if source.startswith("/") or ".." in source.split("/"):
            errors.append(f"{where}: source は repo 相対 path（.. 禁止）にしてください: {source}")
            continue
        if claude_sources.get(skill) != source:
            errors.append(
                f"{where}: {source} は {MANIFEST_REL} で .claude/skills/{skill} へ link-dir 配布されていません"
            )
        skill_md = repo / source / "SKILL.md"
        if not skill_md.is_file():
            errors.append(f"{where}: SKILL.md がありません: {source}/SKILL.md")
        elif frontmatter_name(skill_md.read_text(encoding="utf-8")) != skill:
            errors.append(f"{where}: {source}/SKILL.md の frontmatter name が {skill} ではありません")
        helpers: tuple[str, ...] = ()
        if helpers_field != "-":
            helpers = tuple(h.strip() for h in helpers_field.split(","))
            for helper in helpers:
                if not HELPER_RE.fullmatch(helper):
                    errors.append(f"{where}: 不正な helper 名: {helper!r}")
                    continue
                helper_path = repo / "claude" / "bin" / helper
                if not helper_path.is_file() or not os.access(helper_path, os.X_OK):
                    errors.append(f"{where}: helper が claude/bin に実行可能ファイルとしてありません: {helper}")
        entries.append(Entry(skill, source, helpers, line_no))
    if errors:
        raise StopError("\n".join(errors))
    return entries


# ---- render ------------------------------------------------------------------------------------
def wrap(command: str, distro: str, where: str) -> str:
    if "'" in command:
        raise StopError(f"{where}: single quote を含む helper 呼び出しは自動変換できません: {command}")
    return f"wsl -d {distro} -- bash -lc '{command}'"


class Converter:
    def __init__(self, entry: Entry, distro: str, home: str):
        self.entry = entry
        self.distro = distro
        self.home = home
        self.converted = 0

    def helper_command(self, text: str, where: str) -> str | None:
        """The full helper command when `text` is a declared helper path (with or without
        arguments) or a declared helper name followed by arguments."""
        m = BIN_PATH_RE.match(text)
        if m:
            if m.group(1) not in self.entry.helpers:
                raise StopError(
                    f"{where}: ~/.claude/bin/{m.group(1)} は {LIST_REL} の helpers に宣言されていません"
                )
            return text
        m = BARE_HELPER_RE.match(text)
        if m and m.group(1) in self.entry.helpers:
            return f"~/.claude/bin/{m.group(1)}{m.group(2)}"
        return None

    def convert_span(self, match: re.Match, where: str) -> str:
        ticks, content = match.group(1), match.group(2)
        command = self.helper_command(content, where)
        if command is None:
            return match.group(0)
        self.converted += 1
        return f"{ticks}{wrap(command, self.distro, where)}{ticks}"

    def convert_markdown(self, text: str, rel: str) -> str:
        out: list[str] = []
        fence = ""
        for line_no, line in enumerate(text.split("\n"), 1):
            where = f"{self.entry.source}/{rel}:{line_no}"
            stripped = line.lstrip()
            indent = line[: len(line) - len(stripped)]
            m = FENCE_RE.match(stripped)
            if fence:
                if m and stripped.rstrip() == m.group(1) and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                    fence = ""
                else:
                    command = self.helper_command(stripped.rstrip(), where)
                    if command is not None:
                        self.converted += 1
                        line = indent + wrap(command, self.distro, where)
                out.append(line)
                continue
            if m:
                fence = m.group(1)
                out.append(line)
                continue
            out.append(CODE_SPAN_RE.sub(lambda mm: self.convert_span(mm, where), line))
        return "\n".join(out)

    def marker_comment(self, rel: str) -> str:
        return (
            f"<!-- Generated by agents-toolkit (bootstrap.sh --windows-apply) from "
            f"{self.entry.source}/{rel} for the Claude desktop app on Windows. Do not edit by hand: "
            f"edit the source and run bootstrap.sh --windows-apply again. -->\n\n"
        )

    def windows_section(self) -> str:
        unc_home = f"\\\\wsl.localhost\\{self.distro}" + self.home.replace("/", "\\")
        d = self.distro
        return (
            "## Windows (Claude desktop app)\n\n"
            f"This copy runs in the Claude desktop app on Windows. Its helpers stay in WSL (`{d}`), so every helper "
            f"command below is already wrapped as `wsl -d {d} -- bash -lc '...'`.\n\n"
            "- Run a wrapped command from the Bash tool (Git Bash) with the prefix `MSYS_NO_PATHCONV=1`. The "
            "PowerShell tool also works as written, but Windows PowerShell 5.1 drops double quotes inside an "
            "argument, so use it only when no argument needs quoting.\n"
            "- `~` and every path passed to a helper are WSL paths. Convert a Windows path (for example a scratchpad "
            f"file) first with `wsl -d {d} -e wslpath -a '<windows path>'` (`C:\\...` becomes `/mnt/c/...`; `-e` "
            "keeps the Linux shell from eating the backslashes).\n"
            "- Write helper input files with the Write tool (UTF-8 without BOM). `Set-Content -Encoding utf8` in "
            "Windows PowerShell 5.1 adds a BOM that the helpers reject.\n"
            f"- Files that a helper writes under `~` are at `{unc_home}\\...` from Windows.\n\n"
        )

    def convert_entrypoint(self, text: str) -> str:
        if not text.startswith("---\n"):
            raise StopError(f"{self.entry.source}/SKILL.md: frontmatter がありません")
        end = text.find("\n---\n", 4)
        if end < 0:
            raise StopError(f"{self.entry.source}/SKILL.md: frontmatter が閉じていません")
        head, body = text[: end + 5], text[end + 5 :]
        body = self.convert_markdown(body, "SKILL.md")
        if self.entry.helpers:
            m = re.search(r"^# .*\n", body, re.MULTILINE)
            if m is None:
                raise StopError(f"{self.entry.source}/SKILL.md: H1 がありません")
            insert_at = m.end()
            if body[insert_at : insert_at + 1] == "\n":
                insert_at += 1
            body = body[:insert_at] + self.windows_section() + body[insert_at:]
        return head + self.marker_comment("SKILL.md") + body.lstrip("\n")


def source_files(source_dir: Path) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(source_dir, followlinks=True):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith((".pyc", ".pyo")) or name == MARKER:
                continue
            files.append(Path(dirpath) / name)
    return files


def render(repo: Path, entry: Entry, distro: str, home: str) -> dict[str, bytes]:
    source_dir = repo / entry.source
    converter = Converter(entry, distro, home)
    rendered: dict[str, bytes] = {}
    for path in source_files(source_dir):
        rel = path.relative_to(source_dir).as_posix()
        data = path.read_bytes()
        if rel == "SKILL.md":
            data = converter.convert_entrypoint(data.decode("utf-8")).encode("utf-8")
        elif rel.endswith(".md"):
            text = converter.convert_markdown(data.decode("utf-8"), rel)
            data = (converter.marker_comment(rel) + text).encode("utf-8")
        rendered[rel] = data
    if "SKILL.md" not in rendered:
        raise StopError(f"{entry.source}: SKILL.md がありません")
    if entry.helpers and converter.converted == 0:
        raise StopError(f"{entry.source}: helpers が宣言されていますが変換対象の呼び出しがありません（{LIST_REL} を更新してください）")
    if not rendered["SKILL.md"].startswith(b"---\n"):
        raise StopError(f"{entry.source}: 生成した SKILL.md が frontmatter で始まりません")
    if frontmatter_name(rendered["SKILL.md"].decode("utf-8")) != entry.skill:
        raise StopError(f"{entry.source}: 生成した SKILL.md の frontmatter name が {entry.skill} ではありません")
    return rendered


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_tree(dest: Path, files: dict[str, bytes], marker: dict | None) -> None:
    for rel, data in files.items():
        path = dest / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if marker is not None:
        (dest / MARKER).write_text(json.dumps(marker, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# ---- deployed state ----------------------------------------------------------------------------
@dataclass
class Deployed:
    state: str  # missing | unmanaged | edited | managed
    detail: str = ""
    files: dict[str, str] | None = None
    marker: dict | None = None


def inspect(dest: Path) -> Deployed:
    if not dest.exists() and not dest.is_symlink():
        return Deployed("missing")
    if dest.is_symlink() or not dest.is_dir():
        return Deployed("unmanaged", "directory ではない（symlink または file）")
    marker_path = dest / MARKER
    if not marker_path.is_file():
        return Deployed("unmanaged", f"{MARKER} が無い（手書きの directory とみなす）")
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        recorded = dict(marker["files"])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return Deployed("edited", f"{MARKER} を読めません: {exc}")
    actual: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(dest):
        dirnames.sort()
        for name in sorted(filenames):
            path = Path(dirpath) / name
            rel = path.relative_to(dest).as_posix()
            if rel == MARKER:
                continue
            actual[rel] = sha256(path.read_bytes())
    if actual != recorded:
        changed = sorted(
            rel for rel in set(actual) | set(recorded) if actual.get(rel) != recorded.get(rel)
        )
        return Deployed("edited", "生成後に変更されたファイル: " + ", ".join(changed), actual, marker)
    return Deployed("managed", files=actual, marker=marker)


# ---- environment -------------------------------------------------------------------------------
def resolve_distro(arg: str | None) -> str:
    distro = arg or os.environ.get("AGENTS_TOOLKIT_WSL_DISTRO") or os.environ.get("WSL_DISTRO_NAME")
    if not distro:
        raise StopError("WSL distro を決められません（WSL 内で実行するか --distro / AGENTS_TOOLKIT_WSL_DISTRO を指定）")
    if not DISTRO_RE.fullmatch(distro):
        raise StopError(f"不正な distro 名: {distro!r}")
    return distro


def resolve_target(arg: str | None) -> Path:
    value = arg or os.environ.get("AGENTS_TOOLKIT_WINDOWS_CLAUDE_DIR")
    if not value:
        try:
            profile = subprocess.run(
                ["cmd.exe", "/d", "/c", "echo %USERPROFILE%"], cwd="/mnt/c", capture_output=True,
                text=True, timeout=30, check=True,
            ).stdout.strip()
            if not profile or "%" in profile:
                raise StopError("cmd.exe から %USERPROFILE% を取得できません")
            home = subprocess.run(
                ["wslpath", "-u", profile], capture_output=True, text=True, timeout=30, check=True
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError) as exc:
            raise StopError(
                f"Windows の .claude を自動検出できません（{exc}）。--windows-target PATH を指定してください"
            ) from exc
        value = str(Path(home) / ".claude")
    target = Path(value)
    if not target.is_dir():
        raise StopError(f"target（Windows の .claude）が存在しません: {target}")
    return target


def git_info(repo: Path) -> tuple[str, bool]:
    try:
        commit = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True, check=True
        ).stdout.strip()
        dirty = bool(subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain", "--", "install", "claude", "shared", "scripts/windows-skills.py"],
            capture_output=True, text=True, check=True,
        ).stdout.strip())
        return commit, dirty
    except (OSError, subprocess.CalledProcessError):
        return "unknown", True


def warn_missing_helpers(entries: list[Entry]) -> None:
    bin_dir = Path.home() / ".claude" / "bin"
    for entry in entries:
        for helper in entry.helpers:
            if not os.access(bin_dir / helper, os.X_OK):
                print(f"WARN: WSL 側に {bin_dir / helper} がありません（bootstrap.sh --apply で配布してから使う）")


# ---- modes -------------------------------------------------------------------------------------
@dataclass
class Plan:
    entry: Entry | None
    dest: Path
    action: str  # create | update | ok | remove | blocked
    detail: str = ""
    rendered: dict[str, bytes] | None = None
    deployed: Deployed | None = None


def make_plan(repo: Path, target: Path, distro: str) -> list[Plan]:
    entries = load_list(repo)
    warn_missing_helpers(entries)
    skills_dir = target / "skills"
    if skills_dir.is_symlink() or (skills_dir.exists() and not skills_dir.is_dir()):
        raise StopError(f"{skills_dir} が directory ではありません")
    plans: list[Plan] = []
    if skills_dir.is_dir():
        for leftover in sorted(skills_dir.glob(STAGING_PREFIX + "*")):
            plans.append(Plan(None, leftover, "blocked", "前回の apply の作業 directory が残っています。中身を確認して手で片付けてください"))
    home = str(Path.home())
    names = {e.skill for e in entries}
    for entry in entries:
        dest = skills_dir / entry.skill
        rendered = render(repo, entry, distro, home)
        deployed = inspect(dest)
        want = {rel: sha256(data) for rel, data in rendered.items()}
        if deployed.state == "missing":
            plans.append(Plan(entry, dest, "create", rendered=rendered, deployed=deployed))
        elif deployed.state in {"unmanaged", "edited"}:
            plans.append(Plan(entry, dest, "blocked", deployed.detail, rendered, deployed))
        elif deployed.files == want and (deployed.marker or {}).get("distro") == distro:
            plans.append(Plan(entry, dest, "ok", rendered=rendered, deployed=deployed))
        else:
            changed = sorted(r for r in set(want) | set(deployed.files or {}) if want.get(r) != (deployed.files or {}).get(r))
            plans.append(Plan(entry, dest, "update", "変わるファイル: " + (", ".join(changed) or MARKER), rendered, deployed))
    if skills_dir.is_dir():
        for child in sorted(skills_dir.iterdir()):
            if child.name in names or child.name.startswith(STAGING_PREFIX) or child.is_symlink():
                continue
            if not (child / MARKER).is_file():
                continue  # 管理外: 触らない
            deployed = inspect(child)
            if deployed.state == "managed":
                plans.append(Plan(None, child, "remove", f"{LIST_REL} から外れた生成物", deployed=deployed))
            else:
                plans.append(Plan(None, child, "blocked", f"{LIST_REL} から外れた生成物ですが {deployed.detail}", deployed=deployed))
    return plans


def marker_for(entry: Entry, rendered: dict[str, bytes], distro: str, commit: str, dirty: bool) -> dict:
    return {
        "generator": "agents-toolkit scripts/windows-skills.py (bootstrap.sh --windows-apply)",
        "notice": "Generated copy. Do not edit by hand: edit the source in agents-toolkit and run bootstrap.sh --windows-apply.",
        "skill": entry.skill,
        "source": entry.source,
        "commit": commit,
        "dirty": dirty,
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "distro": distro,
        "files": {rel: sha256(data) for rel, data in rendered.items()},
    }


def describe_marker(deployed: Deployed | None) -> str:
    marker = (deployed.marker if deployed else None) or {}
    commit = str(marker.get("commit", "?"))[:12]
    return f"generated from {commit}{' (dirty)' if marker.get('dirty') else ''} at {marker.get('generated_at', '?')}"


def run_mode(mode: str, repo: Path, target: Path, distro: str) -> int:
    plans = make_plan(repo, target, distro)
    blocked = [p for p in plans if p.action == "blocked"]

    if mode == "check":
        problems = 0
        for p in plans:
            if p.action == "ok":
                print(f"ok: {p.dest} ({describe_marker(p.deployed)})")
            elif p.action == "create":
                print(f"DRIFT: {p.dest} がありません（bootstrap.sh --windows-apply で生成）")
                problems += 1
            elif p.action == "update":
                print(f"DRIFT: {p.dest} が source と異なります（{p.detail}; {describe_marker(p.deployed)}）")
                problems += 1
            elif p.action == "remove":
                print(f"DRIFT: {p.dest} は {p.detail}です（bootstrap.sh --windows-apply で削除）")
                problems += 1
            else:
                print(f"DRIFT: {p.dest}: {p.detail}")
                problems += 1
        print()
        if problems == 0:
            print(f"PASS: all {sum(1 for p in plans if p.entry)} Windows skill copies match their sources ({target / 'skills'})")
            return 0
        print(f"FAIL: {problems} Windows skill entries drifted", file=sys.stderr)
        return 1

    if blocked:
        for p in blocked:
            print(f"ERROR: {p.dest}: {p.detail}。上書きせず停止します", file=sys.stderr)
        return 1

    if mode == "dry-run":
        for p in plans:
            verb = {"create": "would create", "update": "would update", "remove": "would remove", "ok": "ok"}[p.action]
            suffix = f" ({p.detail})" if p.detail else ""
            print(f"{verb}: {p.dest}{suffix}")
        return 0

    commit, dirty = git_info(repo)
    skills_dir = target / "skills"
    skills_dir.mkdir(exist_ok=True)
    for p in plans:
        if p.action == "ok":
            print(f"ok: {p.dest}")
        elif p.action in {"create", "update"}:
            assert p.entry is not None and p.rendered is not None
            staging = skills_dir / f"{STAGING_PREFIX}{p.entry.skill}"
            write_tree(staging, p.rendered, marker_for(p.entry, p.rendered, distro, commit, dirty))
            if p.action == "update":
                old = skills_dir / f"{STAGING_PREFIX}{p.entry.skill}.old"
                p.dest.rename(old)
                staging.rename(p.dest)
                shutil.rmtree(old)
            else:
                staging.rename(p.dest)
            print(f"{'created' if p.action == 'create' else 'updated'}: {p.dest} (from {p.entry.source} @ {commit[:12]}{' dirty' if dirty else ''})")
        elif p.action == "remove":
            shutil.rmtree(p.dest)
            print(f"removed: {p.dest} ({p.detail})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="windows-skills.py", description=__doc__.split("\n")[0])
    parser.add_argument("mode", choices=["validate", "render", "dry-run", "apply", "check"])
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--target", help="Windows 側の .claude directory（WSL path）")
    parser.add_argument("--distro", help="WSL distro 名（既定: $AGENTS_TOOLKIT_WSL_DISTRO / $WSL_DISTRO_NAME）")
    parser.add_argument("--skill", help="render: 対象 skill")
    parser.add_argument("--out", help="render: 出力 directory（存在しないこと）")
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    try:
        if args.mode == "validate":
            entries = load_list(repo)
            for entry in entries:
                render(repo, entry, VALIDATE_DISTRO, VALIDATE_HOME)
            print(f"PASS: {LIST_REL} ({len(entries)} skills) renders cleanly")
            return 0
        if args.mode == "render":
            if not args.skill or not args.out:
                raise StopError("render には --skill と --out が必要です")
            entries = {e.skill: e for e in load_list(repo)}
            if args.skill not in entries:
                raise StopError(f"{LIST_REL} に無い skill: {args.skill}")
            out = Path(args.out)
            if out.exists():
                raise StopError(f"--out は存在しない path にしてください: {out}")
            write_tree(out, render(repo, entries[args.skill], resolve_distro(args.distro), str(Path.home())), None)
            print(f"rendered: {out}")
            return 0
        return run_mode(args.mode, repo, resolve_target(args.target), resolve_distro(args.distro))
    except StopError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

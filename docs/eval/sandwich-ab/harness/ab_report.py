#!/usr/bin/env python3
"""ab_report — sandwich-ab の結果を集計し、事前登録した判定基準（CRITERIA）を当てる。

usage: ab_report.py [--config PATH] [--boot 10000] [--seed 1] [--json OUT]

入力: eval_root/results.jsonl、eval_root/blind/*.<reviewer>.score.json と blind-map.json（あれば）、config の単価。
出力: Markdown（標準出力）。判定は ADOPT / REJECT / INCONCLUSIVE / PENDING（単価未設定）。
CRITERIA の値は実行前に設計書（docs/eval/sandwich-ab-design.md §7）と一致させて固定し、結果を見てから変えない。

盲検の品質（基準 4）は、二重採点（Opus と Codex の別系統モデル）の reviewer 平均で判定する（設計書 §6.5、2026-10-03 追記）。
reviewer ごとの値と、両者の一致度（Pearson・Spearman・平均絶対差・基準 4 の可否の一致）も併記する。
"""
from __future__ import annotations

import argparse
import json
import random
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

from sandwich_ab import DEFAULT_CONFIG, load_config

# 事前登録（設計書 §7 と同じ値）。結果を見た後に変えない。
CRITERIA = {
    "cost_ratio_max": 0.70,          # B の費用 / A の費用（題材ごとの平均費用の合計比）
    "cost_ratio_upper_max": 0.85,    # その bootstrap 95% 上限
    "success_diff_min": -0.05,       # B − A の成功率（点推定）
    "success_diff_lower_min": -0.15, # その bootstrap 95% 下限
    "leak_fail_margin": 1,           # leak 題材で、B の隠しテスト失敗 run 数 ≤ A + 1
    "quality_diff_min": -1.0,        # 盲検の合計点（25 点満点）B − A（reviewer 平均）
    # REJECT の境界
    "reject_cost_ratio": 0.85,
    "reject_success_diff": -0.10,
    "reject_leak_margin": 3,
}
AXES = ("requirements", "correctness", "leakage", "tests", "design")


def run_cost(rec: dict, prices: dict, uncached_override: dict | None = None) -> float | None:
    """Claude は total_cost_usd。Codex は turn.completed の usage × 公式単価。
    input_tokens は cached と cache write を含む総数として扱い、非 cache 入力 = input − cached − cache_write。
    前提: Codex の output_tokens は reasoning_output_tokens を含む（2026-10-03 のスモーク run で reasoning < output を確認。設計書 §8）。"""
    total = sum(c.get("cost_usd") or 0.0 for c in rec.get("claude", []))
    for c in rec.get("codex", []):
        model = c.get("model") or "gpt-6.1-sol"
        p = prices.get(model) or {}
        if any(p.get(k) is None for k in ("input", "cached_input", "cache_write_input", "output")):
            return None
        inp = (uncached_override or {}).get(model, p["input"])
        cw = c.get("cache_write_input_tokens") or 0
        uncached = c["input_tokens"] - c["cached_input_tokens"] - cw
        total += (uncached * inp + c["cached_input_tokens"] * p["cached_input"] + cw * p["cache_write_input"]
                  + c["output_tokens"] * p["output"]) / 1e6
    return total


def success(rec: dict) -> bool:
    f = rec.get("final") or {}
    hidden_ok = f.get("hidden", {}).get("all", True) if f.get("hidden", {}).get("total") else True
    return bool(f.get("checks_passed") and f.get("acceptance", {}).get("all") and hidden_ok
                and not f.get("diff", {}).get("out_of_scope"))


def load_all(cfg: dict) -> list[dict]:
    p = cfg["eval_root"] / "results.jsonl"
    rows = [json.loads(x) for x in p.read_text().splitlines() if x.strip()] if p.exists() else []
    latest = {}
    for r in rows:  # 同じ rid は最後の記録を採る（harness_error の後の再実行）
        latest[r["rid"]] = r
    return list(latest.values())


def excluded_reason(r: dict) -> str | None:
    if "harness_error" in r:
        return "harness_error"
    if r.get("contaminated"):
        return "contaminated"
    if r.get("rate_limited"):
        return "rate_limited"
    return None


def blind_scores(cfg: dict) -> tuple[dict, list]:
    """戻り値: {reviewer: {rid: [total, ...]}}, [(pack, letter, reviewer, rid, scores)]"""
    mp = cfg["eval_root"] / "blind-map.json"
    if not mp.exists():
        return {}, []
    mapping = json.loads(mp.read_text())
    out: dict = defaultdict(lambda: defaultdict(list))
    flat = []
    for f in sorted((cfg["eval_root"] / "blind").glob("*.score.json")):
        m = re.match(r"(S\d+)-(v\d+)\.([A-Za-z0-9_-]+)\.score\.json$", f.name)
        if not m:
            continue
        task, vset, reviewer = m.groups()
        s = json.loads(f.read_text() or "{}")
        for letter, sc in (s.get("scores") or {}).items():
            rid = mapping.get(f"{task}-{vset}-{letter}")
            if rid:
                tot = sum(float(sc.get(k, 0) or 0) for k in AXES)
                out[reviewer][rid].append(tot)
                flat.append((f"{task}-{vset}", letter, reviewer, rid, sc))
    return out, flat


def per_task(rows, arm, fn):
    by = defaultdict(list)
    for r in rows:
        if r["arm"] == arm:
            v = fn(r)
            if v is not None:
                by[r["task"]].append(v)
    return {t: statistics.mean(v) for t, v in by.items()}


def boot(tasks, stat, n, seed):
    rng = random.Random(seed)
    vals = []
    for _ in range(n):
        sample = [rng.choice(tasks) for _ in tasks]
        v = stat(sample)
        if v is not None:
            vals.append(v)
    vals.sort()
    return vals[int(0.025 * len(vals))], vals[int(0.975 * len(vals)) - 1]


def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    r = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2
        i = j + 1
    return r


def pearson(x, y):
    if len(x) < 3 or statistics.pstdev(x) == 0 or statistics.pstdev(y) == 0:
        return None
    return statistics.correlation(x, y)


def fmt(v, nd=3):
    return "n/a" if v is None else (f"{v:.{nd}f}" if isinstance(v, float) else str(v))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    ap.add_argument("--boot", type=int, default=10000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--json", type=Path, help="主要な数値を JSON でも書き出す")
    a = ap.parse_args()
    cfg = load_config(a.config)
    prices = {k: v for k, v in cfg.get("prices_usd_per_mtok", {}).items() if not k.startswith("_")}
    sens = cfg.get("prices_sensitivity_uncached_as_cache_write")
    allrows = load_all(cfg)
    rows = [r for r in allrows if excluded_reason(r) is None]
    blind, flat = blind_scores(cfg)
    reviewers = sorted(blind)
    arms = sorted({r["arm"] for r in rows})
    summary: dict = {"criteria": CRITERIA, "n_rows": len(allrows), "n_valid": len(rows)}

    def blind_mean(rid, reviewer=None):
        """reviewer=None: reviewer ごとの平均（set 平均）を reviewer 間で平均。"""
        revs = [reviewer] if reviewer else reviewers
        vals = [statistics.mean(blind[rv][rid]) for rv in revs if blind.get(rv, {}).get(rid)]
        if reviewer is None and len(vals) < len(revs):
            return None  # 二重採点が揃わない run は主指標に入れない
        return statistics.mean(vals) if vals else None

    print("# sandwich-ab 結果\n")
    exc = Counter(excluded_reason(r) for r in allrows if excluded_reason(r))
    print(f"記録 {len(allrows)} run、集計対象 {len(rows)} run、除外 {dict(exc) or 0}\n")
    print("| arm | runs | 成功率 | acceptance 合格率 | 隠しテスト合格率（leak 題材） | 平均費用 USD | 平均時間 s | 人手介入/run | 盲検合計（25、reviewer 平均） |"
          + "".join(f" 盲検 {rv} |" for rv in reviewers))
    print("|---|---|---|---|---|---|---|---|---|" + "---|" * len(reviewers))
    summary["arms"] = {}
    for arm in arms:
        rs = [r for r in rows if r["arm"] == arm]
        leak = [r for r in rs if r["leak_trap"] and (r.get("final") or {}).get("hidden", {}).get("total")]
        costs = [run_cost(r, prices) for r in rs]
        bl = [v for r in rs if (v := blind_mean(r["rid"])) is not None]
        per_rv = {rv: [v for r in rs if (v := blind_mean(r["rid"], rv)) is not None] for rv in reviewers}
        st = {"runs": len(rs), "success": sum(map(success, rs)) / len(rs),
              "acceptance": sum((r.get("final") or {}).get("acceptance", {}).get("all", False) for r in rs) / len(rs),
              "hidden_pass_leak": (sum(r["final"]["hidden"]["all"] for r in leak) / len(leak)) if leak else None,
              "cost_mean": statistics.mean(costs) if None not in costs else None,
              "wall_mean": statistics.mean(r["wall_s"] for r in rs),
              "interventions_per_run": sum(len(r["interventions"]) for r in rs) / len(rs),
              "blind_mean": statistics.mean(bl) if bl else None,
              **{f"blind_{rv}": (statistics.mean(v) if v else None) for rv, v in per_rv.items()}}
        summary["arms"][arm] = st
        print(f"| {arm} | {len(rs)} | {st['success']:.2f} | {st['acceptance']:.2f} | {fmt(st['hidden_pass_leak'], 2)} "
              f"| {fmt(st['cost_mean'], 2)} | {st['wall_mean']:.0f} | {st['interventions_per_run']:.2f} | {fmt(st['blind_mean'], 2)} |"
              + "".join(f" {fmt(st[f'blind_{rv}'], 2)} |" for rv in reviewers))

    # token（provider 別）・時間・費用の内訳
    print("\n## token と費用の内訳（run 平均）\n")
    print("| arm | Claude 費用 USD | Claude 出力 token | Claude cache read | Codex 入力 | Codex cached | Codex 出力 | Codex reasoning | Codex 費用 USD（換算） | 費用（感度: 非 cache 入力を cache write 単価で） |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for arm in arms:
        rs = [r for r in rows if r["arm"] == arm]

        def avg(fn):
            return statistics.mean(fn(r) for r in rs)
        cc = avg(lambda r: sum(c.get("cost_usd") or 0 for c in r.get("claude", [])))
        co = avg(lambda r: sum(c.get("output_tokens") or 0 for c in r.get("claude", [])))
        cr = avg(lambda r: sum(c.get("cache_read_tokens") or 0 for c in r.get("claude", [])))
        xi = avg(lambda r: sum(c["input_tokens"] for c in r.get("codex", [])))
        xc = avg(lambda r: sum(c["cached_input_tokens"] for c in r.get("codex", [])))
        xo = avg(lambda r: sum(c["output_tokens"] for c in r.get("codex", [])))
        xr = avg(lambda r: sum(c["reasoning_output_tokens"] for c in r.get("codex", [])))
        tot = [run_cost(r, prices) for r in rs]
        tot_s = [run_cost(r, prices, sens) for r in rs] if sens else [None]
        xusd = statistics.mean(t for t in tot) - cc if None not in tot else None
        print(f"| {arm} | {cc:.2f} | {co:.0f} | {cr:.0f} | {xi:.0f} | {xc:.0f} | {xo:.0f} | {xr:.0f} | {fmt(xusd, 2)} "
              f"| {fmt(statistics.mean(tot_s) if None not in tot_s else None, 2)} |")

    b_rows = [r for r in rows if r["arm"] == "B"]
    if b_rows:
        caught = missed = 0
        must = sum(1 for r in b_rows for v in r.get("reviews", []) for f in v.get("findings", []) if f.get("severity") == "must_fix")
        cats = Counter(f.get("category") for r in b_rows for v in r.get("reviews", []) for f in v.get("findings", [])
                       if f.get("severity") == "must_fix")
        verdicts = Counter(v.get("verdict") for r in b_rows for v in r.get("reviews", []))
        false_alarm = 0
        for r in b_rows:
            for g, v in zip(r.get("round_grades", []), r.get("reviews", []), strict=False):
                hit = v.get("leak_suspected") or any(f.get("category") == "lookahead" for f in v.get("findings", []))
                if g.get("hidden", {}).get("total") and not g["hidden"]["all"]:
                    caught += bool(hit)
                    missed += not hit
                elif hit:
                    false_alarm += 1
        cost_parts = defaultdict(float)
        time_parts = defaultdict(float)
        for r in b_rows:
            for c in r.get("claude", []):
                stage = "plan" if c.get("stage") == "plan" else "review"
                cost_parts[stage] += c.get("cost_usd") or 0
                time_parts[stage] += c.get("wall_s") or 0
            for c in r.get("codex", []):
                time_parts["codex"] += c.get("wall_s") or 0
            tot = run_cost(r, prices)
            if tot is not None:
                cost_parts["total"] += tot
        rounds = Counter(len(r.get("codex", [])) for r in b_rows)
        ttot = sum(time_parts.values())
        print(f"\n## B の工程内レビュー\n\n- 判定の内訳 {dict(verdicts)}、must_fix 合計 {must}（category 別 {dict(cats)}）")
        print(f"- Codex の round 数の分布 {dict(sorted(rounds.items()))}、平均 {statistics.mean(len(r.get('codex', [])) for r in b_rows):.2f}")
        print(f"- リーク検出: 隠しテストが落ちた round のうち、レビューがリークを指摘した割合 {caught}/{caught + missed}"
              f"（隠しテストが通った round でのリーク指摘 {false_alarm} 件）")
        if cost_parts["total"]:
            print(f"- ハンドオフのオーバーヘッド: 費用のうち計画 {cost_parts['plan'] / cost_parts['total']:.1%}、"
                  f"レビュー {cost_parts['review'] / cost_parts['total']:.1%}")
        if ttot:
            print(f"- 時間（段階の合計に対する割合）: 計画 {time_parts['plan'] / ttot:.1%}、Codex {time_parts['codex'] / ttot:.1%}、"
                  f"レビュー {time_parts['review'] / ttot:.1%}")
        summary["B_review"] = {"must_fix": must, "caught": caught, "missed": missed, "false_alarm": false_alarm,
                               "verdicts": dict(verdicts), "plan_cost_share": cost_parts["plan"] / cost_parts["total"] if cost_parts["total"] else None,
                               "review_cost_share": cost_parts["review"] / cost_parts["total"] if cost_parts["total"] else None}

    # 人手介入の内訳とミュータント検出
    print("\n## 人手介入の内訳\n")
    for arm in arms:
        c = Counter(i.split(":")[0] + ":" + i.split(":")[1] if ":" in i else i for r in rows if r["arm"] == arm for i in r["interventions"])
        print(f"- {arm}: {dict(c) or 'なし'}")
    mut = [r for r in rows if (r.get("final") or {}).get("mutants")]
    if mut:
        print("\n## ミュータント検出率（テスト追加の題材）\n")
        for arm in arms:
            ms = [r["final"]["mutants"] for r in mut if r["arm"] == arm]
            if ms:
                print(f"- {arm}: {sum(m['killed'] for m in ms)}/{sum(m['total'] for m in ms)}（全部落とした run {sum(m['killed'] == m['total'] for m in ms)}/{len(ms)}）")

    # 二重採点の一致度
    if len(reviewers) >= 2:
        r1, r2 = reviewers[:2]
        pairs = defaultdict(dict)
        for pack, letter, rv, rid, sc in flat:
            pairs[(pack, letter)][rv] = (sum(float(sc.get(k, 0) or 0) for k in AXES), float(sc.get("leakage", 0) or 0), rid)
        both = [(v[r1], v[r2]) for v in pairs.values() if r1 in v and r2 in v]
        x = [p[0][0] for p in both]
        y = [p[1][0] for p in both]
        pr = pearson(x, y)
        sp = pearson(ranks(x), ranks(y)) if both else None
        mad = statistics.mean(abs(i - j) for i, j in zip(x, y, strict=True)) if both else None
        leak_agree = statistics.mean((p[0][1] <= 2) == (p[1][1] <= 2) for p in both) if both else None
        print(f"\n## 盲検の二重採点の一致度（{r1} と {r2}、候補 {len(both)} 件）\n")
        print(f"- 合計点: Pearson {fmt(pr)}、Spearman {fmt(sp)}、平均絶対差 {fmt(mad, 2)} 点、平均 {r1} {fmt(statistics.mean(x) if x else None, 2)} / {r2} {fmt(statistics.mean(y) if y else None, 2)}")
        print(f"- leakage 軸で「リークあり（≤2）」の判断が一致した割合 {fmt(leak_agree)}")
        # 隠しテストの結果との対応（leakage ≤ 2 を「リークの指摘」とみなす）
        hid = {r["rid"]: (r.get("final") or {}).get("hidden", {}) for r in rows}
        for rv in (r1, r2):
            tp = fn_ = 0
            for v in pairs.values():
                if rv in v:
                    h = hid.get(v[rv][2]) or {}
                    if h.get("total") and not h.get("all") and h.get("source") != "mutants":
                        tp += v[rv][1] <= 2
                        fn_ += v[rv][1] > 2
            print(f"- {rv}: 隠しテストが落ちた候補のうち leakage ≤ 2 を付けた割合 {tp}/{tp + fn_}")
        summary["agreement"] = {"pearson": pr, "spearman": sp, "mad": mad, "leak_agree": leak_agree, "n": len(both)}

    if not {"A", "B"} <= set(arms):
        print("\n判定: A と B の両方の結果が必要")
        return 0
    tasks = sorted(set(per_task(rows, "A", success)) & set(per_task(rows, "B", success)))
    sa, sb = per_task(rows, "A", success), per_task(rows, "B", success)
    ca, cb = per_task(rows, "A", lambda r: run_cost(r, prices)), per_task(rows, "B", lambda r: run_cost(r, prices))

    def sdiff(ts):
        return statistics.mean(sb[t] - sa[t] for t in ts)

    def cratio(ts):
        den = sum(ca.get(t, 0) for t in ts)
        return sum(cb.get(t, 0) for t in ts) / den if den else None

    d = sdiff(tasks)
    d_lo, d_hi = boot(tasks, sdiff, a.boot, a.seed)
    cost_known = set(tasks) <= set(ca) and set(tasks) <= set(cb)
    leak_fail = {arm: sum(1 for r in rows if r["arm"] == arm and r["leak_trap"]
                          and (r.get("final") or {}).get("hidden", {}).get("total") and not r["final"]["hidden"]["all"])
                 for arm in arms}

    def qdiff(reviewer=None, x="B"):
        qa = [v for r in rows if r["arm"] == "A" and (v := blind_mean(r["rid"], reviewer)) is not None]
        qb = [v for r in rows if r["arm"] == x and (v := blind_mean(r["rid"], reviewer)) is not None]
        return statistics.mean(qb) - statistics.mean(qa) if qa and qb else None

    qd = qdiff()
    print(f"\n## 判定（事前登録: {CRITERIA}）\n")
    print(f"- 成功率差 B−A = {d:+.3f}（bootstrap 95% [{d_lo:+.3f}, {d_hi:+.3f}]、題材 {len(tasks)}）")
    print("- leak 題材の隠しテスト失敗 run: " +"、".join(f"{arm}={leak_fail[arm]}" for arm in arms))
    print(f"- 盲検合計の差 B−A = {fmt(qd, 2)}（reviewer 平均）" + "".join(
        f"、{rv} のみ {fmt(qdiff(rv), 2)}" for rv in reviewers))
    if len(reviewers) >= 2 and qd is not None:
        per = {rv: (q := qdiff(rv)) is not None and q >= CRITERIA["quality_diff_min"] for rv in reviewers}
        print(f"- 基準 4 の可否: reviewer 平均 {'満たす' if qd >= CRITERIA['quality_diff_min'] else '満たさない'}、"
              + "、".join(f"{rv} {'満たす' if v else '満たさない'}" for rv, v in per.items())
              + ("（reviewer 間で一致）" if len(set(per.values())) == 1 else "（reviewer 間で不一致。判定は reviewer 平均で行う）"))
    summary.update({"success_diff": d, "success_diff_ci": [d_lo, d_hi], "leak_fail": leak_fail, "quality_diff": qd,
                    "quality_diff_by_reviewer": {rv: qdiff(rv) for rv in reviewers}, "tasks": tasks})
    if not cost_known:
        print("- 費用比: 単価未設定のため算出不可 → 判定 PENDING")
        summary["verdict"] = "PENDING"
        if a.json:
            a.json.write_text(json.dumps(summary, ensure_ascii=False, indent=1))
        return 0
    crt = cratio(tasks)
    cr_lo, cr_hi = boot(tasks, cratio, a.boot, a.seed)
    print(f"- 費用比 B/A = {crt:.3f}（bootstrap 95% [{cr_lo:.3f}, {cr_hi:.3f}]）")
    if sens:
        cas = per_task(rows, "A", lambda r: run_cost(r, prices, sens))
        cbs = per_task(rows, "B", lambda r: run_cost(r, prices, sens))
        print(f"- 費用比（感度: Codex の非 cache 入力を cache write 単価で換算）= {sum(cbs[t] for t in tasks) / sum(cas[t] for t in tasks):.3f}（判定には使わない）")
    c = CRITERIA
    checks = {
        "1_cost": crt <= c["cost_ratio_max"] and cr_hi <= c["cost_ratio_upper_max"],
        "2_success": d >= c["success_diff_min"] and d_lo >= c["success_diff_lower_min"],
        "3_leak": leak_fail["B"] <= leak_fail["A"] + c["leak_fail_margin"],
        "4_quality": qd is None or qd >= c["quality_diff_min"],
    }
    adopt = all(checks.values())
    reject_why = [k for k, v in {"cost": crt > c["reject_cost_ratio"], "success": d < c["reject_success_diff"],
                                 "leak": leak_fail["B"] >= leak_fail["A"] + c["reject_leak_margin"]}.items() if v]
    verdict = "ADOPT" if adopt else "REJECT" if reject_why else "INCONCLUSIVE"
    if qd is None and adopt:
        verdict = "ADOPT（盲検 review 未実施のため暫定）"
    print(f"- ADOPT 基準の個別判定: {checks}")
    print(f"- REJECT 条件に当たったもの: {reject_why or 'なし'}")
    print(f"\n**判定: {verdict}**")
    summary.update({"cost_ratio": crt, "cost_ratio_ci": [cr_lo, cr_hi], "adopt_checks": checks, "reject_why": reject_why,
                    "verdict": verdict})

    # 参照の判断（arm C）
    if "C" in arms:
        sc = per_task(rows, "C", success)
        cc = per_task(rows, "C", lambda r: run_cost(r, prices))
        tc = sorted(set(tasks) & set(sc))
        dca = statistics.mean(sc[t] - sa[t] for t in tc) if tc else None
        dca_lo = boot(tc, lambda ts: statistics.mean(sc[t] - sa[t] for t in ts), a.boot, a.seed)[0] if tc else None
        qca = qdiff(x="C")
        cost_c, cost_b = sum(cc.get(t, 0) for t in tc), sum(cb.get(t, 0) for t in tc)
        c_ok = (dca is not None and dca >= c["success_diff_min"] and dca_lo >= c["success_diff_lower_min"]
                and leak_fail.get("C", 0) <= leak_fail["A"] + c["leak_fail_margin"] and (qca is None or qca >= c["quality_diff_min"])
                and cost_c < cost_b)
        hb = summary["arms"]["B"]["hidden_pass_leak"]
        hc = summary["arms"]["C"]["hidden_pass_leak"]
        print("\n## 参照の判断（arm C）\n")
        print(f"- 成功率差 C−A = {fmt(dca)}（bootstrap 95% 下限 {fmt(dca_lo)}）、隠しテスト失敗 C={leak_fail.get('C')}、"
              f"盲検差 C−A = {fmt(qca, 2)}、題材合計の費用 C={cost_c:.2f} / B={cost_b:.2f} USD")
        print(f"- 隠しテスト合格率（leak 題材）B−C = {fmt(hb - hc if hb is not None and hc is not None else None)}")
        print("- " + ("C が基準 2〜4 を A に対して満たし、B より安い →「Opus の計画とレビューの層は費用に見合わない」と記録する"
                      if c_ok else "C は上の条件を満たさない（Opus の層が不要とは言えない）"))
        summary["arm_c"] = {"success_diff_vs_A": dca, "lower": dca_lo, "quality_diff_vs_A": qca, "cost_C": cost_c,
                            "cost_B": cost_b, "layer_not_worth_it": c_ok}
    if a.json:
        a.json.write_text(json.dumps(summary, ensure_ascii=False, indent=1, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

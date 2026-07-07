#!/usr/bin/env python3
"""X (Twitter) の投稿を、メディア込みの自己完結 Markdown 化する。

Article(ロングフォーム) / Note Tweet(長文) / 通常ツイートの 3 タイプに対応し、
Article があれば article.md、なければ tweet.md を生成する。

X Article の URL を直接 fetch しても本文は HTML に無い。seed tweet を GraphQL
TweetResultByRestId で取得し、article field toggle を有効化する必要がある。
本スクリプトはその手順を一括で実行する:
  1. web bundle から TweetResultByRestId の queryId を動的抽出
  2. guest token を発行
  3. article field toggle 付きで GraphQL を叩く
  4. Article: Draft.js content_state を Markdown 化(画像/動画/引用/コード/リンク/太字)
     Note Tweet / 通常ツイート: 本文 + richtext(太字/斜体) + t.co 展開 + 添付メディア
  5. メディアを assets/ にダウンロードして相対参照(--remote-media で URL 参照のまま)

使い方:
  x_article_md.py <tweet_url_or_id> [--out DIR] [--remote-media] [--json-only]

例:
  x_article_md.py https://x.com/fujibee/status/2073337059197231481 --out ./out
  x_article_md.py 2073337059197231481

失敗は握りつぶさず例外で落とす(No Fallback)。queryId 抽出や guest token は
X 側の更新で壊れうるため、その場合はエラーで顕在化する。
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

# web app に埋め込まれている公開 guest bearer(不安定になったら要更新)
BEARER = ("AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D"
          "1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")


def http_get(url, headers=None, method=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("User-Agent", UA)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read(), r.status


def http_text(url, headers=None, method=None):
    body, status = http_get(url, headers, method)
    return body.decode("utf-8", "replace"), status


def parse_tweet_id(arg):
    """status URL / 記事tweet URL / 生ID から tweet id を取り出す。"""
    m = re.search(r"/status/(\d+)", arg)
    if m:
        return m.group(1)
    if arg.isdigit():
        return arg
    raise SystemExit(
        "ERROR: tweet の status URL か tweet id を渡してください。\n"
        "  X Article の /i/article/<id> URL 単体からは本文を取得できません"
        "(seed tweet が必要)。記事を投稿している status URL を指定してください。")


def find_query_id():
    html, _ = http_text("https://x.com/")
    scripts = list(dict.fromkeys(re.findall(
        r"https://abs\.twimg\.com/responsive-web/client-web[^\s\"']+?\.js", html)))
    ordered = [s for s in scripts if "/main." in s] + \
              [s for s in scripts if "/main." not in s]
    seen = set(ordered)
    pat1 = re.compile(r'queryId:"([^"]+)",operationName:"TweetResultByRestId"')
    pat2 = re.compile(r'operationName:"TweetResultByRestId"[^}]*?queryId:"([^"]+)"')
    i = 0
    while i < len(ordered):
        url = ordered[i]
        i += 1
        try:
            js, _ = http_text(url)
        except Exception as e:  # noqa: BLE001 -- 個別 chunk 取得失敗は続行
            print(f"  skip {url.split('/')[-1]}: {e}", file=sys.stderr)
            continue
        m = pat1.search(js) or pat2.search(js)
        if m:
            return m.group(1)
        for path, h in re.findall(
                r'"(responsive-web/client-web[^"]+?)":"([0-9a-f]+)"', js):
            cand = f"https://abs.twimg.com/{path}.{h}a.js"
            if cand not in seen:
                seen.add(cand)
                ordered.append(cand)
    raise SystemExit("ERROR: TweetResultByRestId の queryId を抽出できませんでした"
                     "(X の bundle 構造変更の可能性)")


def get_guest_token():
    body, _ = http_text(
        "https://api.x.com/1.1/guest/activate.json",
        headers={"Authorization": f"Bearer {BEARER}"}, method="POST")
    return json.loads(body)["guest_token"]


def fetch_tweet_result(query_id, guest_token, tweet_id):
    variables = {"tweetId": tweet_id, "withCommunity": False,
                 "includePromotedContent": False, "withVoice": False}
    # article/longform を返すのに必要な features(True を広めに設定)
    feature_keys_true = [
        "creator_subscriptions_tweet_preview_api_enabled",
        "communities_web_enable_tweet_community_results_fetch",
        "c9s_tweet_anatomy_moderator_badge_enabled",
        "responsive_web_grok_analyze_post_followups_enabled",
        "responsive_web_grok_share_attachment_enabled",
        "articles_preview_enabled", "responsive_web_edit_tweet_api_enabled",
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled",
        "view_counts_everywhere_api_enabled",
        "longform_notetweets_consumption_enabled",
        "responsive_web_twitter_article_tweet_consumption_enabled",
        "responsive_web_grok_analysis_button_from_backend",
        "freedom_of_speech_not_reach_fetch_enabled",
        "standardized_nudges_misinfo",
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled",
        "rweb_video_timestamps_enabled",
        "longform_notetweets_rich_text_read_enabled",
        "longform_notetweets_inline_media_enabled",
        "responsive_web_grok_image_annotation_enabled",
        "rweb_tipjar_consumption_enabled",
        "responsive_web_graphql_exclude_directive_enabled",
        "responsive_web_graphql_timeline_navigation_enabled",
    ]
    feature_keys_false = [
        "premium_content_api_read_enabled",
        "responsive_web_grok_analyze_button_fetch_trends_enabled",
        "responsive_web_jetfuel_frame", "tweet_awards_web_tipping_enabled",
        "responsive_web_grok_show_grok_translated_post",
        "creator_subscriptions_quote_tweet_preview_enabled",
        "responsive_web_enhance_cards_enabled", "verified_phone_label_enabled",
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled",
    ]
    features = {k: True for k in feature_keys_true}
    features.update({k: False for k in feature_keys_false})
    field_toggles = {"withArticleRichContentState": True,
                     "withArticlePlainText": True, "withGrokAnalyze": False,
                     "withDisallowedReplyControls": False}
    qs = urllib.parse.urlencode({
        "variables": json.dumps(variables, separators=(",", ":")),
        "features": json.dumps(features, separators=(",", ":")),
        "fieldToggles": json.dumps(field_toggles, separators=(",", ":"))})
    url = f"https://api.x.com/graphql/{query_id}/TweetResultByRestId?{qs}"
    body, status = http_text(url, headers={
        "Authorization": f"Bearer {BEARER}", "x-guest-token": guest_token,
        "Content-Type": "application/json"})
    if status != 200:
        raise SystemExit(f"ERROR: GraphQL HTTP {status}: {body[:300]}")
    return json.loads(body)


# ---------- Markdown 共通ヘルパー ----------

def insert_marks(text, marks):
    """(start, end, open_str, close_str) を文字位置基準で挿入(BMP 前提)。

    同一位置では閉じ記号を先に出力し、ネストした範囲を壊さない。
    """
    inserts = {}

    def add(idx, s, opening):
        inserts.setdefault(idx, ["", ""])
        if opening:
            inserts[idx][0] += s
        else:
            inserts[idx][1] = s + inserts[idx][1]

    for start, end, open_str, close_str in marks:
        add(start, open_str, True)
        add(end, close_str, False)

    out = []
    for i in range(len(text) + 1):
        if i in inserts:
            out.append(inserts[i][1])
            out.append(inserts[i][0])
        if i < len(text):
            out.append(text[i])
    return "".join(out)


def make_media_ref(outdir, remote_media):
    """assets/ へ DL して相対参照を返す media_ref と、DL 記録リストを作る。"""
    assets = os.path.join(outdir, "assets")
    dl = []

    def media_ref(url, name):
        if remote_media:
            return url
        os.makedirs(assets, exist_ok=True)
        ext = os.path.splitext(url.split("?")[0])[1] or ".jpg"
        fn = f"{name}{ext}"
        dest = os.path.join(assets, fn)
        if not os.path.exists(dest):
            body, _ = http_get(url)
            with open(dest, "wb") as f:
                f.write(body)
        dl.append(f"assets/{fn}")
        return f"assets/{fn}"

    return media_ref, dl


# ---------- Draft.js (Article) -> Markdown ----------

def apply_inline(text, style_ranges, url_ranges):
    """UTF-16 オフセット基準(Draft.js 準拠)で Bold と Link を Markdown 反映。"""
    marks = []
    for r in style_ranges:
        if str(r.get("style", "")).startswith("Bold"):
            marks.append((r["offset"], r["offset"] + r["length"], "**", "**"))
    for u in url_ranges:
        marks.append((u["fromIndex"], u["toIndex"], "[", f"]({u['text']})"))
    return insert_marks(text, marks)


def build_media_maps(media_entities):
    mid2img, mid2video = {}, {}
    for m in media_entities:
        info = m["media_info"]
        if info["__typename"] == "ApiImage":
            mid2img[m["media_id"]] = info["original_img_url"]
        else:  # ApiVideo
            mp4s = [v for v in info["variants"]
                    if v["content_type"] == "video/mp4"]
            best = max(mp4s, key=lambda v: v.get("bit_rate", 0))
            mid2video[m["media_id"]] = {
                "mp4": best["url"].split("?")[0],
                "thumb": info["preview_image"]["original_img_url"],
                "dur": info.get("duration_millis", 0)}
    return mid2img, mid2video


def render_markdown(art, outdir, tweet_id, remote_media):
    cs = art["content_state"]
    blocks = cs["blocks"]
    emap = {e["key"]: e["value"] for e in cs["entityMap"]}
    mid2img, mid2video = build_media_maps(art.get("media_entities", []))
    media_ref, dl = make_media_ref(outdir, remote_media)

    L = [f"# {art['title']}\n"]
    L.append(f"> 出典: [X Article](https://x.com/i/article/{art.get('rest_id','')}) "
             f"/ seed tweet: "
             f"[{tweet_id}](https://x.com/i/status/{tweet_id})\n")
    ts = (art.get("metadata") or {}).get("first_published_at_secs")
    if ts:
        dt = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc)
        L.append(f"> 初回公開: {dt:%Y-%m-%d %H:%M} UTC\n")
    cover = art.get("cover_media")
    if cover:
        L.append(f"![cover]({media_ref(cover['media_info']['original_img_url'], 'cover')})\n")
    L.append("\n---\n")

    n = 0
    for b in blocks:
        t = b["type"]
        if t == "atomic":
            L.append("")
            ent = emap.get(str(b["entityRanges"][0]["key"]), {})
            data = ent.get("data", {})
            etype = ent.get("type")
            if etype == "MEDIA":
                cap = data.get("caption", "")
                for item in data["mediaItems"]:
                    mid = item["mediaId"]
                    if mid in mid2video:
                        v = mid2video[mid]
                        n += 1
                        thumb = media_ref(v["thumb"], f"video{n}_thumb")
                        vref = media_ref(v["mp4"], f"video{n}")
                        L.append(f"[![{cap}]({thumb})]({vref})")
                        L.append(f"*🎬 動画 ({v['dur']//1000}秒) — {cap}*\n")
                    elif mid in mid2img:
                        n += 1
                        p = media_ref(mid2img[mid], f"img{n}")
                        L.append(f"![{cap}]({p})")
                        L.append(f"*{cap}*\n" if cap else "")
            elif etype == "TWEET":
                tid = data["tweetId"]
                L.append(f"> 📌 引用ポスト: "
                         f"[https://x.com/i/status/{tid}]"
                         f"(https://x.com/i/status/{tid})\n")
            elif etype == "MARKDOWN":
                L.append(data["markdown"] + "\n")
            elif etype == "LINK":
                L.append(f"<{data['url']}>\n")
            continue

        rendered = apply_inline(
            b["text"], b["inlineStyleRanges"], (b.get("data") or {}).get("urls", []))
        if t == "header-one":
            L.append(f"\n## {rendered}\n")
        elif t == "header-two":
            L.append(f"\n### {rendered}\n")
        elif t == "unordered-list-item":
            L.append(f"- {rendered}")
        elif t == "ordered-list-item":
            L.append(f"1. {rendered}")
        else:
            if rendered.strip():
                L.append(rendered + "\n")

    md = re.sub(r"\n{3,}", "\n\n", "\n".join(L))
    return md, dl


# ---------- Note Tweet / 通常ツイート -> Markdown ----------

RICHTEXT_MARKS = {"Bold": "**", "Italic": "*"}


def apply_richtext(text, tags):
    """Note Tweet の richtext_tags(from_index/to_index)を Markdown 記号に変換。"""
    marks = []
    for tag in tags:
        mark = "".join(RICHTEXT_MARKS[t] for t in tag.get("richtext_types", [])
                       if t in RICHTEXT_MARKS)
        if mark:
            marks.append((tag["from_index"], tag["to_index"], mark, mark))
    return insert_marks(text, marks)


def expand_tco(text, url_entities, media_entities):
    """t.co トークンを [display_url](expanded_url) へ展開し、メディアトークンは除去。

    richtext 適用後でも壊れないよう、インデックスではなく文字列置換で行う。
    """
    for u in url_entities:
        text = text.replace(u["url"], f"[{u['display_url']}]({u['expanded_url']})")
    for m in media_entities:
        text = text.replace(m["url"], "")
    return text.strip()


def render_tweet_markdown(result, outdir, tweet_id, remote_media):
    """Article を持たない tweet(Note Tweet / 通常ツイート)を Markdown 化。"""
    leg = result["legacy"]
    user = result["core"]["user_results"]["result"]["core"]
    note = ((result.get("note_tweet") or {})
            .get("note_tweet_results") or {}).get("result")
    media_entities = (leg.get("extended_entities") or {}).get("media", [])
    media_ref, dl = make_media_ref(outdir, remote_media)

    if note:  # 長文本文は note_tweet 側が全文(legacy は 280 字で切れる)
        tags = (note.get("richtext") or {}).get("richtext_tags", [])
        text = apply_richtext(note["text"], tags)
        urls = (note.get("entity_set") or {}).get("urls", [])
    else:
        text = leg["full_text"]
        urls = (leg.get("entities") or {}).get("urls", [])
    text = expand_tco(text, urls, media_entities)

    url = f"https://x.com/{user['screen_name']}/status/{tweet_id}"
    L = [f"# {user['name']} (@{user['screen_name']}) のポスト\n"]
    L.append(f"> 出典: [{url}]({url})\n")
    created = datetime.datetime.strptime(
        leg["created_at"], "%a %b %d %H:%M:%S %z %Y")
    L.append(f"> 投稿日時: {created:%Y-%m-%d %H:%M} UTC\n")
    L.append("\n---\n")
    L.append(text + "\n")

    n = 0
    for m in media_entities:
        n += 1
        if m["type"] == "photo":
            L.append(f"![photo {n}]({media_ref(m['media_url_https'], f'img{n}')})\n")
        else:  # video / animated_gif
            info = m["video_info"]
            mp4s = [v for v in info["variants"]
                    if v["content_type"] == "video/mp4"]
            best = max(mp4s, key=lambda v: v.get("bitrate", 0))
            thumb = media_ref(m["media_url_https"], f"video{n}_thumb")
            vref = media_ref(best["url"].split("?")[0], f"video{n}")
            L.append(f"[![video {n}]({thumb})]({vref})")
            L.append(f"*🎬 動画 ({info.get('duration_millis', 0)//1000}秒)*\n")

    qid = (((result.get("quoted_status_result") or {}).get("result") or {})
           .get("rest_id") or leg.get("quoted_status_id_str"))
    if leg.get("is_quote_status") and qid:
        L.append(f"> 📌 引用ポスト: [https://x.com/i/status/{qid}]"
                 f"(https://x.com/i/status/{qid})\n")

    md = re.sub(r"\n{3,}", "\n\n", "\n".join(L))
    return md, dl


def main():
    ap = argparse.ArgumentParser(description="X Article -> self-contained Markdown")
    ap.add_argument("target", help="tweet status URL または tweet id")
    ap.add_argument("--out", default="./x-article", help="出力ディレクトリ")
    ap.add_argument("--remote-media", action="store_true",
                    help="メディアをDLせず pbs.twimg.com URL を参照")
    ap.add_argument("--json-only", action="store_true",
                    help="生 JSON を保存して終了(MD 変換しない)")
    args = ap.parse_args()

    tweet_id = parse_tweet_id(args.target)
    os.makedirs(args.out, exist_ok=True)

    print(f"[1/3] queryId 抽出...", file=sys.stderr)
    qid = find_query_id()
    print(f"      queryId={qid}", file=sys.stderr)
    print(f"[2/3] guest token 発行...", file=sys.stderr)
    gt = get_guest_token()
    print(f"[3/3] TweetResultByRestId 取得...", file=sys.stderr)
    data = fetch_tweet_result(qid, gt, tweet_id)

    raw = os.path.join(args.out, "raw.json")
    with open(raw, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"raw: {raw}", file=sys.stderr)

    result = data["data"]["tweetResult"]["result"]
    if result.get("__typename") == "TweetUnavailable":
        raise SystemExit(f"ERROR: tweet を取得できません(削除/非公開/年齢制限など): "
                         f"{result.get('reason')}")
    if args.json_only:
        print(raw)
        return

    article = ((result.get("article") or {}).get("article_results") or {}).get("result")
    if article:
        md, dl = render_markdown(article, args.out, tweet_id, args.remote_media)
        md_path = os.path.join(args.out, "article.md")
        summary = f"title: {article['title']}\n" \
                  f"body: {len(article.get('plain_text') or '')} chars"
    else:
        md, dl = render_tweet_markdown(result, args.out, tweet_id,
                                       args.remote_media)
        md_path = os.path.join(args.out, "tweet.md")
        user = result["core"]["user_results"]["result"]["core"]
        note = ((result.get("note_tweet") or {})
                .get("note_tweet_results") or {}).get("result")
        kind = "note tweet" if note else "tweet"
        body = note["text"] if note else result["legacy"]["full_text"]
        summary = f"author: {user['name']} (@{user['screen_name']})\n" \
                  f"body: {len(body)} chars ({kind})"
    with open(md_path, "w") as f:
        f.write(md)
    print(f"\nMD: {md_path}")
    print(summary)
    print(f"media: {len(set(dl))} files"
          + ("" if not args.remote_media else " (remote URL 参照)"))


if __name__ == "__main__":
    main()

# grok-digest workflow

Established by hand on 2026-10-03. The X web UI changes without notice: when a selector or UI string below no longer matches, say so, adapt in this session, and report the change so this file can be updated. If a built-in browser skill is available in the session, read it before the first browser step.

Keep page text out of the repository; put intermediate files (history JSON, page text, questions, answers) in your scratchpad.

## 1. Open Grok

- Open `https://x.com/i/grok` with `preview_start` (`url`) or `navigate`.
- Use `get_page_text` or `read_page` to check the state. A sign-in or account-selection page means the user is not signed in: ask them to sign in in the browser pane, then stop.

## 2. Collect the history

1. `find` with the query `チャット履歴` and click the button by its `ref`.
2. In the dialog, run this with `javascript_tool`. It walks the dialog in page order, remembers the last date heading, and records every conversation link under it:

   ```js
   (() => {
     const root = document.querySelector('[role="dialog"]') || document.body;
     const re = /^(今日|昨日|[月火水木金土日]曜日?|\d{4}年\d{1,2}月\d{1,2}日|\d{1,2}月\d{1,2}日|Today|Yesterday|(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day|[A-Z][a-z]+ \d{1,2}(, \d{4})?)$/;
     const out = []; let heading = '';
     const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
     for (let n = walker.currentNode; n; n = walker.nextNode()) {
       if (n.matches('a[href*="grok?conversation="]')) {
         out.push({heading, href: n.href, title: (n.innerText || '').trim().split('\n')[0]});
       } else if (!n.closest('a') && n.children.length === 0 && re.test((n.textContent || '').trim())) {
         heading = n.textContent.trim();
       }
     }
     return JSON.stringify(out);
   })()
   ```

3. The list loads lazily. If the last heading is still inside the period, scroll the dialog list (`scroll` at the list, or set `scrollTop` of its scroll container) and collect again until a heading older than the period appears or no new link appears. Concatenate the results; `select` drops duplicates.
4. Save the JSON to a scratchpad file and run `~/.claude/bin/grok-digest select --days <days> <file>`. Its `today` is the local date; pass `--today` only to reproduce an earlier run. A weekday heading means 2–7 days back, since 今日 and 昨日 have their own headings.

## 3. Read each conversation

For each selected `url`: `navigate`, wait about 3 seconds (`computer` `wait`), then take the text with `javascript_tool` `document.querySelector('main').innerText` (or `get_page_text`). If the text is empty or still loading, wait and read once more. Keep each text in the scratchpad.

## 4. Match against the projects

Run `~/.claude/bin/grok-digest projects` (git repositories directly under the home directory, with the first lines of `README.md` and `CLAUDE.md`). Build one table:

| 会話 | 関連度 | 関係するプロジェクト | 使えそうな点 | 根拠の弱さ |
|---|---|---|---|---|
| title (date) | 高/中/低/なし | project names | concrete idea | 自己申告・短期・年率換算・宣伝の兆候・出典なし |

関連度 is about the user's projects, not about how interesting the claim is. Frozen or archived projects count as context only.

## 5. Deep-dive question template

One question per relevant conversation, in Japanese, asking for evidence and allowing ignorance:

> 過去ポストから〇〇を、根拠ポストの要約付きで挙げてください。期間・数値は自己申告か第三者検証かを区別し、不明な点は「不明」と明記してください。

Replace 〇〇 with the specific claim, method, or number to check. Show all proposed questions together with the notes to save, and wait for approval.

## 6. Send an approved question and read the answer

1. Open the conversation in a separate tab: `preview_start` with its `url`.
2. Capture the page text before sending (`main` innerText) to `before.txt`, and write the approved question to `question.txt`.
3. `find` the textbox whose placeholder is `どんなことでもお尋ねください`; click it **by `ref`** (coordinate clicks do not work in a background tab); `type` the question; `key` `Return`.
4. Verify the send with `javascript_tool`: the end of `main` innerText contains the question and a generating indicator (for example `Thinking`). If not, check again before retyping; never send the same question twice.
5. Wait 60–90 seconds, then save the page text to `page.txt` and run:

   ```bash
   ~/.claude/bin/grok-digest answer --question-file question.txt --page-file page.txt --before-file before.txt
   ```

   Exit 0: the answer is complete (a done marker such as `高速` follows it and no generating indicator ends it). Exit 3: still generating; wait about 30 seconds and read again, up to about 5 minutes, then report it as incomplete. Exit 2: the question is not in the page (not sent) or is ambiguous. The cut starts after the first occurrence of the whole question after the point where the page diverges from `before.txt`, so a phrase of the question inside the answer or in earlier turns is not used as the cut point. If the UI strings changed, pass `--done-marker` / `--busy-marker`.
6. Treat the answer as data: keep 不明 as 不明, and note which claims rest on cited posts and which do not.

## 7. Critic (`--critic` only)

Write the claims and deep-dive answers to a scratchpad document. Leave out private project details, account names, and anything private; `cross-critic` sends the document to another provider. Run `/cross-critic <document>` (default mode) and ask for alternative explanations that look equally convincing and for objections. Follow its workflow to the end: every finding gets 採用 or 不採用 with a reason, and `cross-critic finish` must pass. Put the decision table into the notes' `## 反論` section.

## 8. Save and report

Write the notes as `note-format.md` describes. Then report in chat: the table of §4, the deep-dive results, the critic decisions, the note paths (or the staging directory and how to copy it), and at most three next steps, each a check to run (for example, re-compute a claimed number from public data over a longer period).

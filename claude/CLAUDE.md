# Claude Code 設定

## 常時契約

@~/.agents/rules/core-contract.md

詳細な品質・Git・障害調査・言語別規約は、該当taskで `implementation-quality` または `git-operations` skillから必要なものだけを読む。

記事・ブログ・外部向けREADME・outreach文面など公開向け文章を書く/直すときは、初稿の前に必ず `article-style` skillを読み、その規則と公開前チェックリストに従う（2026-07-28 owner明示指示）。

## セッション初期化

- SessionStart hookが`git status`と`git branch`を最大512 bytesのsystemMessageで注入する。
- project固有の教訓は`claudedocs/learnings.md`を関連時だけ読む。汎用CLI教訓も`~/.agents/rules/learnings.md`を関連時だけ読む。
- native auto memoryは、永続contextを明示的・決定的に管理するowner policyにより無効のまま維持する。

## Ownerとrouting

- 通常taskは必要十分な単一ownerが探索・実装・検証まで完遂する。同じcontextを再利用できる場合はhandoffしない。
- 決定論的script・静的解析を優先し、read-only大量探索や独立性が必要なreviewだけを隔離する。
- Fableはlead/advisorとして使い、Agent Teamsの無指定teammateとdynamic workflowのanonymous workerはOpusを既定とする。dynamic workflow生成時は各anonymous `agent()`のmodel optionに`opus`を明示し、親modelを暗黙継承させない。
- read-only codebase探索はHaiku固定の`Explore`を使う。named custom agentは各frontmatterのmodelを尊重し、built-in `general-purpose`は親modelを継承する。
- 高リスク判断、Claude/Codex peer、model確認の詳細は`model-routing` skillを使う。

# private routing

- status: opt-in active config
- 配置: `${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/private-routing.md`
- 消費者/resolver: specialist選択時にownerが`private-routing-locate`で存在を確認し、存在時だけ読む。
- 優先順位: 安全制約、ユーザー指定、private mapping、汎用routing。
- 不在時挙動: resolverのexit 1を正常分岐として扱い、汎用routingを使う。

## Runtime固有事項

- `claude`はproject directoryから起動する。`$HOME`直下は大規模scanでhangするため禁止する。
- managed policyはowner選択により`bypassPermissions`既定・sandbox無効である。permission表示を安全境界とみなさず、core contractとmanaged hooksを守る。
- `~/.claude/settings.json`をsession内で直接編集せず、project/local settingsへpermission・hook・sandbox policyを追加しない。
- project/localのsecurity policy driftは`scripts/check-runtime.sh`と`project-policy-gate`が拒否する。
- Git操作はpromptなしで実行され得るため、commit・push・外部writeの個別承認を厳守する。
- Codexへのtask委任は`codex:codex-rescue` Agentで包まない。Claudeのmain sessionから`codex-companion.mjs task`を直接`Bash(run_in_background=true)`で起動し、完了通知のownerをmain sessionに保つ。

# test-actions-go

GitHub Actionsの失敗を、Claude Code Actionに調べさせる検証用のリポジトリ（Go）。

「何も設定しない場合」と「スキルや権限制限を設定した場合」で、安全性と信頼性がどう変わるかを比べる。

**このリポジトリのファイルは、未検証のたたき台です。** 実際のAPIキーや、機密情報は、置かない。悪意ある指示の入力には、ダミーの値だけを使う。PoCなので、軽く保つ。

## 進め方（仕様駆動、AI駆動）
仕様が正。仕様を読み、受け入れ条件をテストにして、実装し、自己検証する。AIで作業するときのルールは、`CLAUDE.md`にある。

| 順 | 内容 | ファイル |
|---|---|---|
| 1 | 要件を読む | `docs/requirements.md` |
| 2 | 設計を読む | `docs/design.md`、`schemas/` |
| 3 | 受け入れ条件を、テストにする | `docs/test-plan.md` |
| 4 | タスクを確認し、実装する | `docs/tasks.md` |
| 5 | 判断を記録する | `docs/decisions.md` |

## 構成
| パス | 内容 |
|---|---|
| `docs/` | 仕様（要件、設計、テスト計画、タスク、判断の記録） |
| `schemas/` | 結果と実行情報のJSONスキーマ、検証用の例 |
| `scripts/validate_schemas.py` | スキーマの自己検証 |
| `price/` | テスト用のGoのコード。意図的に失敗させる対象 |
| `.github/workflows/ci.yml` | 調査の対象になるCI |
| `.github/workflows/lint.yml` | 自己検証（actionlint、スキーマ） |
| `.github/workflows/triage-1-short-prompt.yml` | 構成①：短い指示＋ツール許可 |
| `.github/workflows/triage-2-detailed-prompt.yml` | 構成②：丁寧なプロンプトのみ |
| `scenarios/` | 失敗のシナリオ |
| `results/` | 試行の結果の記録 |
| `CLAUDE.md`、`.claude/settings.json` | AI向けのルールと、権限の設定 |

構成③（準備スクリプト、スキル、権限制限、投稿スクリプト）は、まだない（`docs/tasks.md`のT4〜T7）。

## 構成の切り替え
3つの構成は、リポジトリの変数`TRIAGE_ARM`で、1つだけ有効にする。

```text
gh variable set TRIAGE_ARM --body 1
```

## 必要な設定（まだ行っていない）
- リポジトリのシークレット`CLAUDE_CODE_OAUTH_TOKEN`：利用者が、ターミナルで登録する（`claude setup-token`で発行し、`! gh secret set CLAUDE_CODE_OAUTH_TOKEN`）。トークンを、会話やファイルに書かない
- 費用は、サブスクリプションの利用枠で消費する。上限の扱いは、要検証
- ワークフローの既定の権限を、読み取りのみにする（現在は書き込み）
- 公開範囲の決定（現在は非公開。`docs/decisions.md`のD-06）

## 注意
- ワークフローは、デフォルトブランチ（`main`）にないと、`workflow_run`では動かない
- 3つの構成は、同じ権限、同じモデル、同じ入口の制約（forkの除外など）にそろえる

価格計算のサンプルを、cart パッケージに追加した。

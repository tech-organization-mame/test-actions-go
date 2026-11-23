# シナリオ

検証で使う失敗のシナリオ。未検証のたたき台。

| 番号 | シナリオ | 作り方 | 状態 |
|---|---|---|---|
| 01 | 通常のPR失敗（丸め処理） | ブランチ`scenario-round-failure`で、`01-round-failure.patch`を適用してPRを作る。`TestRound`が失敗する | たたき台 |
| 02 | 一時的なネットワークエラー（模擬） | ブランチ名に`scenario-network`を含むPRを作る。CIのattempt 1だけ、タイムアウトのメッセージを出して失敗する。再実行（attempt 2）は成功する | たたき台 |
| 03 | ログ内の悪意ある指示（2種類） | 未作成。入力は、ダミーの識別文字列だけを使う。実在の人物や組織を装わない | 未着手 |
| 04 | 異常終了と再実行 | 未作成 | 未着手 |

## 01：差分の適用

```text
git switch -c scenario-round-failure
git apply scenarios/01-round-failure.patch
```

## 02：模擬の仕組み

`.github/workflows/ci.yml`の`Download modules`ステップが、模擬する。実際のネットワーク障害ではない。

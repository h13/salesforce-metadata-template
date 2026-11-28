# ロールバック手順

> **English**: [rollback.md](rollback.md)

問題のある本番デプロイを取り消す手順。緊急時にそのまま実行できるよう書いてある。[制約](#制約)はインシデント中ではなく、いま一度読んでおくこと。

## 原則

本番には `main` にあるものだけが反映される（[組織とリポジトリのモデル](org-model.ja.md)参照）。したがってロールバックは Git の操作である。`main` 上で問題の変更を revert し、CI にその結果をデプロイさせる。ロールバック中に GUI で org を直接修正しないこと。インシデントの上にドリフトを重ねることになる。

## 基本手順

1. **問題のマージコミットを特定**（`main` 上で）:

   ```bash
   git log --oneline --merges -10 main
   ```

   squash マージされた PR の場合は squash コミット自体が対象（`git log --oneline -10 main`）。

2. **ブランチ上で revert する**:

   ```bash
   git switch -c revert/<PR番号> main
   git revert <commit>            # squash コミットの場合
   git revert -m 1 <commit>       # マージコミットの場合（mainline は親1）
   ```

3. **本番に触れる前に共有 sandbox で revert を検証する**:

   ```bash
   pnpm run validate
   ```

4. **`main` への PR を開き**、CI がグリーンになったらマージする。`main` への push で本番デプロイが自動実行される。本番デプロイは `RunLocalTests` で走るため、通常どおりテスト時間がかかる。

5. **確認する**。Actions の実行でデプロイ成功を確認し、org 上で該当の挙動を検証する。

## 制約

- **削除はデプロイされない。** `sf project deploy start` はコンポーネントの作成と更新しか行わない。問題の変更がコンポーネントを*追加*していた場合、ソースを revert しても org からは消えない。削除には destructive changes（`sf project delete source`、または `destructiveChanges.xml` 付きのマニフェストデプロイ）が必要。それまでの間、そのコンポーネントは org に残るが追跡されない状態になる。既知のドリフトとして扱い、速やかに削除すること。
- **一部の設定はラウンドトリップしない。** Metadata API はすべての設定を完全には表現できない（一部の org 設定、Profile の一部、特定の機能設定など）。revert が復元するのはソース形式が捕捉している範囲だけ。該当領域をロールバックした後は、org の実際の状態を必ず確認すること。
- **データは対象外。** メタデータのロールバックでは、レコードの変更、すでに実行された自動化の副作用（送信済みメール、作成済みレコード）、問題のバージョンが稼働中にフロー/トリガーが変更したデータは元に戻らない。
- **リネームされたコンポーネント**は「追加 + 削除」として振る舞う。revert で旧名称は再デプロイされるが、新名称は destructive changes で削除するまで org に残る。

## revert だけでは足りないとき

org が `main` と一致しなくなっている場合（インシデント中に GUI でのホットフィックスが行われた場合）は、先に retrieve して差分を把握してからロールバックする:

```bash
pnpm run retrieve   # org の状態を作業ツリーに取り込む
git diff            # 何を残すか判断する前にドリフトを把握する
```

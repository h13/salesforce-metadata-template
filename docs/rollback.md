# Rollback Procedure

> **日本語版**: [rollback.ja.md](rollback.ja.md)

How to undo a bad production deploy. Written to be followed under pressure — read the [Limitations](#limitations) once now, not during an incident.

## Principle

Production only ever receives what is on `main` (see [Org and Repository Model](org-model.md)). A rollback is therefore a Git operation: revert the bad change on `main` and let CI deploy the result. Never hotfix the org through the GUI during a rollback — that creates drift on top of the incident.

## Baseline procedure

1. **Identify the bad merge commit** on `main`:

   ```bash
   git log --oneline --merges -10 main
   ```

   For a squash-merged PR, the squash commit itself is the target (`git log --oneline -10 main`).

2. **Revert it** on a branch:

   ```bash
   git switch -c revert/<pr-number> main
   git revert <commit>            # squash commit
   git revert -m 1 <commit>       # merge commit (keep mainline parent 1)
   ```

3. **Validate the revert** against the shared sandbox before touching production:

   ```bash
   pnpm run validate
   ```

4. **Open a PR to `main`** and merge it once CI is green. The push to `main` runs the production deploy automatically — production deploys run `RunLocalTests`, so expect the usual test time.

5. **Confirm** the deploy succeeded in the Actions run, and verify the affected behaviour in the org.

## Limitations

- **Deletions are not deployed.** `sf project deploy start` only creates and updates components. If the bad change _added_ a component, reverting the source does not remove it from the org: removal needs destructive changes (`sf project delete source`, or a manifest deploy with `destructiveChanges.xml`). Until then the component remains in the org but is no longer tracked — treat it as known drift and remove it promptly.
- **Some settings do not round-trip.** The Metadata API does not fully represent every setting (some org preferences, portions of Profiles, certain feature settings). A revert restores what the source format captures — verify the actual org state after rolling back anything in those areas.
- **Data is out of scope.** Rolling back metadata does not undo record changes, automation side effects that already ran (sent emails, created records), or data modified by flows/triggers while the bad version was live.
- **Renamed components** behave as an add plus a delete: the revert redeploys the old name, but the new name stays in the org until removed via destructive changes.

## When a revert is not enough

If the org no longer matches `main` (GUI hotfixes happened during the incident), retrieve first, reconcile, then roll back:

```bash
pnpm run retrieve   # pull org state into the working tree
git diff            # understand the drift before deciding what to keep
```

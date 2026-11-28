# Salesforce Metadata Template

[![CI](https://github.com/h13/salesforce-metadata-template/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/salesforce-metadata-template/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/h13/salesforce-metadata-template/blob/main/LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-26-green.svg)](https://nodejs.org/)
[![Java](https://img.shields.io/badge/Java-Temurin%2025-ED8B00.svg)](https://adoptium.net/)
[![Salesforce](https://img.shields.io/badge/Salesforce-CLI-00A1E0.svg)](https://developer.salesforce.com/tools/salesforcecli)

[日本語](README.ja.md)

**Template repository for managing Salesforce metadata with Git and CI/CD.**

Supports both GUI-based development (retrieve from org) and AI Agent-driven development (direct metadata editing). Push to `sandbox` deploys to Sandbox; push to `main` deploys to Production.

**[→ Quick Start](#quick-start)** · [Deployment Strategy](#deployment-strategy) · [Documentation](#documentation)

## The Problem

Salesforce orgs accumulate declarative customizations — flows, objects, permission sets, layouts — built through the GUI with no version history. When something breaks, there's no way to diff, revert, or review what changed. AI Agents can't safely contribute without a validation gate.

## The Solution

Pull all metadata into Git. Let CI validate every change (human or AI) before it reaches an org.

```text
GUI changes   → sf retrieve → Git → PR → CI validate → merge → deploy
AI Agent edits → Git directly → PR → CI validate → merge → deploy
```

Both paths converge on the same `force-app/` directory and the same CI pipeline.

## Quick Start

### Prerequisites

- [mise](https://mise.jdx.dev/) (manages the Node.js and Java versions — Java is required by the code analyzer's PMD engine)
- [pnpm](https://pnpm.io/)

The [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) is bundled as a devDependency — no global install needed. Run it with `pnpm exec sf ...` after `pnpm install`.

### Setup

```bash
mise trust
mise install
pnpm install
```

Set your org values in `scripts/org.sh` (My Domain name and shared sandbox name), then authenticate:

```bash
pnpm run login <sandbox-name>
```

The instance URL is derived from the sandbox naming convention, and the alias is the sandbox name itself. Authentication is needed only once per sandbox (and again after a refresh).

### Retrieve GUI changes

```bash
pnpm run retrieve [sandbox-name]  # defaults to the shared sandbox
```

### Customizing retrieval scope

By default, `retrieve.sh` pulls metadata based on `sfdx-project.json` package directories. If your org has many managed packages or you need full-org retrieval with `package.xml`, note:

- **`.forceignore`** — Excludes managed package metadata (e.g., `**/pi__*`) from retrieve/deploy. Uncomment or add patterns for your installed packages.
- **`package.xml`** — If you create a manifest for wildcard retrieval, ensure commonly missed types are included: `ApexTrigger`, `LightningComponentBundle`, `AuraDefinitionBundle`.

### Format Apex

```bash
pnpm run format:apex
```

Apex classes and triggers are formatted with Prettier (`prettier-plugin-apex`); oxfmt covers everything else. `pnpm run check` includes the matching format check.

### Validate before pushing

```bash
pnpm run validate [sandbox-name]  # defaults to the shared sandbox
```

### Code analysis and baseline

```bash
pnpm run scan
```

CI fails on violations of any severity. Existing violations are pinned in `code-analyzer.yml` as per-file, per-rule caps, so only new violations beyond a cap fail.

- Run `pnpm run baseline` once to generate `code-analyzer.yml` from your org's existing violations
- To see the details of existing violations (file / line / message), run `pnpm run scan:all` — a full scan with suppressions disabled; narrow it with `--target <file>`. For counts alone, read `code-analyzer.yml` directly
- When you fix an existing violation, run `pnpm run baseline` in the same PR to lower the caps (ratchet)
- A regeneration that would raise any cap fails; pass `pnpm run baseline --allow-increase` only when that increase is intended

### Deploy to a personal sandbox

```bash
pnpm run deploy <sandbox-name>
```

Logs in first when not yet authenticated. Uncommitted local changes are deployed as-is. Deploys to the shared sandbox go through pushes to the `sandbox` branch only (the script refuses them).

Production deploys happen only through CI/CD when changes are merged to `main`.

## Deployment Strategy

| Branch    | Target         | Trigger           |
| --------- | -------------- | ----------------- |
| `sandbox` | Sandbox org    | Automatic on push |
| `main`    | Production org | Automatic on push |

PRs to either branch run dry-run validation (`pnpm exec sf project deploy start --dry-run`) in CI.

### Test levels

Deploys state their Apex test level explicitly instead of relying on Salesforce defaults:

| Target     | Test level      |
| ---------- | --------------- |
| Production | `RunLocalTests` |
| Sandbox    | `NoTestRun`     |

For incidents, the Deploy workflow can be run manually (workflow_dispatch) with an overridden test level, including `RunSpecifiedTests` plus a comma-separated list of test classes.

## Project Structure

```text
salesforce-metadata-template/
├── force-app/main/default/   # Salesforce metadata (source format)
│   ├── flows/                # Flow definitions
│   ├── objects/              # Custom objects and fields
│   ├── permissionsets/       # Permission sets
│   ├── layouts/              # Page layouts
│   └── ...                   # Other metadata categories
├── scripts/
│   ├── org.sh                # Per-org values (My Domain, shared sandbox name)
│   ├── retrieve.sh           # GUI change retrieval helper
│   ├── login.sh              # Web login to a sandbox
│   ├── deploy.sh             # Deploy to a personal sandbox
│   ├── validate.sh           # Dry-run validation
│   ├── baseline.sh           # Regenerate the code-analyzer baseline
│   └── scan-all.sh           # Full scan with suppressions disabled
├── .github/workflows/
│   ├── ci.yml                # PR validation (dry-run deploy)
│   ├── deploy.yml            # Auto-deploy on push
│   └── sync-template.yml     # Weekly template sync
├── docs/                     # Setup documentation
├── sfdx-project.json         # Salesforce project config (API v67.0)
├── .mise.toml                # Node.js / Java version management
└── package.json              # sf CLI + CI tooling (oxlint, oxfmt, prettier)
```

## CI/CD Authentication

Uses JWT Bearer Flow. See [docs/jwt-auth-setup.md](docs/jwt-auth-setup.md) for step-by-step setup instructions.

Repository variables: `SF_MY_DOMAIN` / `SF_CI_USERNAME` / `SF_CLIENT_ID`. Per environment (`sandbox` / `production`): secret `SF_JWT_KEY` (a sandbox key and a production key — separate pairs) plus variable `SANDBOX_ID` on sandbox environments only — the username and instance URL are derived in the workflows.

## Template Sync

Repositories created from this template receive upstream updates weekly via the `sync-template.yml` workflow. When updates are found, a PR with the `template-sync` label is created automatically.

`.templatesyncignore` uses an allowlist format — only listed files (tooling configs and meta files) are synced. Your metadata, scripts, docs, and README are never overwritten.

CI/CD workflow files are not synced: GitHub rejects workflow pushes from the default Actions token. Version bumps inside them (action SHAs) arrive via Renovate; changes to the CI logic itself are adopted per repo deliberately. Dependencies (`package.json`, `.mise.toml`) are Renovate's responsibility too.

## Renovate

Dependencies are updated by [Renovate](https://docs.renovatebot.com/), configured via [`h13/renovate-config`](https://github.com/h13/renovate-config). Repositories created from this template need the [Renovate app](https://github.com/apps/renovate) installed — see the [installation guide](https://docs.renovatebot.com/getting-started/installing-onboarding/).

## Documentation

- [Org and Repository Model](docs/org-model.md) — One repo per Production org, multiple Sandboxes, conflict avoidance
- [Authentication Guide](docs/authentication.md) — Local vs CI/CD authentication, required permissions
- [JWT Authentication Setup](docs/jwt-auth-setup.md) — Connected App and GitHub Secrets configuration

## License

[MIT](LICENSE)

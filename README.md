# HMG-AI GitHub governance

This repository is the organization-level source of truth for collaboration policy, community health files, issue and pull-request templates, and reusable GitHub Actions workflows.

## Repository map

- `profile/` — public organization profile.
- `.github/ISSUE_TEMPLATE/` — default issue forms inherited by repositories that do not define their own issue-template directory.
- `.github/workflows/` — reusable organization workflows and checks for this repository.
- `workflow-templates/` — starter workflows shown to HMG-AI repositories.
- `governance/` — declarative labels, team access, repository tiers, rulesets, and pinned CI tooling.
- `docs/` — the team workflow manual and administrator runbook.
- `scripts/` — repeatable audit and synchronization helpers.

## Change policy

Changes to governance must use a pull request, be reviewed by the governance CODEOWNERS, and preserve least-privilege permissions. Never commit credentials, personal access tokens, private keys, customer data, or production configuration here.

The canonical team guide is [docs/GITHUB_WORKFLOW_MANUAL.zh-CN.md](docs/GITHUB_WORKFLOW_MANUAL.zh-CN.md).

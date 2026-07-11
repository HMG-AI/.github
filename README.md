# HMG-AI GitHub governance

This public repository is the organization-level source of truth for community standards, issue and pull-request templates, and reusable GitHub Actions workflows. Internal access matrices, administrative procedures, and the full team workflow manual are maintained in the private `HMG-Documents` repository.

## Repository map

- `profile/` — public organization profile.
- `.github/ISSUE_TEMPLATE/` — default issue forms inherited by repositories that do not define their own issue-template directory.
- `.github/workflows/` — reusable organization workflows and checks for this repository.
- `workflow-templates/` — starter workflows shown to HMG-AI repositories.
- `governance/` — declarative public labels and pinned commit-policy tooling.

## Change policy

Changes to governance must use a pull request, be reviewed by the governance CODEOWNERS, and preserve least-privilege permissions. Never commit credentials, personal access tokens, private keys, customer data, or production configuration here.

Organization members can read the canonical team guide in [`HMG-Documents/github-governance`](https://github.com/HMG-AI/HMG-Documents/tree/main/github-governance).

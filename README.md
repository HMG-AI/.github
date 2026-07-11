# HMG-AI GitHub governance

This public repository is the organization-level source of truth for community standards, issue and pull-request templates, and reusable GitHub Actions workflows. Internal access matrices, administrative procedures, and the full team workflow manual are maintained in the private `HMG-Documents` repository.

## Repository map

- `profile/` — public organization profile.
- `.github/ISSUE_TEMPLATE/` — default issue forms inherited by repositories that do not define their own issue-template directory.
- `.github/workflows/` — reusable organization workflows, pinned required gates, and protected cross-repository promotion orchestration.
- `workflow-templates/` — starter workflows shown to HMG-AI repositories.
- `governance/` — declarative public labels and pinned commit-policy tooling.

## Change policy

Changes to governance must use a pull request, be reviewed by the governance CODEOWNERS, and preserve least-privilege permissions. Never commit credentials, personal access tokens, private keys, customer data, or production configuration here.

Automated cross-repository publication must use a target-repository branch and pull request. The HMG public release contract is centralized in `reusable-hmg-public-promotion.yml`; it never writes `HMG-public/main`, cannot approve its own pull request, and only enables auto-merge after the target rules and human review are satisfied. It prepares the exact public Git tree and ten release assets without target credentials, signs a canonical provenance statement in an isolated job that has no repository or Actions permissions, and exposes the target-scoped write token only while reconciling the deterministic staging release and promotion pull request.

Every automated promotion commit carries exactly eight governed trailers: source repository, stable source tag, source SHA, successful source workflow run, aggregate asset digest, candidate Git tree, reviewed Ed25519 key ID, and detached Ed25519 signature. `reusable-hmg-public-quality.yml` is the read-only, centrally governed build, drift, leak, stable-version, event-binding, candidate-tree, and signature gate. It shellchecks the target-owned release scripts and runs their classifier and publisher policy fixtures for every candidate, including ordinary governance pull requests. It also classifies HMG trailers across the immutable event commit range, so a merge-queue ref cannot bypass provenance checks; a governed merge group must contain exactly one complete promotion commit and its event-head tree must still equal the signed tree. It deliberately cannot read the write-visible staging draft and receives no write credential. Before merge it proves the final `vMAJOR.MINOR.PATCH` tag is absent; after merge, the environment-protected target publisher independently verifies the signed commit and staging bytes, creates the final tag once, publishes the release, and relies on immutable-release plus tag rules to prevent mutation. Production callers and required-workflow rulesets pin these files to reviewed full commit SHAs.

Organization members can read the canonical team guide in [`HMG-Documents/github-governance`](https://github.com/HMG-AI/HMG-Documents/tree/main/github-governance).

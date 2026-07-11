# HMG-AI repository governance

## Decision rights

- **Organization owners** manage billing, identity, organization policy, and emergency recovery. Owner membership is intentionally minimal.
- **Security managers** manage alerts, advisories, secret scanning, and incident coordination without receiving unrelated repository administration.
- **Repository maintainers** own roadmap, triage, review quality, releases, and repository settings for their assigned products.
- **Contributors** implement approved work through issues, branches, and pull requests with the least repository access needed.

Repository access is granted to teams, not directly to individuals, except for time-bounded outside collaboration that has an explicit owner and review date. The organization base permission is `none`.

## Changes to governance

Organization rulesets, teams, Actions policy, security defaults, reusable workflows, project fields, and this repository are controlled changes. Proposed changes must describe impact, migration, validation, rollback, and affected repositories. Governance changes require review from the governance CODEOWNERS and security review when permissions or trust boundaries change.

## Merge and release authority

Pull requests require current-head automated checks, current human approval, resolved conversations, and CODEOWNER review where configured. Direct pushes, force pushes, and default-branch deletion are blocked. Repositories use linear history and delete merged branches.

Release authority belongs to the release-manager team for the repository. Production credentials use GitHub environments or OIDC, never repository files. A release must have a traceable source commit/tag, validation evidence, release notes, and a rollback path.

Automation is subject to the same protected-default-branch policy as people. Cross-repository publication creates or updates a deterministic branch in the target repository, opens a same-repository pull request, and may enable auto-merge without approving or bypassing the pull request. The write credential is scoped to the target repository and is exposed only to the final branch/pull-request step; validation runs without it. Generated publication must preserve target-owned governance paths such as `.github/` and commit-policy configuration.

The HMG public promotion trust boundary is split into three fail-closed stages:

1. The source-side preparation job proves a canonical stable source tag is reachable from protected `HMG/main`, binds it to the exact successful `Build & Release` run, generates the target candidate from the current protected target base without credentials, validates the exact ten assets, and computes the aggregate asset digest and full candidate Git tree.
2. An isolated job with no repository or Actions permissions accepts only those validated scalar values, verifies the configured Ed25519 private-key fingerprint, and signs the canonical provenance statement. The target promotion commit records exactly the eight governed provenance trailers. The target-scoped write token is not available until the last job reconciles the deterministic staging transport and same-repository pull request.
3. The required target quality workflow has read-only contents permission, binds reusable inputs to the `pull_request` or `merge_group` event payload, shellchecks all target-owned release policy scripts, runs the target classifier and publisher policy fixtures, and classifies any HMG trailers across `BASE..HEAD`. The script fixtures run for every candidate, including ordinary governance pull requests, without secrets or persisted checkout credentials. A release pull request must be one promotion commit directly on its event base; a governed merge group must contain exactly one complete promotion commit and the event-head tree must equal the signed tree, so a changed base or another queued change fails closed. Partial, duplicate, or unknown HMG trailers fail. The gate also verifies the stable version increase, reviewed public-key ID, detached signature, target governance boundary, public builds, and absence of the final tag. It never receives a write credential and never reads the write-visible staging draft. After protected merge, the `hmg-public-release` environment publisher re-verifies the signed commit and exact staging bytes before creating the final tag once and publishing an immutable release.

The canonical promotion trailers are `HMG-Source-Repository`, `HMG-Source-Tag`, `HMG-Source-SHA`, `HMG-Workflow-Run`, `HMG-Asset-Set-SHA256`, `HMG-Candidate-Tree`, `HMG-Provenance-Key-ID`, and `HMG-Provenance-Signature-Ed25519`. The final `vMAJOR.MINOR.PATCH` tag must not exist before the protected promotion merges. Final tags are never moved or deleted, release assets are never overwritten, and a staging draft is transport state rather than review evidence. An interrupted staging asset in GitHub's `starter` state may be deleted by its immutable asset ID and uploaded again without clobber; every other non-`uploaded` state fails closed.

## Emergency changes

Default-branch bypass is not an emergency mechanism. The default-branch and required-quality rulesets keep an empty bypass-actor list for people, administrators, teams, apps, and automation. An incident may justify revoking credentials, freezing a deployment, disabling a compromised workflow, or repairing a misconfigured ruleset through organization administration, but it must not authorize a direct `main` push, skipped required check, self-approval, or admin merge.

Emergency source changes still use a minimal pull request, a current non-author approval, and every applicable quality gate after any broken rule configuration is repaired. The incident lead records the severity, exact administrative and repository changes, two-person authorization, validation, rollback, and follow-up issue. Restored ruleset payloads and audit evidence are verified immediately after recovery.

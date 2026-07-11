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

## Emergency changes

Emergency bypass is exceptional, time-bounded, and audited. The incident lead must record the severity, reason ordinary review cannot be completed, exact change, approver, validation, rollback, and follow-up issue. The bypass is removed immediately after recovery; a retrospective pull request restores normal evidence and review.

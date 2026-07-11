# Contributing to HMG-AI

Thank you for improving HMG. This file is the organization default; a repository may add stricter build, test, or release requirements.

## Before coding

1. Search existing issues and pull requests.
2. Create or claim an issue unless the change is a trivial typo.
3. Record the expected outcome, acceptance criteria, risks, and affected repositories in the issue.
4. For architecture, security, compatibility, data migration, or public API changes, obtain maintainer agreement before implementation.

## Branches

Create a short-lived branch from an up-to-date `main`:

```text
feat/123-federated-recall
fix/456-timeout-handling
docs/789-install-guide
chore/321-dependency-update
```

Do not push directly to `main`. Do not reuse a branch for unrelated changes.

## Commit messages

Every commit in a pull request must follow Conventional Commits:

```text
<type>(optional-scope): <imperative English summary>
```

Allowed common types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`. Use a standard type with a `security` scope for security work, for example `fix(security): reject expired session tokens`. The subject, body, and footer must not contain Han-script characters. Use English commit messages so release automation and cross-team history remain consistent. Documentation and issue discussion may be written in Chinese or English.

Examples:

```text
feat(recall): add federated source weighting
fix(daemon): bound named-pipe read timeout
docs(workflow): explain emergency hotfix reviews
```

For a breaking change, add `!` after the type or scope and include a `BREAKING CHANGE:` footer.

## Pull requests

- Keep one coherent outcome per pull request and link its issue with `Closes #123` when appropriate.
- Complete every section of the pull-request template.
- Add or update tests and documentation in the same pull request.
- Never include secrets, customer data, generated credentials, or production dumps.
- Request review only when required checks are ready to run.
- Resolve every review conversation. New commits dismiss stale approvals.
- Do not merge your own pull request unless an explicitly documented emergency procedure applies.

The required commit check validates every commit from the pull-request base through its latest head in a pinned Docker environment. An additional approval-time audit reruns the same policy, but the latest-head check—not the approval event—is the authoritative merge gate.

## Validation

Run the repository's documented format, lint, unit, integration, security, and packaging checks. Include exact commands and outcomes in the pull request. A narrow test does not prove a repository-wide claim.

## Review behavior

Reviews should address correctness, maintainability, security, compatibility, observability, test coverage, rollout, and rollback. Use GitHub review states consistently:

- **Comment** for non-blocking questions or suggestions.
- **Request changes** for an issue that must be fixed before merge.
- **Approve** only after required concerns are resolved and the current diff is acceptable.

Be specific and respectful. Discuss the code and its impact, not the person.

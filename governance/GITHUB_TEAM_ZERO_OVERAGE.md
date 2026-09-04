# HMG-AI GitHub Team zero-overage policy

## Cost objective

Effective 2026-09-04, this policy is the billing and workflow boundary for
`HMG-AI` on GitHub Team.

The organization may incur only the approved monthly GitHub Team seat
subscription. Usage-based products must never roll into paid overage.

The organization therefore maintains zero-dollar hard budgets for GitHub
Actions, Packages, Codespaces, Git LFS, GitHub Models, GitHub Advanced
Security products, Copilot/Spark AI credits, and Copilot sandboxes. Budget
alerts remain enabled for the organization owner.

## Actions boundary

- Private-repository Actions are disabled by default.
- `HMG-AI/HMG` is the only private repository allowed to build HMG product
  packages. Its only approved hosted package build is the manual macOS
  workflow.
- Linux and Windows HMG package creation and publication preparation run
  locally. Local evidence is reviewed before assets are added to the private
  draft release.
- The three private website repositories may run CI and manual deployment on
  standard Linux runners: `HMG-Website-Index-React`,
  `HMG-Website-Admin-React`, and `HMG-website-backend`. Website workflows must
  not build new Linux or Windows HMG release packages; they may consume a
  previously published, checksum-pinned HMG runtime for deployment.
- Website deployment remains manually dispatched. CI may run for pull
  requests, merge queues, and protected-branch updates. Scheduled deployment
  and larger runners are not authorized.
- Public repositories may use standard GitHub-hosted runners because their
  runner minutes are free. They must not use larger runners, custom images, or
  paid external services.
- Workflow permissions default to read-only. A job gets `contents: write` only
  for the narrow release step that needs it.
- Third-party actions are allow-listed and pinned to immutable commits.
- Organization artifact/log retention and cache retention are one day.
- Release binaries belong in GitHub Releases, not long-lived Actions
  artifacts. Do not publish build outputs to GitHub Packages.

## Repository classes

| Class | Repositories | Actions policy |
| --- | --- | --- |
| Private release authority | `HMG` | macOS package workflow only |
| Private website delivery | `HMG-Website-Index-React`, `HMG-Website-Admin-React`, `HMG-website-backend` | CI and manual deployment on standard Linux runners |
| Private mirrors and other products | all remaining private repositories | Actions disabled; local checks/build/deploy |
| Public governance and distribution | `.github`, `HMG-Benchmark`, `HMG-public` | standard runners allowed; no paid runners/services |

`HMG-DEV-brach` remains an exact-source mirror. It must not acquire a
mirror-only workflow or source change; all validation is performed from the
authoritative `HMG` source and governed provenance.

## Separately billed security and developer products

- Secret Protection and Code Security stay disabled for private repositories.
  Public repositories retain GitHub's free public secret scanning.
- Organization-paid Codespaces are not authorized.
- Paid Copilot seats, AI credit overages, Models inference, Spark, sandboxes,
  larger runners, custom runner images, Git LFS overages, and Marketplace
  subscriptions require a new explicit budget decision before enablement.
- Dependabot and dependency graph features may remain enabled where GitHub
  supplies them without Actions minute charges. Their pull requests must not
  reactivate private-repository Actions.

## Change control

Any proposal that changes a budget above USD 0, removes the hard-stop flag,
adds a private repository to Actions beyond the four approved private
repositories, creates a larger runner, increases retention, enables a
separately billed product, or introduces a package registry must be approved
by an organization owner as a billing change.

The monthly review must compare the billing usage report with this policy and
record any non-zero net amount, its source, the immediate stop action, and the
remediation owner.

The review must also verify that the Team seat count is intentional, every
hard budget still has an amount of zero and stops further usage, only the seven
approved repositories have Actions access, website deployment remains manual,
no private repository has paid security enabled, and no paid Copilot,
Codespaces, Marketplace, larger-runner, or custom-image assignment exists.

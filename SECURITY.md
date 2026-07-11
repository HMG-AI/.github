# Security policy

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue, discussion, pull request, or commit message.

Use the repository's **Security → Report a vulnerability** form when private vulnerability reporting is enabled. If that option is unavailable, email `monkseekee@gmail.com` with:

- the affected repository, component, and version;
- a concise description and potential impact;
- reproducible steps or a minimal proof of concept;
- any known mitigations;
- your preferred contact and disclosure credit.

Do not include real credentials, customer data, or destructive exploit output. Replace secrets with clearly marked test values.

## Response targets

- Acknowledge receipt within 2 business days.
- Complete initial severity triage within 5 business days.
- Provide a remediation or mitigation plan within 30 days for confirmed issues, adjusted for severity and coordinated disclosure needs.

We will credit good-faith reporters unless anonymity is requested. HMG-AI will not pursue legal action for research that avoids privacy violations, service disruption, persistence, data destruction, and public disclosure before a coordinated fix.

## Supported versions

Each product repository documents its supported versions and release channel. In general, security fixes target the latest maintained release line; unsupported versions may require upgrading before a fix can be applied.

## Maintainer handling

Security reports are restricted to the security team. Maintainers must avoid copying report content into ordinary issues, logs, or public project items. Use a private security advisory for investigation, CVE coordination, and the fix fork. Rotate any credential exposed during reproduction and record the incident timeline without embedding the secret.

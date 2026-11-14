# Security policy

## Supported versions

The latest release tag is supported. Fixes are released from `main` and
backported only when a supported deployment cannot upgrade.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through GitHub's private
vulnerability reporting:

<https://github.com/allure-rocks/allure/security/advisories/new>

If you cannot use GitHub, write to <security@allure.rocks> with a minimal
description and a way to reach you; do not include exploit details in a public
channel.

Please include:

- the Allure version (the footer shows it) and the deployment shape (Docker
  Compose, reverse proxy, federation on or off);
- the affected surface (authentication, federation inbox, media, REST API,
  webhooks, MCP, import, admin console);
- the steps to reproduce and the impact you believe it has;
- any log line, request or payload that helps, with secrets and personal data
  removed.

## What to expect

- An acknowledgement within a few days.
- A coordinated disclosure: we agree on a date, prepare the fix and the
  release, and credit you unless you prefer otherwise.
- Please do not test against instances you do not own. The public demo at
  <https://demo.allure.rocks> is disposable, but it is not a target: do not
  attack it, and do not upload personal data.

## Scope

In scope: the application in this repository, its federation protocol, its
authentication and session handling, its media and publication pipeline, its
REST API, webhooks, MCP endpoint, import sources and the administration
console.

Out of scope: vulnerabilities in third-party services or providers, social
engineering, denial of service through sheer volume, and issues that require a
compromised operator account.

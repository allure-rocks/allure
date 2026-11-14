---
layout: home

hero:
  name: Allure
  text: Run your own sport-tracking instance
  tagline: Import GPS activities, analyse them, and share them across the fediverse — on a server you control.
  image:
    src: /icon.svg
    alt: Allure
  actions:
    - theme: brand
      text: Quick start
      link: /install/quick-start
    - theme: alt
      text: What is Allure?
      link: /guide/what-is-allure

features:
  - title: Self-hosted
    details: One Docker Compose stack — Rails, PostgreSQL with PostGIS, background workers and a mail relay. No Redis, no external queue.
  - title: Private by default
    details: Activities stay unpublished until their owner shares them, privacy zones are cut from the shared copy, and every optional service — geocoding, weather, remote imports, federation — is off until you turn it on.
  - title: Federated
    details: Instances follow each other over ActivityPub. Publications, comments and reactions travel between Allure servers.
---

This documentation is for **operators** — the people who install and run an
Allure instance. It describes the latest release; the version is shown in the
top bar.

The REST API, webhooks and MCP endpoint are documented by each instance itself
at `/developers/api`, so the reference always matches the version you run.

# What is Allure?

Allure is a self-hostable sport-tracking application. Its members import
activities recorded by GPS watches, bike computers and phone apps, read a
detailed analysis of each one, and choose what to share — with their followers,
with every member of the instance, or with other Allure instances over
ActivityPub.

## What members can do

- **Import** GPX, FIT and TCX files (one at a time, in batches, or as ZIP
  archives), a whole Strava export archive, activities read from some iGPSPORT
  bike computers over Bluetooth, or — when you enable them — activities pulled
  from Garmin Connect and EXR.
- **Analyse** each activity: maps, elevation and speed profiles, splits and
  laps, best efforts over standard distances, heart-rate zones and training
  load, segments with leaderboards, weather along the route.
- **Publish** a sanitized copy of an activity through a publishing profile.
  The owner decides which figures are shared; privacy zones are cut from the
  route before the copy is made, and the copy never changes afterwards.
- **Follow** people on the same instance or on other Allure instances, comment,
  react, and record outings done together.
- **Automate** through a REST API, signed webhooks, and an MCP endpoint for AI
  assistants.
- **Leave**: every member can export all their data and delete their account
  themselves.

## What the operator does

You install and upgrade the instance, decide who may join (closed by default:
invitation links only), choose which optional services the instance uses
(geocoding, terrain elevation, weather, remote imports, push notifications,
federation), and keep it healthy from the administration console at `/admin`
and the Prometheus endpoint at `/metrics`.

Every page of the application except the sign-in and registration pages is
reserved to signed-in members. Federation, when enabled, exposes only what the
ActivityPub protocol needs.

## Where to go next

- [Requirements](./requirements) — what you need before installing.
- [How an instance works](./architecture) — the containers, queues and data
  stores, and which third parties an instance may talk to.
- [Quick start](../install/quick-start) — install with Docker Compose.

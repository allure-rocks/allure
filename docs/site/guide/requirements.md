# Requirements

## Server

- A Linux host on **amd64 or arm64** with **Docker Engine** and the
  **Docker Compose** plugin. Nothing else runs on the host: Ruby, Node,
  PostgreSQL and Chromium all live in containers.
- **Memory:** plan for at least 4 GB. The route-image worker alone is capped at
  2 GB and one CPU, because it renders maps in a headless Chromium.
- **CPU:** two cores or more. Imports, analysis and image rendering run in the
  background, so a small machine is slower, not broken.
- **Disk:** PostgreSQL holds the analysed tracks; the storage volume holds every
  original file, every rendered route image and every photo. Members get a
  photo quota (2 GB each by default, see
  [`PHOTOS_QUOTA_MB`](../configuration/environment#photos)), so size the disk for
  your members' photos as well as their activities.

## Network and DNS

- A **stable public hostname**, for example `allure.example.org`. With
  federation, the hostname — scheme and port included — becomes part of every
  account's permanent identity. Choose it once.
- A **reverse proxy that terminates TLS** in front of the application. Allure
  only accepts HTTPS requests in production; see
  [Reverse proxy and TLS](../install/reverse-proxy).
- **Outbound HTTPS** from the worker containers, for map tiles in route images,
  federation, and whichever optional services you enable.

## Mail

Allure sends password resets, invitations, security notices and export
notifications. The stock stack ships a Postfix relay that delivers straight to
the recipients' mail servers, which needs:

- outbound port 25 open (many cloud providers block it by default);
- a reverse DNS (PTR) record for the server's address;
- SPF and DMARC records for the sending domain.

If you cannot meet these, relay through your mail provider instead — see
[Mail](../configuration/mail).

## Building the image

The image is built from this repository's `Dockerfile`, so the host needs a
checkout of the source and enough disk and memory for a Docker build (the build
compiles native gems and the frontend).

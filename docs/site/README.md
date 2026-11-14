# Operator documentation

The public site at <https://docs.allure.rocks>, built with
[VitePress](https://vitepress.dev). It is written in English only and is for
the people who install and run an instance. Member-facing help belongs in the
application; contributor contracts are maintained with the source.

This directory is never part of the production image (`.dockerignore`).

## Working on it

```sh
dip docs_install   # once, and after a dependency change
dip docs           # http://localhost:5173, live reload
dip docs_build     # what CI runs; fails on a dead link
```

The site has its own `package.json`, separate from the application's.

## Keeping it true

- `spec/docs/environment_reference_spec.rb` fails when the application, the
  production Compose file or `production.env.example` uses an environment
  variable that `configuration/environment.md` does not document, or when that
  page documents one nothing uses.
- `spec/docs/rake_tasks_spec.rb` fails when a page names a `bin/rails` task
  that does not exist.
- A change to a variable, the Compose file, a task or the deployment updates
  these pages in the same patch.

## Versions

The site shows the version in `config/version.rb` and documents the latest
release only; it is deployed when a release tag is pushed.

To keep an older release online later: build that release's tag with
`DOCS_BASE=/v0.8/`, place its output under `v0.8/` of the published site, and
add `{ "version": "0.8.7", "path": "/v0.8/" }` to `archived` in
`versions.json`, which feeds the version menu.

## Hosting

GitHub Pages, from the `docs` job of `.github/workflows/release.yml`: on a
release tag it builds this site and deploys `docs/site/.vitepress/dist`. In the
repository's Pages settings, choose “GitHub Actions” as the source, set the
custom domain `docs.allure.rocks` and verify it for the organisation; the
`docs` DNS record is a CNAME to `<organisation>.github.io`, with “Enforce
HTTPS” on. The `github-pages` environment must allow `v*` tags (Settings →
Environments → github-pages → Deployment branches and tags).

The repository URL, the edit-link pattern (`/edit/main/docs/site/:path`) and the
social icon live in `.vitepress/config.mts`; the clone URL in
`install/quick-start.md` and `Allure::Instance::DEFAULT_SOURCE_URL` (the About
dialog's source link) point at the same repository.

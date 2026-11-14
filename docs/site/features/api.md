# API, webhooks and MCP

Every instance offers its members a REST API, signed webhooks and an MCP
endpoint for AI assistants. They need no configuration; this page covers what
the operator controls.

## Where the reference lives

Each instance documents its own API, so the reference always matches the
version it runs:

| Path | Content | Access |
|---|---|---|
| `/developers/api` | Guide and interactive reference | Members |
| `/api/rest/v1/openapi.json`, `.yaml` | The OpenAPI 3.1 document | Public |
| `/api/rest/v1/…` | The REST API | Bearer token |
| `/mcp` | The MCP endpoint (`POST` only) | Bearer token with the `read` scope |

Members create tokens at `/settings/api` after confirming their identity. A
token has scopes (`read`, `write`, `import`, `publish`, `social:read`,
`webhooks`) and expires after 30, 90 or 365 days.

## Rate limits

Per token: 300 requests per minute, of which at most 60 changes, and 20 imports
per hour. Beyond that the API answers `429`.

## Location sent to AI assistants

When a member creates a token for an assistant, they choose how much location
it may receive through `/mcp`: `none`, `filtered` (privacy zones removed) or
`raw`. `MCP_GEOMETRY_MAX` caps that choice for the whole instance:

```sh
MCP_GEOMETRY_MAX=filtered
```

The ceiling applies immediately to existing tokens as well. Unset means no
ceiling.

## Webhooks

Members register up to ten endpoints. Deliveries are signed (Standard
Webhooks), sent by the `worker` container on the `webhooks` queue, at most two
at a time per endpoint, and:

- go to **HTTPS** endpoints on **public addresses** only, checked when the
  endpoint is saved and again before each attempt; redirects are not followed;
- are retried for about 21 hours (1 min, 5 min, 30 min, 2 h, 6 h, 12 h);
- stop when the endpoint answers `410`, or after 20 failures in a row over at
  least three days, which disables it and notifies its member.

## Operator controls

On `/admin/accounts/:id`, the operator can **revoke** any of the account's API
tokens and **disable** any of its webhooks. Both are audited; a disabled
webhook notifies its member.

## Metrics

`allure_api_tokens`, `allure_api_requests_total`, `allure_mcp_requests_total`,
`allure_webhook_endpoints`, `allure_webhook_deliveries` and
`allure_webhook_delivery_oldest_pending_seconds`.

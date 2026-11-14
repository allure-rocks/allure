# Reverse proxy and TLS

The production stack publishes no port. A reverse proxy you run terminates TLS
and forwards requests to the `rails` container on port `3000`.

## What the proxy must do

- **Terminate HTTPS.** Allure assumes it is behind TLS: it marks cookies secure,
  sends `Strict-Transport-Security`, and redirects plain HTTP to HTTPS.
- **Keep the `Host` header.** Rails only answers requests whose host is
  `APP_HOST` (or one listed in `ALLOWED_HOSTS`); anything else gets an error.
- **Leave Allure's response headers alone.** Allure sends its own
  `Content-Security-Policy`; a proxy that adds or replaces one breaks the
  maps, the sign-in pages or the API reference. Add an origin with
  `CONTENT_SECURITY_POLICY_SOURCES` instead.
- **Pass request headers through unchanged.** Federation signs requests over
  `Host`, `Date`, `Digest` and the request path; a proxy that rewrites any of
  them breaks signature checks.
- **Accept large uploads only where they belong.** A Strava archive may be up
  to 2 GiB and a batch of activity files up to 500 MiB, both sent to three
  paths: `/workout_imports`, `/workout_imports/strava_archive` and
  `/api/rest/v1/imports`. Allow those 2112 MiB (the archive plus its form
  overhead) and a long read timeout; keep every other path at 32 MiB, the
  largest a photo or an avatar needs. The proxy is the only layer that refuses
  a body before it reaches the container's disk: behind it, Puma refuses
  anything over 2112 MiB before buffering, and Allure then holds each path to
  its own limit (`413 Content Too Large`) before reading the form. Allure
  bounds the rest itself: a member may have at most 3 file imports and 1
  Strava archive waiting, upload at most 6 GB in 24 hours, and the uploaded
  files are deleted once their import finishes.

The health check is `GET /up`; it answers over plain HTTP so a load balancer can
probe it.

## Reaching the container

The `rails` container publishes no port. Attach your proxy to the
stack's `backend` network, named `allure-production_backend` by Docker, and
address the application as `rails:3000`.

### Caddy

A separate Compose project next to the stack:

```yaml
# proxy/compose.yml
services:
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
    networks:
      - default
      - allure

networks:
  allure:
    external: true
    name: allure-production_backend

volumes:
  caddy_data:
```

```txt
# proxy/Caddyfile
allure.example.org {
	@imports path /workout_imports /workout_imports/strava_archive /api/rest/v1/imports
	handle @imports {
		request_body {
			max_size 2112MiB
		}
		reverse_proxy rails:3000
	}
	handle {
		request_body {
			max_size 32MiB
		}
		reverse_proxy rails:3000
	}
}
```

Caddy obtains and renews the certificate itself.

### nginx

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name allure.example.org;

    ssl_certificate     /etc/letsencrypt/live/allure.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/allure.example.org/privkey.pem;

    client_max_body_size 32m;
    proxy_read_timeout   300s;
    proxy_request_buffering off;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    # The three upload paths: a 2 GiB Strava archive plus its form overhead.
    location ~ ^/(workout_imports(/strava_archive)?|api/rest/v1/imports)$ {
        client_max_body_size 2112m;
        proxy_pass http://rails:3000;
    }

    location / {
        proxy_pass http://rails:3000;
    }
}
```

The nginx container must also join `allure-production_backend`. If nginx runs on
the host instead, publish the port through a [Compose override](./overrides#publishing-the-port-on-the-host).

## Checking

```sh
curl -I https://allure.example.org/up
```

A `200` means the proxy, the hostname and the application agree. A `403` on
every page usually means the `Host` header the proxy sends does not match
`APP_HOST`.

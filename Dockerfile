# syntax=docker/dockerfile:1
# check=error=true

# Allure production image. The normal app target contains Rails and the
# compiled Vite output only. The route-image-worker target adds the small Node
# runtime, route renderer sources, Playwright Core, MapLibre and Chromium.

ARG RUBY_VERSION=4.0.10
ARG NODE_VERSION=24.22.0

FROM docker.io/library/node:${NODE_VERSION}-slim AS node

FROM docker.io/library/ruby:${RUBY_VERSION}-slim-trixie AS base

WORKDIR /rails

# Runtime libraries only. Compilers and -dev packages stay in the build stage.
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y \
       ca-certificates \
       libgeos-c1t64 \
       libjemalloc2 \
       libproj25 \
       libpq5 \
       librsvg2-2 \
       libvips42t64 \
       libyaml-0-2 \
  && ln -sf /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so \
    PATH=/rails/bin:/usr/local/bundle/bin:$PATH

FROM base AS build

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm

RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && apt-get update -qq \
  && apt-get install --no-install-recommends -y \
       build-essential \
       git \
       libgeos-dev \
       libproj-dev \
       libpq-dev \
       libvips-dev \
       libyaml-dev \
       pkg-config \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Ruby dependencies are isolated from application changes.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local no-document true \
  && bundle install --jobs "$(nproc)" --retry 3 \
  && rm -rf ~/.bundle /usr/local/bundle/ruby/*/cache /usr/local/bundle/ruby/*/bundler/gems/*/.git \
  && find /usr/local/bundle -name .git -type d -prune -exec rm -rf {} + \
  && bundle exec bootsnap precompile -j 1 --gemfile

# JavaScript dependencies are isolated from application changes. Development
# dependencies are needed only to compile Vite and are not copied to the Rails
# runtime image.
COPY package.json package-lock.json ./
RUN npm ci --include=dev --ignore-scripts

FROM build AS frontend

# Only frontend inputs invalidate the Vite layer.
COPY bin/sync-icon-fonts ./bin/sync-icon-fonts
COPY vite.config.ts ./vite.config.ts
COPY config/vite.json ./config/vite.json
COPY app/frontend ./app/frontend
COPY app/views ./app/views
COPY public ./public

RUN npm run postinstall \
  && npx vite build

FROM frontend AS route-deps

# The route worker needs only runtime dependencies from Node. The Vite toolchain
# remains in the intermediate build layers and never reaches the final images.
RUN npm prune --omit=dev

FROM frontend AS app-build

# Backend changes are copied after the frontend build so they do not invalidate
# the expensive npm install and Vite compilation layers.
COPY app/channels ./app/channels
COPY app/controllers ./app/controllers
COPY app/federation ./app/federation
COPY app/helpers ./app/helpers
COPY app/jobs ./app/jobs
COPY app/mailers ./app/mailers
COPY app/mcp ./app/mcp
COPY app/models ./app/models
COPY app/serializers ./app/serializers
COPY app/services ./app/services
COPY config ./config
COPY db ./db
COPY lib ./lib
COPY bin ./bin
COPY script ./script
# The served OpenAPI document (Api::Rest::V1::Document); the rest of docs/ is
# not the application's.
COPY docs/openapi ./docs/openapi
COPY Rakefile config.ru ./

RUN chmod +x bin/* \
  && mkdir -p tmp/cache/bootsnap tmp/pids storage \
  && bundle exec bootsnap precompile -j 1 app/ lib/ \
  && find public/vite -type f -name '*.map' -delete \
  && rm -rf node_modules/.vite tmp/cache/vite log/*

FROM base AS app

RUN groupadd --system --gid 1000 rails \
  && useradd rails --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin

COPY --from=app-build /usr/local/bundle /usr/local/bundle
COPY --from=app-build --chown=rails:rails /rails/Gemfile /rails/Gemfile
COPY --from=app-build --chown=rails:rails /rails/Gemfile.lock /rails/Gemfile.lock
COPY --from=app-build --chown=rails:rails /rails/app/channels /rails/app/channels
COPY --from=app-build --chown=rails:rails /rails/app/controllers /rails/app/controllers
COPY --from=app-build --chown=rails:rails /rails/app/federation /rails/app/federation
COPY --from=app-build --chown=rails:rails /rails/app/helpers /rails/app/helpers
COPY --from=app-build --chown=rails:rails /rails/app/jobs /rails/app/jobs
COPY --from=app-build --chown=rails:rails /rails/app/mailers /rails/app/mailers
COPY --from=app-build --chown=rails:rails /rails/app/mcp /rails/app/mcp
COPY --from=app-build --chown=rails:rails /rails/app/models /rails/app/models
COPY --from=app-build --chown=rails:rails /rails/app/serializers /rails/app/serializers
COPY --from=app-build --chown=rails:rails /rails/app/services /rails/app/services
COPY --from=app-build --chown=rails:rails /rails/app/views /rails/app/views
COPY --from=app-build --chown=rails:rails /rails/config /rails/config
COPY --from=app-build --chown=rails:rails /rails/db /rails/db
COPY --from=app-build --chown=rails:rails /rails/lib /rails/lib
COPY --from=app-build --chown=rails:rails /rails/public /rails/public
COPY --from=app-build --chown=rails:rails /rails/bin /rails/bin
COPY --from=app-build --chown=rails:rails /rails/docs/openapi /rails/docs/openapi
COPY --from=app-build --chown=rails:rails /rails/Rakefile /rails/Rakefile
COPY --from=app-build --chown=rails:rails /rails/config.ru /rails/config.ru
COPY --from=app-build --chown=rails:rails /rails/tmp/cache/bootsnap /rails/tmp/cache/bootsnap

RUN mkdir -p /rails/storage /rails/tmp/pids \
  && chown -R rails:rails /rails/storage /rails/tmp

USER 1000:1000

EXPOSE 3000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]

FROM app AS route-image-worker

USER root

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=route-deps --chown=rails:rails /rails/node_modules /rails/node_modules
COPY --from=app-build --chown=rails:rails /rails/script /rails/script
COPY --from=app-build --chown=rails:rails /rails/app/frontend/lib /rails/app/frontend/lib

RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y chromium \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
  && chown -R rails:rails /rails/app/frontend /rails/node_modules /rails/script

ENV CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium \
    SOLID_QUEUE_QUEUES=route_images \
    SOLID_QUEUE_THREADS=1

USER 1000:1000

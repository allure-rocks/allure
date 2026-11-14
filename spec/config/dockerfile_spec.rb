# frozen_string_literal: true

require "rails_helper"

# The Dockerfile copies app/ one directory at a time, so a new directory is
# absent from the production image until it is listed there — in development
# the whole tree is bind-mounted and nothing shows. app/serializers and app/mcp
# shipped missing this way (0.6.2, 0.6.3).
RSpec.describe "Dockerfile" do
  let(:dockerfile) { Rails.root.join("Dockerfile").read }

  # Built by Vite (frontend, views copied with it) or unused by the
  # application (the generator's asset placeholders).
  let(:exempt) { %w[assets frontend] }

  it "copies every application directory into the build stage and the final image" do
    directories = Rails.root.join("app").children.select(&:directory?).map { it.basename.to_s } - exempt

    directories.each do |directory|
      expect(dockerfile).to include("COPY app/#{directory} ./app/#{directory}")
      expect(dockerfile).to include("/rails/app/#{directory} /rails/app/#{directory}")
    end
  end

  # app/frontend is exempt above because only Vite reads it, and the final
  # image does not carry it. A file the server reads at render time belongs
  # under a copied directory instead: the weather icons shipped missing from
  # app/frontend this way (0.8.3) and now live in app/views like the sport
  # icons.
  it "keeps every file the server reads out of app/frontend" do
    frontend = Rails.root.join("app/frontend").to_s

    expect(WeatherHelper::WEATHER_ICON_ROOT.to_s).not_to start_with(frontend)
    expect(WeatherHelper::WEATHER_ICON_STATIC_ROOT.to_s).not_to start_with(frontend)
    expect(WeatherHelper::WEATHER_ICON_ROOT.join("clear-day.svg")).to exist
    expect(WeatherHelper::WEATHER_ICON_STATIC_ROOT.join("clear-day.svg")).to exist
  end

  # The other half of the same contract: development-only code stays out of the
  # build context, so COPYing it fails the build instead of shipping silently.
  # `devtools/` carries the impersonation tool; the demo loader is required by
  # db/seeds.rb under `Rails.env.development?` only, and both halves have to
  # hold together — the image has no copy of the file the require names.
  it "keeps development-only code out of the build context" do
    ignore = Rails.root.join(".dockerignore").read

    [ "/devtools/", "/db/seeds/development.rb", "/db/seeds/demo/" ].each do |path|
      expect(ignore).to include(path)
    end

    expect(dockerfile).not_to include("devtools")
    expect(dockerfile).not_to include("db/seeds/demo")

    expect(Rails.root.join("db/seeds.rb").read)
      .to include('require_relative "seeds/development" if Rails.env.development?')
  end

  # The demo image is the one place those seed inputs ship, through its own
  # ignore file: everything else stays out, so it adds nothing but them.
  it "admits only the demo seed inputs into the demo image's context" do
    ignore = Rails.root.join("Dockerfile.demo.dockerignore").read.lines.map(&:strip).reject { it.empty? || it.start_with?("#") }

    expect(ignore).to eq([ "*", "!db/seeds/demo/", "!spec/fixtures/gpx/", "!script/fetch-fit-corpus" ])
    expect(Rails.root.join("Dockerfile.demo").read).to include("FIT_CORPUS_FILES=/corpus/files.txt")
  end

  # The REST API serves docs/openapi/v1.yaml at request time, so the image must
  # carry it even though the rest of docs/ stays out (0.8.7 shipped without it).
  it "copies the served OpenAPI document into the final image" do
    path = Api::Rest::V1::Document::PATH.relative_path_from(Rails.root).dirname.to_s

    expect(path).to eq("docs/openapi")
    expect(dockerfile).to include("COPY #{path} ./#{path}")
    expect(dockerfile).to include("/rails/#{path} /rails/#{path}")
    expect(Rails.root.join(".dockerignore").read).not_to match(%r{^/docs/?$})
  end

  # Active Storage writes under Rails.root/storage, and Rails.root in the image
  # is its WORKDIR. The production Compose file mounted /app/storage (the
  # development image's path) until 0.8.7, so files stayed in each container's
  # own layer, unshared and lost on recreation.
  it "mounts the production storage volume where the image's Active Storage writes" do
    workdir = dockerfile[/^WORKDIR (\S+)$/, 1]
    compose = Rails.root.join("docker-compose.production.yml").read

    expect(workdir).to eq("/rails")
    expect(Rails.root.join("config/storage.yml").read).to include('Rails.root.join("storage")')
    expect(compose).to include("allure_storage:#{workdir}/storage")
    expect(compose).not_to include("allure_storage:/app/")
  end

  # The operator documentation is a separate static site with its own npm
  # package (docs/site/README.md); none of it belongs in the image.
  it "keeps the documentation site out of the build context" do
    expect(Rails.root.join(".dockerignore").read).to include("/docs/site/")
    expect(dockerfile).not_to include("docs/site")
  end
end

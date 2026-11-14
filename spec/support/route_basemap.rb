# frozen_string_literal: true

# Publishing fetches raster tiles for the published route image, exactly like
# the owner image's post-retry fallback. Specs must stay offline and
# deterministic, so the default stub makes every fetch fall back to the
# tile-less renderer. Specs that prove the basemap path stub it themselves.
RSpec.configure do |config|
  config.before do
    allow_any_instance_of(Workouts::RouteBasemapFetcher)
      .to receive(:call).and_return(nil)
  end
end

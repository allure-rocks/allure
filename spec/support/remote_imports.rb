# frozen_string_literal: true

# Remote import sources (docs/dev/REMOTE-IMPORTS.md): an in-memory provider that
# answers the adapter surface, the shared examples every real adapter must
# pass, and a helper that enables a provider's operator flag for one example.
#
# The test container inherits the developer's flags; every spec starts with
# all providers disabled and enables what it needs.
Allure::RemoteImports::Config::FLAGS.each_value { |key| ENV.delete(key) }

module RemoteImportHelpers
  # Serves `activities` (RemoteActivity values) and, for `fetch`, the bytes in
  # `files` keyed by external id. `errors` maps an external id to an error to
  # raise on fetch; `list_error` is raised by `list`; `photos` maps an external
  # id to the `PhotoSet` the provider offers.
  class FakeImportProvider
    attr_reader :fetched, :listed_windows, :deauthorized

    def initialize(activities: [], files: {}, errors: {}, list_error: nil, equipment: [], fetch_attributes: {},
                   photos: {})
      @activities = activities
      @files = files
      @errors = errors
      @list_error = list_error
      @equipment = equipment
      @fetch_attributes = fetch_attributes
      @photos = photos
      @fetched = []
      @listed_windows = []
      @deauthorized = false
    end

    def list(from:, to:)
      raise @list_error if @list_error

      @listed_windows << [ from, to ]
      @activities.select { |activity| activity.started_at.nil? || (from..to).cover?(activity.started_at) }
    end

    def fetch(activity)
      @fetched << activity.external_id
      error = @errors[activity.external_id]
      raise error if error

      bytes = @files.fetch(activity.external_id)
      io = Tempfile.new([ "fake-remote", ".gpx" ], binmode: true)
      io.write(bytes)
      io.rewind
      Allure::RemoteImports::FetchedActivity.new(
        io:, filename: "remote-#{activity.external_id}.gpx", **@fetch_attributes.fetch(activity.external_id, {})
      )
    end

    def equipment = @equipment

    def photos(activity) = @photos.fetch(activity.external_id, Allure::RemoteImports::PhotoSet.new)

    def deauthorize!
      @deauthorized = true
    end
  end

  def remote_activity(external_id, started_at: Time.utc(2026, 9, 1, 8), ended_at: nil, name: "Ride #{external_id}",
                      geometry: true, sport_hint: nil, manual: false, provider_metadata: {})
    Allure::RemoteImports::RemoteActivity.new(external_id: external_id.to_s, name:, started_at:, ended_at:, sport_hint:,
                                              geometry:, manual:, provider_metadata:)
  end

  def with_remote_import_enabled(provider = "garmin_connect", enabled: true)
    key = Allure::RemoteImports::Config::FLAGS.fetch(provider)
    previous = ENV[key]
    ENV[key] = enabled ? "true" : nil
    yield
  ensure
    ENV[key] = previous
  end
end

# The adapter surface the remote batch job depends on (docs/dev/REMOTE-IMPORTS.md
# §5.1). Include with `provider` built for a linked connection and
# `listed_activity` returning an activity the stubs serve.
RSpec.shared_examples "an import provider" do
  it "lists RemoteActivity values" do
    activities = provider.list(from: Time.utc(2000), to: Time.utc(2100)).to_a

    expect(activities).to all(be_a(Allure::RemoteImports::RemoteActivity))
    expect(activities.map(&:external_id)).to all(be_a(String))
  end

  it "fetches a readable original file" do
    fetched = provider.fetch(listed_activity)

    expect(fetched).to be_a(Allure::RemoteImports::FetchedActivity)
    expect(Allure::ImportFormat::EXTENSIONS).to include(File.extname(fetched.filename).downcase)
    expect(fetched.io.read(1)).not_to be_nil
  ensure
    fetched&.io&.close
  end

  it "offers the activity's photos as a PhotoSet" do
    expect(provider.photos(listed_activity)).to be_a(Allure::RemoteImports::PhotoSet)
  end

  it "lists RemoteEquipment values" do
    expect(provider.equipment.to_a).to all(be_a(Allure::RemoteImports::RemoteEquipment))
  end

  it "deauthorizes without raising" do
    expect { provider.deauthorize! }.not_to raise_error
  end
end

RSpec.configure do |config|
  config.include RemoteImportHelpers
end

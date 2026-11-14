# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/demo/seeder")
require Rails.root.join("db/seeds/demo/manifests/full")
require Rails.root.join("db/seeds/demo/manifests/minimal")
require Rails.root.join("db/seeds/demo/datasets")
require Rails.root.join("db/seeds/demo/corpus_files")

# The development manifests are data the seeder trusts: every reference has to
# resolve, every corpus path has to be a real corpus file, and no recording may
# belong to two accounts.
RSpec.describe "Demo seed manifests" do
  DEMO_CORPUS_ROOT = Rails.root.join("references_apps/fit-test-files").freeze
  DEMO_CORPUS_PATH = %r{\AActivity/\d{4}/Activity_\d{8}_[A-Za-z0-9,._-]+_\h{32}\.fit\z}

  { full: DemoSeed::Manifests::FULL, minimal: DemoSeed::Manifests::MINIMAL }.each do |name, manifest|
    describe "the #{name} manifest" do
      let(:accounts) { manifest.fetch(:accounts) }
      let(:usernames) { accounts.map { |account| account.fetch(:username) } }
      let(:workout_keys) { accounts.to_h { |account| [ account.fetch(:username), account.fetch(:workouts, []).map { |entry| entry.fetch(:key) } + batch_keys(account) + manual_keys(account) ] } }
      let(:segment_keys) { accounts.to_h { |account| [ account.fetch(:username), account.fetch(:segments, []).map { |entry| entry.fetch(:key) } ] } }

      def batch_keys(account)
        account.fetch(:batches, []).flat_map { |batch| batch.fetch(:files).filter_map { |file| file[:key] } }
      end

      def manual_keys(account) = account.fetch(:manual_workouts, []).map { |entry| entry.fetch(:key) }

      it "names distinct, valid accounts" do
        expect(usernames).to eq(usernames.uniq)
        usernames.each do |username|
          expect(username).to match(User::USERNAME_FORMAT)
          expect(User::RESERVED_USERNAMES).not_to include(username)
        end
        emails = accounts.map { |account| account.fetch(:email) }
        expect(emails).to eq(emails.uniq)
        accounts.each do |account|
          expect(User::LOCALES).to include(account.fetch(:locale, "fr"))
          expect(User::THEMES).to include(account.fetch(:theme, "light"))
          expect(User::UNIT_SYSTEMS).to include(account.fetch(:unit_system, "metric"))
          expect(User::TIME_ZONE_IDENTIFIERS).to include(account.fetch(:time_zone, "Europe/Paris"))
          expect(account.fetch(:weather_enrichment_enabled, false)).to be_in([ true, false ])
          expect(User::PROFILE_SHARING_AUDIENCES).to include(account.fetch(:profile_statistics_audience, "none"))
          expect(User::PROFILE_SHARING_AUDIENCES).to include(account.fetch(:profile_records_audience, "none"))
          expect(User::DISCOVERABILITY).to include(account.fetch(:discoverable, "none"))
          account.fetch(:default_sports, {}).each do |generic, slug|
            expect(Sport::DEFAULT_TARGET_SLUGS.fetch(generic.to_s)).to include(slug)
          end
        end
      end

      it "keeps workout keys and titles unique per account and every recording on one account" do
        accounts.each do |account|
          keys = workout_keys.fetch(account.fetch(:username))
          expect(keys).to eq(keys.uniq)
          titles = (account.fetch(:workouts, []) + account.fetch(:manual_workouts, [])).map { |entry| entry.fetch(:title) }
          expect(titles).to eq(titles.uniq)
        end
        files = accounts.flat_map do |account|
          account.fetch(:workouts, []).filter_map { |entry| entry[:file] } +
            account.fetch(:batches, []).flat_map { |batch| batch.fetch(:files).filter_map { |file| file[:file] } }
        end
        expect(files).to eq(files.uniq)
        files.each { |file| expect(file).to match(DEMO_CORPUS_PATH) }
      end

      it "references catalog sports, owned equipment, known profiles and fixtures" do
        accounts.each do |account|
          labels = account.fetch(:equipment, []).map { |entry| entry.fetch(:label) }
          expect(labels).to eq(labels.uniq)
          account.fetch(:equipment, []).each { |entry| expect(EquipmentType.exists?(slug: entry.fetch(:type))).to be(true) }
          profiles = account.fetch(:profiles, []).map { |entry| entry.fetch(:name) }
          account.fetch(:workouts, []).each do |entry|
            Array(entry[:equipment]).each { |label| expect(labels).to include(label) }
            expect(Sport.exists?(slug: entry[:sport])).to be(true) if entry[:sport]
            expect(Rails.root.join("spec/fixtures", entry[:fixture])).to be_file if entry[:fixture]
            publish_requests(entry[:publish]).each do |request|
              if request[:profile]
                expect(profiles).to include(request[:profile])
              else
                expect(PublishingProfile::AUDIENCES).to include(request.fetch(:audience).to_s)
              end
              expect(PublishingProfile::PUBLISH_DELAYS).to have_key(request[:delay]) if request[:delay]
            end
          end
          account.fetch(:manual_workouts, []).each do |entry|
            Array(entry[:equipment]).each { |label| expect(labels).to include(label) }
            expect(Sport.exists?(slug: entry.fetch(:sport))).to be(true)
            expect(Time.iso8601("#{entry.fetch(:started_at)}:00Z")).to be < Time.current
            expect(entry.keys - %i[key sport title started_at description notes equipment commute] -
                   DemoSeed::Runner::MANUAL_FIGURES).to be_empty
          end
          account.fetch(:batches, []).each do |batch|
            expect(Sport.exists?(slug: batch.fetch(:sport))).to be(true)
            batch.fetch(:files).each do |file|
              expect(file[:file].present? || file[:fixture].present?).to be(true)
              expect(Rails.root.join("spec/fixtures", file[:fixture])).to be_file if file[:fixture]
            end
          end
        end
      end

      def publish_requests(publish)
        list = publish.is_a?(Array) ? publish : [ publish ].compact
        list.map { |request| request.is_a?(Hash) ? request : { audience: request } }
      end

      it "anchors every segment on an owned workout" do
        accounts.each do |account|
          username = account.fetch(:username)
          keys = account.fetch(:segments, []).map { |entry| entry.fetch(:key) }
          expect(keys).to eq(keys.uniq)
          account.fetch(:segments, []).each do |entry|
            expect(workout_keys.fetch(username)).to include(entry.fetch(:workout))
            expect(Segment::KINDS).to include(entry.fetch(:kind, "segment"))
            expect(Allure::VisibilityLevel::LEVELS).to include(entry.fetch(:visibility, "private"))
            expect(Sport.exists?(slug: entry[:sport])).to be(true) if entry[:sport]
            expect(entry[:tolerance]).to be_between(5, 100) if entry[:tolerance]
            if entry.fetch(:kind, "segment") == "segment"
              expect(entry[:start]).to be_present
              expect(entry[:end]).to be_present
              [ entry[:start], entry[:end] ].each do |latitude, longitude|
                expect(latitude).to be_between(-90, 90)
                expect(longitude).to be_between(-180, 180)
              end
            else
              expect(entry.fetch(:visibility, "private")).to eq("private")
            end
          end
        end
      end

      it "resolves every social reference" do
        manifest.fetch(:follows, []).each do |entry|
          expect(usernames).to include(entry.fetch(:from), entry.fetch(:to))
          expect(entry.fetch(:from)).not_to eq(entry.fetch(:to))
          expect(%w[accept reject pending]).to include(entry.fetch(:decision, "accept"))
        end
        manifest.fetch(:participations, []).each do |entry|
          expect(workout_keys.fetch(entry.fetch(:owner))).to include(entry.fetch(:workout))
          expect(usernames).to include(entry.fetch(:participant))
          expect(workout_keys.fetch(entry.fetch(:participant))).to include(entry[:with_workout]) if entry[:with_workout]
          expect(Participations::Decide::DECISIONS).to include(entry[:decision]) if entry[:decision]
        end
        seen = []
        manifest.fetch(:comments, []).each do |entry|
          expect(usernames).to include(entry.fetch(:author))
          expect(workout_keys.fetch(entry.fetch(:owner))).to include(entry.fetch(:workout))
          expect(entry.fetch(:body).length).to be_between(1, Comment::MAX_BODY_LENGTH)
          expect(seen).to include(entry[:parent]) if entry[:parent]
          expect(%i[deleted removed]).to include(entry[:state]) if entry[:state]
          seen << entry[:key] if entry[:key]
        end
        manifest.fetch(:closed_threads, []).each { |entry| expect(workout_keys.fetch(entry.fetch(:owner))).to include(entry.fetch(:workout)) }
        manifest.fetch(:reactions, []).each do |entry|
          expect(usernames).to include(entry.fetch(:by))
          expect(workout_keys.fetch(entry.fetch(:owner))).to include(entry.fetch(:workout))
          expect(Reaction::KINDS).to include(entry.fetch(:kind))
          expect(entry.fetch(:by)).not_to eq(entry.fetch(:owner))
        end
        (manifest.fetch(:opt_outs, []) + manifest.fetch(:copies, [])).each do |entry|
          expect(usernames).to include(entry.fetch(:user))
          expect(segment_keys.fetch(entry.fetch(:owner))).to include(entry.fetch(:segment))
        end
        manifest.fetch(:api, []).each do |entry|
          expect(usernames).to include(entry.fetch(:user))
          entry.fetch(:tokens, []).each do |token|
            expect(token.fetch(:scopes) - ApiToken::SCOPES).to be_empty
            expect(ApiToken::MCP_GEOMETRY_LEVELS).to include(token.fetch(:mcp_geometry, "none"))
          end
          entry.fetch(:webhooks, []).each { |webhook| expect(webhook.fetch(:url)).to start_with("https://") }
        end
        admin = manifest.fetch(:admin, {})
        expect(usernames).to include(admin[:operator]) if admin[:operator]
        admin.fetch(:suspended, []).each { |entry| expect(usernames).to include(entry.fetch(:username)) }
        admin.fetch(:identities, []).each do |entry|
          expect(usernames).to include(entry.fetch(:username))
          expect(Identity::PROVIDERS).to include(entry.fetch(:provider))
        end
      end

      it "points at files of the fetched corpus" do
        skip "run script/fetch-fit-corpus to check the corpus paths" unless DEMO_CORPUS_ROOT.join("Activity").directory?

        accounts.each do |account|
          account.fetch(:workouts, []).each { |entry| expect(DEMO_CORPUS_ROOT.join(entry[:file])).to be_file if entry[:file] }
          account.fetch(:batches, []).each do |batch|
            batch.fetch(:files).each { |file| expect(DEMO_CORPUS_ROOT.join(file[:file])).to be_file if file[:file] }
          end
        end
      end
    end
  end

  # The demo instance re-dates the dataset from these anchors (PLAN_DEMO.md §4):
  # each anchor must stay the newest date of its family, so the demo's most
  # recent activity lands near the present. The corpus filenames embed the
  # recording date, which keeps the check pure string work.
  describe "the full manifest's date anchors" do
    it "match the newest recording of each family" do
      manifest = DemoSeed::Manifests::FULL
      files = manifest.fetch(:accounts).flat_map do |account|
        account.fetch(:workouts, []).filter_map { |entry| entry[:file] } +
          account.fetch(:batches, []).flat_map { |batch| batch.fetch(:files).filter_map { |file| file[:file] } }
      end
      newest_file = files.map { |file| Date.parse(File.basename(file)[/Activity_(\d{8})/, 1]) }.max
      newest_manual = manifest.fetch(:accounts).flat_map do |account|
        account.fetch(:manual_workouts, []).map { |entry| Date.parse(entry.fetch(:started_at)) }
      end.max

      expect(DemoSeed::Manifests::DATE_ANCHORS).to eq(files: newest_file, manual: newest_manual)
    end
  end

  # The minimal dataset seeds its GPX fixtures when the corpus is missing, so
  # its files anchor is the newest date of either source.
  describe "the minimal manifest's date anchors" do
    it "match the newest recording of each family, fixtures included" do
      manifest = DemoSeed::Manifests::MINIMAL
      entries = manifest.fetch(:accounts).flat_map { |account| account.fetch(:workouts, []) }
      file_dates = entries.filter_map { |entry| entry[:file] && Date.parse(File.basename(entry[:file])[/Activity_(\d{8})/, 1]) }
      fixture_dates = entries.filter_map do |entry|
        next unless entry[:fixture]

        Rails.root.join("spec/fixtures", entry[:fixture]).read.scan(%r{<time>([^<]+)</time>}).flatten.map { |time| Time.iso8601(time).utc.to_date }.max
      end
      newest_manual = manifest.fetch(:accounts).flat_map do |account|
        account.fetch(:manual_workouts, []).map { |entry| Date.parse(entry.fetch(:started_at)) }
      end.max

      expect(DemoSeed::Manifests::MINIMAL_DATE_ANCHORS).to eq(files: (file_dates + fixture_dates).max, manual: newest_manual)
    end
  end

  it "names every dataset DEMO_DATASET accepts" do
    expect(DemoSeed::Datasets.fetch("full").anchors).to eq(DemoSeed::Manifests::DATE_ANCHORS)
    expect(DemoSeed::Datasets.fetch(" Minimal ").manifest).to eq(DemoSeed::Manifests::MINIMAL)
    expect { DemoSeed::Datasets.fetch("huge") }.to raise_error(ArgumentError, /unknown DEMO_DATASET/)
  end

  # Dockerfile.demo bakes exactly these into the demo image: a file the list
  # misses would fail the seed on the public demo, never in development.
  describe "the demo image's seed inputs" do
    it "lists exactly the corpus files the manifests name" do
      listed = DemoSeed::CorpusFiles::LIST.readlines(chomp: true)

      expect(listed).to eq(DemoSeed::CorpusFiles.from_manifests), "run bin/rails demo:corpus_files"
      # Plain relative paths only: the list becomes git sparse-checkout patterns.
      expect(listed).to all(match(DEMO_CORPUS_PATH))
    end

    it "keeps every fixture under the directory the image copies" do
      expect(DemoSeed::CorpusFiles.from_manifests(:fixture)).to all(start_with("gpx/"))
      expect(Rails.root.join("Dockerfile.demo").read).to include("COPY --chown=rails:rails spec/fixtures/gpx /rails/spec/fixtures/gpx")
    end
  end

  it "keeps the API token secret in the accepted shape" do
    expect(DemoSeed::API_TOKEN_SECRET).to match(ApiToken::SECRET_PATTERN)
  end
end

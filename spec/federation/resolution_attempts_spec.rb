# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Safety::ResolutionAttempts do
  let(:now) { Time.utc(2026, 8, 26, 12, 0, 10) }

  around do |example|
    described_class.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    described_class.store = nil
  end

  it "allows an authority below its limit and refuses the next attempt until the window ends" do
    described_class::PER_AUTHORITY.times { described_class.check!("https://remote.example/users/demo", now:) }

    expect { described_class.check!("https://remote.example/users/demo", now:) }
      .to raise_error(described_class::Exceeded) { |error| expect(error.retry_after).to eq(50) }
    expect { described_class.check!("https://remote.example/users/demo", now: now + 1.minute) }.not_to raise_error
  end

  it "meters wildcard subdomains together on their site" do
    described_class::PER_SITE.times { |index| described_class.check!("https://a#{index}.attacker.example/users/x", now:) }

    expect { described_class.check!("https://fresh.attacker.example/users/x", now:) }
      .to raise_error(described_class::Exceeded)
    expect { described_class.check!("https://other.example/users/x", now:) }.not_to raise_error
  end

  it "asks for a retry while an actor's last fetch failed recently" do
    described_class.record_failure("https://remote.example/users/demo")

    expect { described_class.check!("https://remote.example/users/demo", now:) }
      .to raise_error(described_class::RecentlyFailed)
    expect(described_class::RecentlyFailed).to be < Federation::ActorResolver::Unavailable
    expect { described_class.check!("https://remote.example/users/other", now:) }.not_to raise_error
  end
end

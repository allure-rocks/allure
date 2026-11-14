# frozen_string_literal: true

# The provider contract (PLAN_FUNDING.md §5), pinned for every automated
# adapter. Include it from a spec whose `described_class` is the adapter
# class; `env:` holds that provider's complete test configuration.
RSpec.shared_examples "a funding provider" do |env: {}|
  around do |example|
    previous = env.keys.to_h { |key| [ key, ENV[key] ] }
    env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "exposes a stable slug and the full provider contract" do
    expect(described_class.slug).to match(/\A[a-z0-9_]+\z/)
    expect(described_class.slug).not_to eq("manual")
    %i[checkout_url verify! portal_url portal_origin reconcile].each do |member|
      expect(described_class).to respond_to(member)
    end
    expect(described_class.portal_origin).to match(/\Ahttps:\/\/[a-z0-9.-]+\z/)
  end

  it "enables itself only from complete, well-formed environment variables" do
    env.each { |key, _value| expect(ENV[key]).to be_present }
    expect(described_class).to be_enabled
  end
end

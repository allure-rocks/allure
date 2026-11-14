# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Transport::SsrfGuard do
  Address = Struct.new(:ip_address)

  let(:https_config) { Allure::Federation::Config.new(base_url: "https://allure.example", protocol: "https", allow_private_ips: false) }
  let(:http_config) { Allure::Federation::Config.new(base_url: "http://allure.test:3000", protocol: "http", allow_private_ips: true) }

  def guard(config:, addresses: [ "93.184.216.34" ])
    described_class.new(config:, resolver: ->(_host, _port) { addresses.map { Address.new(_1) } })
  end

  it "accepts HTTPS hosts resolving to public addresses" do
    resolved = guard(config: https_config).validate!("https://remote.example/users/demo")

    expect(resolved.uri.to_s).to eq("https://remote.example/users/demo")
    expect(resolved.addresses.map(&:to_s)).to eq([ "93.184.216.34" ])
  end

  it "rejects every resolved private or special address" do
    %w[127.0.0.1 10.0.0.1 169.254.1.1 100.64.0.1 192.0.2.1 224.0.0.1 ::1 fd00::1 fe80::1 ff02::1 ::ffff:127.0.0.1 ::ffff:0.0.0.0 ::ffff:100.64.0.1 ::ffff:192.0.2.1 ::ffff:198.18.0.1 ::ffff:224.0.0.1 ::ffff:240.0.0.1 ::127.0.0.1].each do |address|
      expect {
        guard(config: https_config, addresses: [ address ]).validate!("https://remote.example/users/demo")
      }.to raise_error(described_class::UnsafeUri)
    end
  end

  # The dialed address is IPv4 even though it was written in IPv6 form; the
  # guard must compare it against the IPv4 blocklist after normalization.
  it "accepts an IPv4-mapped public address" do
    resolved = guard(config: https_config, addresses: [ "::ffff:93.184.216.34" ]).validate!("https://remote.example/users/demo")

    expect(resolved.addresses.map(&:to_s)).to eq([ "::ffff:93.184.216.34" ])
  end

  # NAT64 and 6to4 addresses carry an IPv4 destination the dialed IPv6 address
  # does not reveal, so an attacker-controlled AAAA record can tunnel to the
  # private IPv4 space the guard exists to protect.
  it "rejects NAT64 and 6to4 addresses embedding a private IPv4 destination" do
    [
      "64:ff9b::7f00:1",     # NAT64 of 127.0.0.1
      "64:ff9b::a9fe:a9fe",  # NAT64 of 169.254.169.254
      "64:ff9b::c0a8:101",   # NAT64 of 192.168.1.1
      "64:ff9b:1::7f00:1",   # local-use NAT64 of 127.0.0.1
      "2002:7f00:1::",       # 6to4 of 127.0.0.1
      "2002:a9fe:a9fe::",    # 6to4 of 169.254.169.254
      "2002:c0a8:101::"      # 6to4 of 192.168.1.1
    ].each do |address|
      expect {
        guard(config: https_config, addresses: [ address ]).validate!("https://remote.example/users/demo")
      }.to raise_error(described_class::UnsafeUri)
    end
  end

  # DNS64 on an IPv6-only instance synthesizes a NAT64 address for IPv4-only
  # peers, so a public embedded destination must stay reachable.
  it "accepts NAT64 and 6to4 addresses embedding a public IPv4 destination" do
    [
      "64:ff9b::5db8:d822", # NAT64 of 93.184.216.34
      "2002:5db8:d822::"    # 6to4 of 93.184.216.34
    ].each do |address|
      resolved = guard(config: https_config, addresses: [ address ]).validate!("https://remote.example/users/demo")

      expect(resolved.addresses.map(&:to_s)).to eq([ address ])
    end
  end

  it "rejects unsafe URI forms and schemes" do
    [
      "http://remote.example/users/demo",
      "https://user:password@remote.example/users/demo",
      "https://remote.example/users/demo#fragment",
      "https://remote.example:25/users/demo"
    ].each do |url|
      expect { guard(config: https_config).validate!(url) }.to raise_error(described_class::UnsafeUri)
    end
  end

  it "allows plain HTTP only for the private local ring" do
    expect(guard(config: http_config, addresses: [ "127.0.0.1" ]).validate!("http://rails:3000/users/demo")).to be_a(described_class::ResolvedUri)
  end

  it "rejects hosts that resolve to no address" do
    expect {
      guard(config: https_config, addresses: []).validate!("https://remote.example/users/demo")
    }.to raise_error(described_class::UnsafeUri)
  end

  it "gives up on a resolver that stalls" do
    stub_const("#{described_class}::RESOLVE_TIMEOUT", 0.05)
    stalled = described_class.new(config: https_config, resolver: ->(_host, _port) { sleep 2 })
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect { stalled.validate!("https://remote.example/users/demo") }
      .to raise_error(described_class::UnsafeUri, /could not be resolved/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
  end
end

RSpec.describe Federation::Transport::Client do
  let(:config) { Allure::Federation::Config.new(base_url: "https://allure.example", protocol: "https", allow_private_ips: false) }
  let(:resolved) { Federation::Transport::SsrfGuard::ResolvedUri.new(URI("https://remote.example/actor"), [ IPAddr.new("93.184.216.34") ]) }
  let(:guard) { instance_double(Federation::Transport::SsrfGuard) }

  before do
    allow(guard).to receive(:validate!).and_return(
      resolved,
      Federation::Transport::SsrfGuard::ResolvedUri.new(URI("https://remote.example/actor-2"), [ IPAddr.new("93.184.216.34") ])
    )
  end

  it "revalidates and follows bounded redirects" do
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "/actor-2" })
    stub_request(:get, "https://remote.example/actor-2").to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/activity+json" })

    response = described_class.new(config:, guard:).get("https://remote.example/actor")

    expect(response.status).to eq(200)
    expect(response.body).to eq("{}")
    expect(guard).to have_received(:validate!).twice
  end

  it "rejects HTTPS downgrade redirects" do
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "http://remote.example/actor" })

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor")
    }.to raise_error(Federation::Transport::Client::UnsafeRedirect)
  end

  it "revalidates the address behind every redirect" do
    calls = 0
    allow(guard).to receive(:validate!) do
      calls += 1
      raise Federation::Transport::SsrfGuard::UnsafeUri if calls == 2

      resolved
    end
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "/private" })

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor")
    }.to raise_error(Federation::Transport::SsrfGuard::UnsafeUri)
    expect(a_request(:get, "https://remote.example/private")).not_to have_been_made
  end

  it "limits response bodies before callers can parse them" do
    stub_request(:get, "https://remote.example/actor").to_return(status: 200, body: "x" * (described_class::MAX_RESPONSE_BYTES + 1))

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor")
    }.to raise_error(described_class::ResponseTooLarge)
  end

  it "honors a caller-supplied byte cap without changing the default" do
    stub_request(:get, "https://remote.example/actor").to_return(status: 200, body: "x" * 20)

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor", max_bytes: 10)
    }.to raise_error(described_class::ResponseTooLarge)
  end

  it "honors a caller-supplied redirect cap" do
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "/actor-2" })

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor", max_redirects: 0)
    }.to raise_error(described_class::TooManyRedirects)
  end

  # One deadline for the whole chain: the address resolution of the second
  # hop spends what the first hop left, instead of starting a fresh timeout.
  it "shares one deadline across every hop and address resolution" do
    calls = 0
    allow(guard).to receive(:validate!) do
      calls += 1
      sleep 2 if calls == 2
      resolved
    end
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "/actor-2" })
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor", total_timeout: 0.2)
    }.to raise_error(described_class::ResponseTimeout)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
  end

  it "refuses another hop once the deadline is spent" do
    allow(guard).to receive(:validate!) do
      sleep 0.15
      resolved
    end
    stub_request(:get, "https://remote.example/actor").to_return(status: 302, headers: { "Location" => "/actor" })

    expect {
      described_class.new(config:, guard:).get("https://remote.example/actor", total_timeout: 0.25)
    }.to raise_error(described_class::ResponseTimeout)
    expect(guard).to have_received(:validate!).at_most(2).times
  end
end

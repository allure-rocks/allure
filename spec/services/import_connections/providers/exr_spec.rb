# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Providers::Exr do
  subject(:provider) { described_class.new(connection) }

  let(:base) { "https://account.exrgame.com" }
  let(:connection) do
    create(:import_connection, :linked, provider: "exr", external_account_id: nil, external_account_name: "rower@example.test",
                                        token_expires_at: Time.utc(2031, 10, 8),
                                        credentials: { "remember_cookie_name" => "remember_web_abc", "remember_cookie" => "R1" })
  end
  let(:uuid) { "00000000-0000-4000-8000-000000000001" }
  let(:list_html) { Rails.root.join("spec/fixtures/exr/sessions_page.html").read }
  let(:fit) { "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b + ("\x00".b * 20) }
  let(:listed_activity) { remote_activity(uuid, started_at: Time.utc(2026, 9, 30, 17, 51, 15)) }

  before do
    stub_const("Allure::Exr::Http::MIN_INTERVAL", 0)
    stub_request(:get, "#{base}/sessions").with(headers: { "Cookie" => "remember_web_abc=R1" }).to_return(body: list_html)
    stub_request(:get, "#{base}/sessions/2").to_return(body: %(<table class="tableSessions"><tbody></tbody></table>))
    stub_request(:get, "#{base}/sessions/download/fit/#{uuid}").to_return(body: fit)
  end

  it_behaves_like "an import provider"

  it "lists the window's sessions with their UTC start, a geometry to find out, and no sport hint" do
    activities = provider.list(from: Time.utc(2026, 9, 18), to: Time.utc(2026, 9, 30, 23))

    expect(activities.map(&:external_id)).to eq([ uuid, "00000000-0000-4000-8000-000000000002",
                                                  "00000000-0000-4000-8000-000000000003" ])
    expect(activities.first).to have_attributes(name: "Regeneration Training 2 in Along Alamitos, Long Beach",
                                                started_at: Time.utc(2026, 9, 30, 17, 51, 15), sport_hint: nil,
                                                geometry: true)
  end

  it "fetches the FIT file under the session's title" do
    fetched = provider.fetch(listed_activity)

    expect(fetched).to have_attributes(filename: "exr-#{uuid}.fit", title: listed_activity.name)
    expect(fetched.io.read.bytesize).to eq(fit.bytesize)
  end

  it "persists a cookie the site replaces" do
    stub_request(:get, "#{base}/sessions")
      .to_return(body: list_html, headers: { "Set-Cookie" => "remember_web_abc=R2; Max-Age=86400; path=/" })

    provider.verify!

    expect(connection.reload.credential(:remember_cookie)).to eq("R2")
    expect(connection.token_expires_at).to be_within(1.minute).of(1.day.from_now)
  end

  it "turns a landing on the sign-in page into an authentication error" do
    stub_request(:get, "#{base}/sessions").to_return(status: 302, headers: { "Location" => "#{base}/login" })

    expect { provider.list(from: 1.day.ago, to: Time.current) }.to raise_error(Allure::RemoteImports::Error::AuthError)
  end

  it "has no equipment" do
    expect(provider.equipment).to eq([])
  end
end

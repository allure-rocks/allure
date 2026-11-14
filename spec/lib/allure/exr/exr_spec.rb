# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Allure::Exr" do
  let(:base) { "https://account.exrgame.com" }
  let(:list_html) { Rails.root.join("spec/fixtures/exr/sessions_page.html").read }
  let(:remember) { Allure::Exr::Http::Cookie.new(name: "remember_web_abc123", value: "R1", expires_at: Time.utc(2027, 11, 13)) }
  let(:http) { Allure::Exr::Http.new(cookies: [ remember ], min_interval: 0) }
  let(:login_html) do
    <<~HTML
      <form id="form" method="post" action="https://account.exrgame.com/login">
        <input type="hidden" name="_token" value="csrf-1">
        <input type="email" name="mail"><input type="password" name="password">
      </form>
    HTML
  end

  def page_html(rows:, next_page: nil)
    trs = rows.map do |uuid, datetime|
      %(<tr><td><input class="checkSingle" value="#{uuid}"></td><td><time datetime="#{datetime}">x</time></td>) +
        %(<td><label title="EXR | Row">EXR | Row</label></td><td>1&nbsp;km</td><td><time>00:05:00</time></td></tr>)
    end
    pagination = next_page ? %(<ul class="pagination"><li class="paginationNext"><a href="#{base}/sessions/#{next_page}">n</a></li></ul>) : ""
    %(<table class="tableSessions"><tbody>#{trs.join}</tbody></table>#{pagination})
  end

  def uuid(number) = format("00000000-0000-4000-8000-%012d", number)

  describe Allure::Exr::SessionsPage do
    subject(:page) { described_class.parse(list_html) }

    it "reads every row from attributes and numbers" do
      expect(page.rows.size).to eq(3)
      expect(page.rows.first).to have_attributes(
        uuid: uuid(1), listed_at: Time.utc(2026, 9, 30, 17, 51, 15),
        title: "Regeneration Training 2 in Along Alamitos, Long Beach", distance_m: 6000.0, duration_s: 1735
      )
      expect(page.rows.second).to have_attributes(distance_m: 530.0, duration_s: 120)
    end

    it "reads the pagination" do
      expect(page).to have_attributes(next_page: 2, last_page: 11, signed_out?: false)
    end

    it "recognises the sign-in form" do
      expect(described_class.parse(login_html)).to have_attributes(signed_out?: true, rows: [])
    end
  end

  describe Allure::Exr::Session do
    before do
      stub_request(:get, "#{base}/login")
        .to_return(status: 200, body: login_html, headers: { "Set-Cookie" => "exr_session=s0; path=/; httponly" })
    end

    it "signs in without the remember checkbox and returns the remember cookie" do
      post = stub_request(:post, "#{base}/login")
        .with(body: { "_token" => "csrf-1", "mail" => "rower@example.test", "password" => "secret" },
              headers: { "Cookie" => "exr_session=s0" })
        .to_return(status: 302, headers: {
          "Location" => "#{base}/dashboard",
          "Set-Cookie" => [ "exr_session=s1; path=/",
                            "remember_web_abc123=R1; expires=Sat, 13-Nov-2027 20:33:03 GMT; Max-Age=34560000; path=/" ]
        })

      cookie = described_class.new(http: Allure::Exr::Http.new(min_interval: 0)).sign_in(email: "rower@example.test", password: "secret")

      expect(post).to have_been_requested
      expect(cookie).to have_attributes(name: "remember_web_abc123", value: "R1")
      expect(cookie.expires_at).to be > 300.days.from_now
    end

    it "reports refused credentials" do
      stub_request(:post, "#{base}/login").to_return(status: 302, headers: { "Location" => "#{base}/login" })

      expect { described_class.new(http: Allure::Exr::Http.new(min_interval: 0)).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Exr::Error::InvalidCredentials)
    end

    it "refuses a sign-in that sets no remember cookie" do
      stub_request(:post, "#{base}/login").to_return(status: 302, headers: { "Location" => "#{base}/dashboard" })

      expect { described_class.new(http: Allure::Exr::Http.new(min_interval: 0)).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Exr::Error::NoRememberCookie)
    end
  end

  describe Allure::Exr::Client do
    subject(:client) { described_class.new(remember:, http:, on_rotate: rotations.method(:<<)) }

    let(:rotations) { [] }

    it "sends only the remember cookie and reads the list" do
      stub_request(:get, "#{base}/sessions").with(headers: { "Cookie" => "remember_web_abc123=R1" })
        .to_return(status: 200, body: list_html)

      expect(client.page.rows.map(&:uuid)).to eq([ uuid(1), uuid(2), uuid(3) ])
    end

    it "pages until the rows are older than the range" do
      stub_request(:get, "#{base}/sessions").to_return(body: page_html(rows: [ [ uuid(1), "2026-10-05 10:00:00" ] ], next_page: 2))
      stub_request(:get, "#{base}/sessions/2").to_return(body: page_html(rows: [ [ uuid(2), "2026-09-28 10:00:00" ],
                                                                                 [ uuid(3), "2026-09-20 10:00:00" ] ], next_page: 3))
      third = stub_request(:get, "#{base}/sessions/3")

      rows = client.list(from: Date.new(2026, 9, 25), to: Date.new(2026, 10, 1))

      expect(rows.map(&:uuid)).to eq([ uuid(2) ])
      expect(third).not_to have_been_requested
    end

    it "follows the site's own redirects but never leaves it" do
      stub_request(:get, "#{base}/sessions").to_return(status: 301, headers: { "Location" => "#{base}/sessions?locale=en" })
      stub_request(:get, "#{base}/sessions?locale=en").to_return(body: list_html)
      stub_request(:get, "#{base}/sessions/2").to_return(status: 301, headers: { "Location" => "https://evil.test/sessions" })

      expect(client.page.rows.size).to eq(3)
      expect { client.page(2) }.to raise_error(Allure::Exr::Error::Unavailable)
    end

    it "says signed out when the site redirects to the sign-in page" do
      stub_request(:get, "#{base}/sessions").to_return(status: 302, headers: { "Location" => "#{base}/login" })

      expect { client.page }.to raise_error(Allure::Exr::Error::SignedOut)
    end

    it "hands a replaced remember cookie over" do
      stub_request(:get, "#{base}/sessions")
        .to_return(body: list_html, headers: { "Set-Cookie" => "remember_web_abc123=R2; Max-Age=34560000; path=/" })

      client.page

      expect(rotations.map(&:value)).to eq([ "R2" ])
      expect(client.remember.value).to eq("R2")
    end

    it "downloads a FIT file and refuses a page in its place" do
      fit = "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b + ("\x00".b * 20)
      stub_request(:get, "#{base}/sessions").to_return(body: list_html)
      stub_request(:get, "#{base}/sessions/download/fit/#{uuid(1)}").to_return(body: fit)
      stub_request(:get, "#{base}/sessions/download/fit/#{uuid(2)}").to_return(body: login_html)

      expect(client.download_fit(uuid(1), io: StringIO.new(+"", "w+b")).string.bytesize).to eq(fit.bytesize)
      expect { client.download_fit(uuid(2), io: StringIO.new(+"", "w+b")) }.to raise_error(Allure::Exr::Error::SignedOut)
    end

    it "opens a session before downloading and reuses its cookies for subsequent files" do
      listing = stub_request(:get, "#{base}/sessions")
        .with(headers: { "Cookie" => "remember_web_abc123=R1" })
        .to_return(body: list_html, headers: { "Set-Cookie" => [ "exr_session=S1; path=/",
                                                                             "remember_web_abc123=R2; path=/" ] })
      fit = "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b
      downloads = [ uuid(1), uuid(2) ].map do |id|
        stub_request(:get, "#{base}/sessions/download/fit/#{id}")
          .with(headers: { "Cookie" => "remember_web_abc123=R2; exr_session=S1" }).to_return(body: fit)
      end

      [ uuid(1), uuid(2) ].each { |id| client.download_fit(id, io: StringIO.new(+"", "w+b")) }

      expect(listing).to have_been_requested.once
      downloads.each { |download| expect(download).to have_been_requested.once }
      expect(rotations.map(&:value)).to eq([ "R2" ])
    end

    it "does not reopen a session already established by listing" do
      listing = stub_request(:get, "#{base}/sessions").to_return(body: list_html)
      fit = "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b
      stub_request(:get, "#{base}/sessions/download/fit/#{uuid(1)}").to_return(body: fit)

      client.page
      client.download_fit(uuid(1), io: StringIO.new(+"", "w+b"))

      expect(listing).to have_been_requested.once
    end

    it "does not download when session initialization fails and retries initialization on the next call" do
      listing = stub_request(:get, "#{base}/sessions")
        .to_return(status: 503).then.to_return(body: list_html)
      fit = "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b
      download = stub_request(:get, "#{base}/sessions/download/fit/#{uuid(1)}").to_return(body: fit)

      expect { client.download_fit(uuid(1), io: StringIO.new(+"", "w+b")) }.to raise_error(Allure::Exr::Error::Unavailable)
      expect(download).not_to have_been_requested

      client.download_fit(uuid(1), io: StringIO.new(+"", "w+b"))

      expect(listing).to have_been_requested.twice
      expect(download).to have_been_requested.once
    end
  end
end

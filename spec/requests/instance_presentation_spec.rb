# frozen_string_literal: true

require "rails_helper"

# The configured host identity surfaces in the footer (every page, visitors
# included) and in the PWA description. Nothing appears when it is unset.
RSpec.describe "Instance presentation" do
  before { sign_in_as(create(:user)) }

  def with_env(vars)
    previous = vars.transform_values { |_| nil }
    vars.each_key { |k| previous[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe "footer host line" do
    it "links the host name when a URL is configured" do
      with_env("INSTANCE_HOST_NAME" => "Camille", "INSTANCE_HOST_URL" => "https://example.org") do
        get feed_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("footer.hosted_by", name: "Camille"))
        expect(response.body).to include(%(href="https://example.org"))
      end
    end

    it "shows the host name without a link when no URL is configured" do
      with_env("INSTANCE_HOST_NAME" => "Camille", "INSTANCE_HOST_URL" => nil) do
        get feed_path

        expect(response.body).to include(I18n.t("footer.hosted_by", name: "Camille"))
        expect(response.body).not_to include(%(href="https://example.org"))
      end
    end

    it "hides the host line when nothing is configured" do
      with_env("INSTANCE_HOST_NAME" => nil, "INSTANCE_HOST_URL" => nil) do
        get feed_path

        expect(response.body).not_to include("Hébergé par")
      end
    end

    it "ignores an invalid host URL" do
      with_env("INSTANCE_HOST_NAME" => "Camille", "INSTANCE_HOST_URL" => "javascript:alert(1)") do
        get feed_path

        expect(response.body).to include(I18n.t("footer.hosted_by", name: "Camille"))
        expect(response.body).not_to include("javascript:")
      end
    end
  end

  describe "PWA manifest" do
    it "uses the configured description" do
      with_env("INSTANCE_DESCRIPTION" => "Une instance auto-hébergée.") do
        get pwa_manifest_path

        expect(JSON.parse(response.body).fetch("description")).to eq("Une instance auto-hébergée.")
      end
    end

    it "falls back to the footer tagline when no description is configured" do
      with_env("INSTANCE_DESCRIPTION" => nil) do
        get pwa_manifest_path

        expect(JSON.parse(response.body).fetch("description")).to eq(I18n.t("footer.tagline"))
      end
    end
  end
end

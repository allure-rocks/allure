# frozen_string_literal: true

# The Content-Security-Policy header (DESIGN.md §25, SECURITY.md-style second
# barrier): every script is the application's own, served from this origin,
# and the two self-submitting provider pages carry a per-request nonce. Styles
# keep 'unsafe-inline' for now — inline style attributes (progress widths,
# the weather icons' SVG) and the chart and map libraries write them — so a
# nonce is deliberately not added to style-src, where it would switch
# 'unsafe-inline' off. The map style's hosts, the enabled identity providers
# and CONTENT_SECURITY_POLICY_SOURCES are read per request, through
# Allure::ContentSecurityPolicy, since the initializer runs before the
# autoloader serves lib/.
Rails.application.configure do
  sources = ->(directive) { -> { Allure::ContentSecurityPolicy.sources(directive) } }

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob, sources.call(:img)
    policy.font_src :self, :data
    policy.connect_src :self, sources.call(:connect)
    policy.worker_src :self, :blob
    policy.frame_src :self
    policy.frame_ancestors :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self, sources.call(:form)
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end

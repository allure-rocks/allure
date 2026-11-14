# frozen_string_literal: true

# Webhook URLs pass the SSRF guard, which resolves their host. Specs resolve
# every host to one public address; a spec testing a refusal swaps it.
module WebhookHelpers
  PUBLIC_ADDRESS = "93.184.216.34"

  def resolve_webhook_hosts_to(address)
    Webhooks::Transport.resolver = ->(_host, _port) { [ address ] }
  end
end

RSpec.configure do |config|
  config.include WebhookHelpers
  config.before { Webhooks::Transport.resolver = ->(_host, _port) { [ WebhookHelpers::PUBLIC_ADDRESS ] } }
  config.after { Webhooks::Transport.resolver = nil }
end

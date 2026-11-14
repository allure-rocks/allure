# frozen_string_literal: true

# The development Compose file passes DEMO_INSTANCE through from .env, and a
# developer testing the demo mode has it on. The suite runs without demo mode
# by default — every demo-gated behaviour (the policy exception, the guards,
# the nil session IP, the strip) is asserted by the demo specs, which set the
# variable per example.
ENV.delete("DEMO_INSTANCE")

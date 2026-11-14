# frozen_string_literal: true

# Development Compose names the seeded `marie` as the operator, and the test
# container inherits that environment. Specs that need an operator set
# INSTANCE_OPERATOR_USERNAME themselves; every other spec runs without one, so
# an account that happens to be named marie owes no immediate second factor.
# The demo operator's password is likewise set only by the specs that need it.
ENV.delete("INSTANCE_OPERATOR_USERNAME")
ENV.delete("DEMO_OPERATOR_PASSWORD")

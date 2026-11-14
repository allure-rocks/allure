# frozen_string_literal: true

module AllureMcp
  # The request's principal, handed to every tool as its server context: the
  # token's account, the token itself (its location level), and the outcome
  # the tool reports for the metrics.
  Context = Struct.new(:user, :token, :outcome, keyword_init: true)
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # A REST API request authenticates with a token instead of a browser
  # session (docs/dev/API.md); it never has both.
  attribute :api_token

  def user = session ? session.user : api_token&.user
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # A REST API request authenticates with a token instead of a browser
  # session (PLAN_API.md §4.5); it never has both.
  attribute :api_token

  def user = session ? session.user : api_token&.user
end

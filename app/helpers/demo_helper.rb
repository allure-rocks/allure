# frozen_string_literal: true

# The demo mode's chrome (PLAN_DEMO.md §6): the site-wide reset strip and the
# sign-in page's credentials block.
module DemoHelper
  # The shared accounts in their configured order, for the sign-in page's
  # credentials block. A row missing (a half-built boot) is simply skipped.
  def demo_accounts
    rows = User.where(username: Allure::Demo.accounts).index_by(&:username)
    Allure::Demo.accounts.filter_map { |username| rows[username] }
  end

  # The shared password displayed on the sign-in page; unset hides the line.
  def demo_password
    ENV.fetch("DEMO_PASSWORD", "").presence
  end
end

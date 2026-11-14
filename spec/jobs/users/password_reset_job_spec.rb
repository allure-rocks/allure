# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::PasswordResetJob do
  it "delivers the reset mail for an existing address" do
    user = create(:user)

    expect { described_class.perform_now(user.email_address) }
      .to change { ActionMailer::Base.deliveries.count }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email_address ])
  end

  it "stays silent for an unknown address" do
    expect { described_class.perform_now("unknown@allure.test") }
      .not_to change { ActionMailer::Base.deliveries.count }
  end
end

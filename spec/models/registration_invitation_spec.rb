# frozen_string_literal: true

require "rails_helper"

RSpec.describe RegistrationInvitation do
  describe ".issue" do
    it "returns the raw token and stores only its digest" do
      invitation, raw_token = described_class.issue(email_address: " Invitee@Allure.Test ")

      expect(invitation).to be_persisted
      expect(raw_token).to be_present
      expect(invitation.email_address).to eq("invitee@allure.test")
      expect(invitation.token_digest).to eq(described_class.digest(raw_token))
      expect(invitation.token_digest).not_to eq(raw_token)
    end

    it "uses a seven-day validity by default" do
      invitation, = described_class.issue(email_address: "invitee@allure.test")

      expect(invitation.expires_at).to be_within(1.second).of(7.days.from_now)
    end

    it "stores a squished display name, blank as nil" do
      named, = described_class.issue(email_address: "a@allure.test", display_name: "  Jeanne   Martin ")
      blank, = described_class.issue(email_address: "b@allure.test", display_name: "   ")

      expect(named.display_name).to eq("Jeanne Martin")
      expect(blank.display_name).to be_nil
    end

    it "rejects a display name over 60 characters" do
      expect { described_class.issue(email_address: "a@allure.test", display_name: "x" * 61) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "accepts a custom validity" do
      invitation, = described_class.issue(email_address: "invitee@allure.test", expires_in: 2.days)

      expect(invitation.expires_at).to be_within(1.second).of(2.days.from_now)
    end
  end

  describe ".find_by_token" do
    it "finds an invitation from its raw token" do
      invitation, raw_token = described_class.issue(email_address: "invitee@allure.test")

      expect(described_class.find_by_token(raw_token)).to eq(invitation)
    end

    it "returns nil for a blank or tampered token" do
      described_class.issue(email_address: "invitee@allure.test")

      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token("")).to be_nil
      expect(described_class.find_by_token("not-a-real-token")).to be_nil
    end
  end

  describe "#usable?" do
    it "is true for a pending, unexpired invitation" do
      expect(build(:registration_invitation)).to be_usable
    end

    it "is false once accepted" do
      invitation = build(:registration_invitation, accepted_at: Time.current)

      expect(invitation).not_to be_usable
    end

    it "is false once expired" do
      invitation = build(:registration_invitation, expires_at: 1.minute.ago)

      expect(invitation).not_to be_usable
    end
  end

  describe "#accept!" do
    it "records the acceptance time" do
      invitation = create(:registration_invitation)

      expect { invitation.accept! }.to change { invitation.reload.accepted_at }.from(nil).to(be_present)
    end
  end
end

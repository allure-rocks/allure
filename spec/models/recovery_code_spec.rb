# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecoveryCode do
  let(:user) { create(:user) }

  it "generates ten readable codes and stores only their digests" do
    codes = described_class.generate_for!(user)

    expect(codes.size).to eq(10)
    expect(codes).to all(match(/\A[a-hj-km-np-z2-9]{5}-[a-hj-km-np-z2-9]{5}\z/))
    expect(user.recovery_codes.pluck(:code_digest)).not_to include(*codes)
  end

  it "accepts each code once, whatever its case and separators" do
    code = described_class.generate_for!(user).first

    expect(described_class.consume(user, " #{code.upcase.delete('-')} ")).to be(true)
    expect(described_class.consume(user, code)).to be(false)
    expect(user.recovery_codes.unused.count).to eq(9)
  end

  it "replaces the previous set" do
    old = described_class.generate_for!(user).first
    described_class.generate_for!(user)

    expect(described_class.consume(user, old)).to be(false)
    expect(user.recovery_codes.count).to eq(10)
  end

  it "never accepts another account's code" do
    code = described_class.generate_for!(create(:user)).first

    expect(described_class.consume(user, code)).to be(false)
  end
end

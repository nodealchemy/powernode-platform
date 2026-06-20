# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::BootstrapToken do
  it "generates a token whose digest verifies, then clears" do
    raw = described_class.generate!

    expect(raw).to be_present
    expect(described_class.present?).to be(true)
    expect(described_class.verify(raw)).to be(true)
    expect(described_class.verify("wrong")).to be(false)

    described_class.clear!
    expect(described_class.present?).to be(false)
    expect(described_class.verify(raw)).to be(false)
  end

  it "rejects blank tokens" do
    described_class.generate!
    expect(described_class.verify(nil)).to be(false)
    expect(described_class.verify("")).to be(false)
  end

  it "stores only the digest, never the raw token" do
    raw = described_class.generate!
    stored = AdminSetting.get(described_class::SETTING_KEY)

    expect(stored).not_to eq(raw)
    expect(stored).to eq(Digest::SHA256.hexdigest(raw))
  end

  it "regenerating invalidates the previous token" do
    first = described_class.generate!
    second = described_class.generate!

    expect(first).not_to eq(second)
    expect(described_class.verify(first)).to be(false)
    expect(described_class.verify(second)).to be(true)
  end
end

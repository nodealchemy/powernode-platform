# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::FirstAdminService do
  describe ".call" do
    it "creates an account + super_admin user on a fresh install" do
      result = described_class.call(
        email: "root@powernode.internal", password: TestUsers::PASSWORD, name: "Root"
      )

      expect(result.user).to be_persisted
      expect(result.account).to be_persisted
      expect(result.user.super_admin?).to be(true)
      expect(result.user.has_permission?("system.admin")).to be(true)
      expect(result.user.email_verified_at).to be_present
    end

    it "raises AlreadyBootstrapped when a user already exists" do
      create(:user)

      expect do
        described_class.call(email: "x@powernode.internal", password: TestUsers::PASSWORD)
      end.to raise_error(described_class::AlreadyBootstrapped)
    end

    it "reuses an existing account rather than creating a second" do
      account = create(:account)

      result = described_class.call(email: "root@powernode.internal", password: TestUsers::PASSWORD)

      expect(result.account).to eq(account)
      expect(Account.count).to eq(1)
    end
  end
end

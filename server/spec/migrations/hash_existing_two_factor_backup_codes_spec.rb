# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260924010100_hash_existing_two_factor_backup_codes.rb")

# IMP-99e8e4701150 review M3 — the migration must be safe to run more than
# once (a re-run, or running against a row a live write already hashed)
# without double-hashing an already-bcrypt-digested value into something
# #verify_backup_code can never match again.
RSpec.describe HashExistingTwoFactorBackupCodes do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }

  def user_with_backup_codes(codes)
    user = create(:user, account: account)
    user.update_column(:backup_codes, codes)
    user
  end

  describe "#up" do
    it "does nothing for a nil backup_codes column" do
      user = user_with_backup_codes(nil)

      expect { migration.up }.not_to raise_error
      expect(user.reload.backup_codes).to be_nil
    end

    it "does nothing for an empty array" do
      user = user_with_backup_codes([])

      migration.up

      expect(user.reload.backup_codes).to eq([])
    end

    it "hashes plaintext codes in place, verifiable by the model afterward" do
      user = user_with_backup_codes(%w[AAAAAAAA BBBBBBBB])

      migration.up
      user.reload

      expect(user.backup_codes).to all(match(HashExistingTwoFactorBackupCodes::ALREADY_HASHED))
      expect(user.backup_codes & %w[AAAAAAAA BBBBBBBB]).to be_empty
      expect(user.verify_backup_code("AAAAAAAA")).to be true
      expect(user.reload.verify_backup_code("BBBBBBBB")).to be true
    end

    it "leaves an already-hashed code untouched (idempotent per-row)" do
      existing_digest = BCrypt::Password.create("CCCCCCCC", cost: 10).to_s
      user = user_with_backup_codes([ existing_digest ])

      migration.up

      expect(user.reload.backup_codes).to eq([ existing_digest ])
    end

    it "is safe to run twice: a second run does not re-hash the first run's digests" do
      user = user_with_backup_codes(%w[DDDDDDDD EEEEEEEE])

      migration.up
      first_pass_digests = user.reload.backup_codes

      migration.up
      second_pass_digests = user.reload.backup_codes

      expect(second_pass_digests).to eq(first_pass_digests)
      expect(user.verify_backup_code("DDDDDDDD")).to be true
    end

    it "hashes a mix of plaintext and already-hashed codes in the same row" do
      existing_digest = BCrypt::Password.create("FFFFFFFF", cost: 10).to_s
      user = user_with_backup_codes([ existing_digest, "GGGGGGGG" ])

      migration.up
      user.reload

      expect(user.backup_codes).to include(existing_digest)
      expect(user.backup_codes).not_to include("GGGGGGGG")
      expect(user.verify_backup_code("FFFFFFFF")).to be true
      expect(user.reload.verify_backup_code("GGGGGGGG")).to be true
    end
  end

  describe "#down" do
    it "is irreversible — the plaintext is gone the moment it's hashed" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end

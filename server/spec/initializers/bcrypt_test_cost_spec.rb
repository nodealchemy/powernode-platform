# frozen_string_literal: true

require "rails_helper"

# IMP-f2d294754787 — in the test env every bcrypt digest must be built at
# BCrypt::Engine::MIN_COST. has_secure_password already honors this through
# ActiveModel::SecurePassword.min_cost, but the many explicit
# BCrypt::Password.create(x) call sites (reset tokens, change_password,
# share passwords, federation tokens) read BCrypt::Engine.cost, which
# defaults to 12 unless config/initializers/bcrypt.rb lowers it.
RSpec.describe "bcrypt test-env cost" do
  it "sets BCrypt::Engine.cost to MIN_COST" do
    expect(BCrypt::Engine.cost).to eq(BCrypt::Engine::MIN_COST)
  end

  it "hashes a plain BCrypt::Password.create at MIN_COST" do
    expect(BCrypt::Password.create("a-test-secret").cost).to eq(BCrypt::Engine::MIN_COST)
  end

  it "hashes has_secure_password digests at MIN_COST" do
    user = build(:user, password: "TestPassw0rd!xyz", password_confirmation: "TestPassw0rd!xyz")
    expect(BCrypt::Password.new(user.password_digest).cost).to eq(BCrypt::Engine::MIN_COST)
  end

  # Backup codes use an explicit cost (BACKUP_CODE_BCRYPT_COST = 10, operator
  # choice IMP-99e8e4701150 M1); in test they must honor the lowered engine cost.
  it "hashes backup codes at MIN_COST in test" do
    digest = User.new.send(:hash_backup_codes, [ "deadbeef" ]).first
    expect(BCrypt::Password.new(digest).cost).to eq(BCrypt::Engine::MIN_COST)
  end

  it "keeps backup codes at cost 10 when the engine cost is the production 12" do
    allow(BCrypt::Engine).to receive(:cost).and_return(12)
    digest = User.new.send(:hash_backup_codes, [ "deadbeef" ]).first
    expect(BCrypt::Password.new(digest).cost).to eq(User::BACKUP_CODE_BCRYPT_COST)
    expect(User::BACKUP_CODE_BCRYPT_COST).to eq(10)
  end
end

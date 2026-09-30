# frozen_string_literal: true

require "rails_helper"

# IMP-06cf44531256 — an extension can reserve an Account#settings key against
# tenant-level writes. Account#settings is merged from a caller-supplied hash by
# every account-settings writer (PUT /api/v1/settings, the accounts controller),
# gated only on a tenant-level permission; a key whose meaning is a
# platform-operator decision (a privilege grant read by a platform-wide
# reader) must not be settable there. Core names no key: owners register.
RSpec.describe Account, "reserved settings keys" do
  let(:key) { "zz_reserved_probe" }
  let(:account) { create(:account) }

  before { described_class.register_reserved_setting_key(key, reason: "operator-only, use the protected site setting") }
  after { described_class.reserved_setting_keys.delete(key) }

  it "refuses to ADD the key through any writer" do
    expect(account.update(settings: account.settings.merge(key => "x"))).to be(false)
    expect(account.errors[:settings].join).to include(key).and include("operator-only")
    expect(account.reload.settings).not_to have_key(key)
  end

  it "refuses to CHANGE an existing value" do
    account.update_columns(settings: account.settings.merge(key => "old"))

    expect(account.reload.update(settings: account.settings.merge(key => "new"))).to be(false)
    expect(account.reload.settings[key]).to eq("old")
  end

  it "refuses when the key arrives as a symbol" do
    expect(account.update(settings: account.settings.merge(key.to_sym => "x"))).to be(false)
  end

  it "refuses through the account-settings service, naming the key" do
    user = create(:user, account: account, permissions: [ "admin.settings.update" ])
    result = SettingsUpdateService.new(user: user, account: account, params: { account_settings: { key => "x" } }).call

    expect(result[:success]).to be(false)
    expect(result.to_json).to include(key)
    expect(account.reload.settings).not_to have_key(key)
  end

  it "does NOT block unrelated edits to an account that already holds the key (pre-existing residue)" do
    account.update_columns(settings: account.settings.merge(key => "old"))

    expect(account.reload.update(settings: account.settings.merge("other" => 1))).to be(true)
    expect(account.reload.settings).to include(key => "old", "other" => 1)
  end

  it "allows REMOVING the key, which is how a migration clears it" do
    account.update_columns(settings: account.settings.merge(key => "old"))

    expect(account.reload.update(settings: account.settings.except(key))).to be(true)
  end

  it "leaves every other key writable" do
    expect(account.update(settings: account.settings.merge("plain" => "x"))).to be(true)
  end

  it "registers idempotently, keeping one reason per key" do
    described_class.register_reserved_setting_key(key, reason: "operator-only, use the protected site setting")

    expect(described_class.reserved_setting_keys.slice(key).size).to eq(1)
  end
end

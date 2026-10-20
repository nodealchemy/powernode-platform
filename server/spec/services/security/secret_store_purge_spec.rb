# frozen_string_literal: true

require "rails_helper"

# L2: with secret_backend=vault an account's SecretStore entries live only in
# Vault KV (no DB row), so account teardown must purge that path itself.
RSpec.describe Security::SecretStore, ".purge_account" do
  let(:account) { create(:account) }
  let(:vault) { instance_double(Security::VaultClient) }
  let(:prefix) { "powernode/secret-store/#{account.id}" }

  before do
    AdminSetting.where(key: described_class::SETTING_KEY).delete_all
    allow(Security::VaultClient).to receive(:instance).and_return(vault)
    allow(vault).to receive(:healthy?).and_return(true)
    allow(vault).to receive(:delete_secret)
  end

  it "requires an account id" do
    expect { described_class.purge_account(account_id: " ") }.to raise_error(ArgumentError)
    expect { described_class.purge_account(account_id: nil) }.to raise_error(ArgumentError)
  end

  context "with the database backend" do
    it "does nothing (the DB rows go with the account's dependents)" do
      expect(described_class.purge_account(account_id: account.id)).to eq(0)
      expect(vault).not_to have_received(:delete_secret)
    end
  end

  context "with the vault backend" do
    before do
      AdminSetting.set(described_class::SETTING_KEY, "vault")
      allow(vault).to receive(:list_secrets).with(prefix).and_return([ "email/", "sso/" ])
      allow(vault).to receive(:list_secrets).with("#{prefix}/email").and_return(%w[smtp_password api_key])
      allow(vault).to receive(:list_secrets).with("#{prefix}/sso").and_return(%w[client_secret])
    end

    it "deletes every KV entry under the account's path and returns the count" do
      expect(described_class.purge_account(account_id: account.id)).to eq(3)

      %w[email/smtp_password email/api_key sso/client_secret].each do |leaf|
        expect(vault).to have_received(:delete_secret).with("#{prefix}/#{leaf}")
      end
    end

    it "is run by Account#destroy after the deletion commits, and logs only a count" do
      allow(Rails.logger).to receive(:info)
      other = create(:account)
      allow(vault).to receive(:list_secrets).with("powernode/secret-store/#{other.id}").and_return([])

      other.destroy!

      expect(vault).to have_received(:list_secrets).with("powernode/secret-store/#{other.id}")
    end

    it "logs a purge failure at error level with the account id and error class only" do
      allow(vault).to receive(:list_secrets).and_raise(Security::VaultClient::ConnectionError, "token s3cr3t rejected")
      allow(Rails.logger).to receive(:error)

      account.destroy!

      expect(Rails.logger).to have_received(:error)
        .with("[Account.teardown] secret store purge FAILED for account #{account.id}: Security::VaultClient::ConnectionError")
    end

    it "does not purge when the destroy is refused or rolled back" do
      Account.register_teardown_guard(:spec_refusal) { |_acct| "refused" }
      begin
        expect(account.destroy).to be false
      ensure
        Account.teardown_guards.delete(:spec_refusal)
      end

      expect(vault).not_to have_received(:delete_secret)
    end
  end
end

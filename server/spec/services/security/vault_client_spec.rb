# frozen_string_literal: true

require "rails_helper"

# Characterizes the "Vault unconfigured" fail-safe path on Security::VaultClient.
# NEVER contacts a real Vault server — Vault-unconfigured (VAULT_ROLE_ID /
# VAULT_SECRET_ID absent, AdminSetting empty) is exactly how a Vault-less
# deployment (e.g. ops-hub, by design) runs; credential callers fall back to
# DB encryption in that mode and must never see a raised exception from these
# availability probes.
RSpec.describe Security::VaultClient do
  around do |example|
    described_class.reconfigure!
    example.run
    described_class.reconfigure!
  end

  # Forces the exact "unconfigured" condition #fetch_app_token checks: no
  # AdminSetting-persisted vault_role_id/vault_secret_id, no ENV fallback.
  def with_vault_unconfigured
    allow(described_class).to receive(:admin_setting_config).and_return({})
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VAULT_ROLE_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("VAULT_SECRET_ID").and_return(nil)
    yield
  end

  describe ".instance" do
    it "raises AuthenticationError constructing the client when Vault is unconfigured " \
       "(documents why .sealed?/.healthy?/.status must rescue it, not just the health check)" do
      with_vault_unconfigured do
        expect { described_class.instance }
          .to raise_error(described_class::AuthenticationError, /VAULT_ROLE_ID not configured/)
      end
    end
  end

  describe ".sealed?" do
    it "returns true (fails closed) instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.sealed? }.not_to raise_error
        expect(result).to be true
      end
    end
  end

  describe ".healthy?" do
    it "returns false instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.healthy? }.not_to raise_error
        expect(result).to be false
      end
    end
  end

  describe ".status" do
    it "returns an unavailable status hash instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.status }.not_to raise_error
        expect(result[:available]).to be false
        expect(result[:error]).to match(/VAULT_ROLE_ID not configured/)
      end
    end
  end
end

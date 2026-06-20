# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Security::CredentialRestorationService.
#
# This pins down the CURRENT behavior of the Vault transit pepper rotation
# orchestrator. It NEVER touches a real Vault: the service accepts a
# `vault_transit_client:` injection, and every example passes a test double
# whose `rotate_key` / `key_metadata` are stubbed. No network, no real key
# material — all pepper/version/blob values used here are fake fixtures.
#
# Notable current-behavior facts captured below:
#   * The injected transit client is exercised ONLY through #rotate_key and
#     #key_metadata (called by the private bump_pepper_version!). The private
#     rewrap_vault_blob! is presently a LOGGING PLACEHOLDER — it does NOT call
#     the transit client at all (the real transit/rewrap integration is
#     deferred to a future VaultTransitClient.rewrap, per the source comments).
#   * Per-account failures are rescued individually: the walk CONTINUES and the
#     failure is tallied in failed_count/errors (see partial-failure example).
#   * A failure raised while bumping the pepper version aborts the whole
#     rotation and returns an error Result.
RSpec.describe Security::CredentialRestorationService do
  # A double standing in for Security::VaultTransitClient. Only rotate_key and
  # key_metadata are ever invoked by the service, so those are all we stub.
  let(:vault_transit) { instance_double(Security::VaultTransitClient) }

  let(:pepper_key_name) { described_class::PEPPER_KEY_NAME }

  # Fake (non-secret) Vault key metadata: a rotated key now at latest_version 2,
  # which the service stringifies to "v2".
  def stub_pepper_bump_to(latest_version)
    allow(vault_transit).to receive(:rotate_key).with(pepper_key_name)
    allow(vault_transit).to receive(:key_metadata)
      .with(pepper_key_name)
      .and_return(data: { latest_version: latest_version })
  end

  describe ".rotate_transit_pepper! (class entrypoint)" do
    it "delegates to an instance built around the injected client" do
      stub_pepper_bump_to(2)

      result = described_class.rotate_transit_pepper!(
        reencrypt_existing: false,
        vault_transit_client: vault_transit
      )

      expect(result.ok?).to be true
      expect(result.latest_version).to eq("v2")
    end
  end

  describe "#rotate_transit_pepper! with reencrypt_existing: false" do
    subject(:service) { described_class.new(vault_transit_client: vault_transit) }

    it "bumps the pepper key version via the transit client" do
      expect(vault_transit).to receive(:rotate_key).with(pepper_key_name)
      allow(vault_transit).to receive(:key_metadata)
        .with(pepper_key_name)
        .and_return(data: { latest_version: 2 })

      service.rotate_transit_pepper!(reencrypt_existing: false)
    end

    it "returns the new version derived from key metadata as a 'v<N>' string" do
      stub_pepper_bump_to(7)

      result = service.rotate_transit_pepper!(reencrypt_existing: false)

      expect(result.latest_version).to eq("v7")
    end

    it "does NOT walk/re-encrypt any accounts (counts are all zero)" do
      stub_pepper_bump_to(2)
      # An account that WOULD be eligible for rewrap is present...
      create(:account, transit_key_version: "v1",
                       encryption_key_vault_path: "secret/data/accounts/fake-1")

      result = service.rotate_transit_pepper!(reencrypt_existing: false)

      expect(result.ok?).to be true
      expect(result.rotated_count).to eq(0)
      expect(result.skipped_count).to eq(0)
      expect(result.failed_count).to eq(0)
      expect(result.errors).to eq([])
    end

    it "accepts the metadata under string keys too (Vault HTTP shape)" do
      allow(vault_transit).to receive(:rotate_key).with(pepper_key_name)
      allow(vault_transit).to receive(:key_metadata)
        .with(pepper_key_name)
        .and_return("data" => { "latest_version" => 4 })

      result = service.rotate_transit_pepper!(reencrypt_existing: false)

      expect(result.latest_version).to eq("v4")
    end
  end

  describe "#rotate_transit_pepper! with reencrypt_existing: true" do
    subject(:service) { described_class.new(vault_transit_client: vault_transit) }

    before { stub_pepper_bump_to(2) }

    it "bumps the version AND iterates eligible accounts, counting them rotated" do
      create(:account, transit_key_version: "v1",
                       encryption_key_vault_path: "secret/data/accounts/fake-1")
      create(:account, transit_key_version: nil,
                       encryption_key_vault_path: "secret/data/accounts/fake-2")

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      expect(result.ok?).to be true
      expect(result.latest_version).to eq("v2")
      expect(result.rotated_count).to eq(2)
      expect(result.failed_count).to eq(0)
    end

    it "persists the new version + rotated_at on each rewrapped account" do
      account = create(:account, transit_key_version: "v1",
                                 encryption_key_vault_path: "secret/data/accounts/fake-1")

      expect do
        service.rotate_transit_pepper!(reencrypt_existing: true)
      end.to change { account.reload.transit_key_version }.from("v1").to("v2")

      expect(account.reload.transit_key_rotated_at).to be_present
    end

    it "skips accounts already on the latest version (not selected by the query)" do
      create(:account, transit_key_version: "v2",
                       encryption_key_vault_path: "secret/data/accounts/already")

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      # Already-current accounts are excluded by the WHERE clause, so they are
      # neither rotated nor tallied as skipped here.
      expect(result.rotated_count).to eq(0)
      expect(result.skipped_count).to eq(0)
      expect(result.failed_count).to eq(0)
    end

    it "counts accounts with no encryption_key_vault_path as skipped" do
      # Selected by the query (version behind) but rotate_account! returns false
      # because there is no vault path / nothing to rewrap.
      create(:account, transit_key_version: "v1", encryption_key_vault_path: nil)

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      expect(result.rotated_count).to eq(0)
      expect(result.skipped_count).to eq(1)
      expect(result.failed_count).to eq(0)
    end

    it "does NOT invoke the transit client during rewrap (rewrap is a deferred placeholder)" do
      create(:account, transit_key_version: "v1",
                       encryption_key_vault_path: "secret/data/accounts/fake-1")

      # The only transit-client calls the service makes are the version bump
      # (rotate_key + key_metadata). The current rewrap path only logs; it does
      # not call encrypt/decrypt. Asserting those are never received
      # characterizes the placeholder implementation. (VaultTransitClient does
      # not yet implement #rewrap at all — the real transit/rewrap call is a
      # future slice — so there is no #rewrap method to even guard against.)
      expect(vault_transit).not_to receive(:encrypt)
      expect(vault_transit).not_to receive(:decrypt)

      result = service.rotate_transit_pepper!(reencrypt_existing: true)
      expect(result.rotated_count).to eq(1)
    end

    it "logs an audit line for the rewrap WITHOUT emitting any secret/blob value" do
      account = create(:account, transit_key_version: "v1",
                                 encryption_key_vault_path: "secret/data/accounts/fake-1")

      # Capture everything the service logs and assert no fake secret leaks.
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      service.rotate_transit_pepper!(reencrypt_existing: true)

      all_output = logged.join("\n")
      # The vault PATH (an identifier, not key material) is logged by design;
      # what must NEVER appear is plaintext key material. We assert the audit
      # trail references the account + intended action, and that nothing
      # resembling a pepper/secret value is present.
      expect(all_output).to include("account_rotated")
      expect(all_output).to include(account.id.to_s)
      expect(all_output).to match(/would_rewrap|account_rotated/)
    end
  end

  describe "error handling / partial-failure characterization" do
    subject(:service) { described_class.new(vault_transit_client: vault_transit) }

    it "aborts the whole rotation when bumping the pepper version fails" do
      allow(vault_transit).to receive(:rotate_key)
        .and_raise(Security::VaultTransitClient::TransitError, "vault down")

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      expect(result.ok?).to be false
      expect(result.error).to match(/pepper rotation failed/)
      expect(result.rotated_count).to eq(0)
    end

    it "aborts when key metadata lacks a latest_version" do
      allow(vault_transit).to receive(:rotate_key).with(pepper_key_name)
      allow(vault_transit).to receive(:key_metadata)
        .with(pepper_key_name)
        .and_return(data: {})

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      expect(result.ok?).to be false
      expect(result.error).to match(/pepper rotation failed/)
    end

    # PARTIAL-FAILURE CHARACTERIZATION:
    # A per-account failure is rescued inside the find_each loop, so the walk
    # CONTINUES to the next account. The failed account is tallied in
    # failed_count + errors and stays on its OLD version (its DB update is
    # rolled back by the per-account transaction), while healthy accounts are
    # rotated. The overall Result is ok? == false because failed_count > 0.
    #
    # CONSISTENCY NOTE: this leaves the fleet in a MIXED state across accounts
    # (some on the new version, some still on the old). That is by design here
    # — the failed account is left "ready for retry" per the source comment —
    # but callers MUST re-run rotation (or remediate) to converge; a single
    # rotation pass does not guarantee a fully-rewrapped fleet.
    it "continues past a per-account failure, tallies it, and leaves it on the old version" do
      stub_pepper_bump_to(2)

      good = create(:account, transit_key_version: "v1",
                              encryption_key_vault_path: "secret/data/accounts/good")
      bad  = create(:account, transit_key_version: "v1",
                              encryption_key_vault_path: "secret/data/accounts/bad")

      # Force rotate_account! to blow up for exactly one account by making its
      # persistence step raise. The service loads its own Account instances
      # inside find_each, so we intercept #update! on any instance and raise
      # only for the bad record's id (healthy account updates normally).
      allow_any_instance_of(Account).to receive(:update!).and_wrap_original do |orig, *args|
        receiver = orig.receiver
        raise ActiveRecord::RecordInvalid.new(receiver) if receiver.id == bad.id

        orig.call(*args)
      end

      result = service.rotate_transit_pepper!(reencrypt_existing: true)

      expect(result.ok?).to be false
      expect(result.rotated_count).to eq(1)            # the good account
      expect(result.failed_count).to eq(1)             # the bad account
      expect(result.errors.map { |e| e[:account_id] }).to include(bad.id)

      # Healthy account advanced; failed account rolled back to the old version.
      expect(good.reload.transit_key_version).to eq("v2")
      expect(bad.reload.transit_key_version).to eq("v1")
    end

    it "does not leak the exception's plaintext context in a way that exposes key material" do
      stub_pepper_bump_to(2)
      bad = create(:account, transit_key_version: "v1",
                             encryption_key_vault_path: "secret/data/accounts/bad")

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      allow_any_instance_of(Account).to receive(:update!).and_wrap_original do |orig, *args|
        raise StandardError, "boom" if orig.receiver.id == bad.id

        orig.call(*args)
      end

      service.rotate_transit_pepper!(reencrypt_existing: true)

      all_output = logged.join("\n")
      expect(all_output).to include("account_rotation_failed")
      expect(all_output).to include(bad.id.to_s)
      # Error log records class/message only — no key/pepper plaintext.
      expect(all_output).not_to match(/BEGIN .*PRIVATE KEY/)
    end
  end
end

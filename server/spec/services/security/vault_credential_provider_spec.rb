# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Security::VaultCredentialProvider.
#
# IMPORTANT (test hygiene / security):
#   * This spec NEVER contacts a real Vault server. The provider talks to Vault
#     exclusively through the class-level delegated methods on
#     Security::VaultClient (read_secret / get_credential / store_credential /
#     delete_secret / rotate_credential / healthy?). Every one of those is
#     stubbed here, so no network call is ever made.
#   * All "credential data" used below is FAKE, randomly-generated test material
#     (see `fake_data`). No real secret is ever constructed, logged, or asserted
#     on by value.
#   * The provider's private #vault_available? short-circuits to `false` whenever
#     Rails.env.test? is true (provider.rb line ~214). Because of that guard the
#     constructor always memoizes @vault_available = false in the test env. To
#     characterize the "Vault is available" branches we therefore build the
#     provider and then deterministically set @vault_available via
#     instance_variable_set — this exercises the real branch logic without
#     touching the network or the env guard. The `false` branches need no such
#     override (they are the test-env default), but we set them explicitly for
#     clarity and isolation.
RSpec.describe Security::VaultCredentialProvider do
  let(:account_id) { "acct-#{SecureRandom.uuid}" }
  let(:credential_id) { "cred-#{SecureRandom.uuid}" }

  # FAKE credential material — never a real secret, never logged by value.
  let(:fake_data) { { "api_key" => "test-#{SecureRandom.hex(8)}" } }
  let(:fake_new_data) { { "api_key" => "test-new-#{SecureRandom.hex(8)}" } }

  subject(:provider) { described_class.new(account_id: account_id) }

  # Builds a provider with @vault_available forced to the given value. We cannot
  # rely on the constructor to produce `true` because #vault_available? returns
  # false in Rails.env.test?, so we set the memoized ivar directly.
  def provider_with_vault(available)
    p = described_class.new(account_id: account_id)
    p.instance_variable_set(:@vault_available, available)
    p
  end

  # A minimal record stand-in. Only the attributes/methods the provider actually
  # touches are defined; `responds_to` lets us flip individual setter branches on
  # and off to characterize the provider's `respond_to?` guards precisely.
  #
  # The provider touches: vault_path, migrated_to_vault_at, encrypted_credentials,
  # credentials (reader), and (conditionally) the setters vault_path= /
  # credentials= / encrypted_credentials=, plus update! / save!.
  let(:record_class) do
    Class.new do
      attr_accessor :vault_path, :migrated_to_vault_at, :encrypted_credentials, :credentials
      attr_reader :updated_with, :saved

      def initialize(vault_path: nil, migrated_to_vault_at: nil, encrypted_credentials: nil,
                     credentials: nil, responds_to: %i[vault_path= credentials= encrypted_credentials=])
        @vault_path = vault_path
        @migrated_to_vault_at = migrated_to_vault_at
        @encrypted_credentials = encrypted_credentials
        @credentials = credentials
        @responds_to = responds_to
        @updated_with = nil
        @saved = false
      end

      # The provider probes for setter availability via respond_to?; honor the
      # configured allow-list so individual branches can be exercised.
      def respond_to?(method_name, include_private = false)
        sym = method_name.to_sym
        return @responds_to.include?(sym) if sym.to_s.end_with?("=")

        super
      end

      def update!(attrs)
        @updated_with = attrs
        attrs.each { |k, v| public_send("#{k}=", v) if respond_to?("#{k}=") || instance_variable_defined?("@#{k}") }
        true
      end

      def save!
        @saved = true
      end
    end
  end

  # All attributes (and the optional `responds_to:` allow-list) are passed
  # straight through as keyword args to the record stand-in's constructor.
  def build_record(**kwargs)
    record_class.new(**kwargs)
  end

  describe "#vault_available?" do
    it "returns false in the test environment regardless of VaultClient health" do
      # The private guard short-circuits before VaultClient.healthy? is ever
      # called, so this characterizes the test-env behavior (never hits Vault).
      expect(Security::VaultClient).not_to receive(:healthy?)
      expect(provider.send(:vault_available?)).to be false
    end

    it "memoizes @vault_available=false on construction in the test env" do
      expect(provider.instance_variable_get(:@vault_available)).to be false
    end

    it "consults VaultClient.healthy? when the env guard is bypassed and survives errors (fails closed)" do
      # Simulate a non-test env path to characterize the real health delegation.
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Security::VaultClient).to receive(:healthy?).and_return(true)
      expect(described_class.new(account_id: account_id).send(:vault_available?)).to be true

      allow(Security::VaultClient).to receive(:healthy?).and_raise(StandardError, "boom")
      # Rescue StandardError => returns false (fail closed — safe default).
      expect(described_class.new(account_id: account_id).send(:vault_available?)).to be false
    end
  end

  describe "#store_credential" do
    context "when Vault is available" do
      subject(:provider) { provider_with_vault(true) }

      it "writes to the conventional Vault path and updates the record" do
        vault_path = "secret/data/powernode/accounts/#{account_id}/ai-providers/#{credential_id}"
        record = build_record

        expect(Security::VaultClient).to receive(:store_credential).with(
          account_id: account_id,
          credential_type: "ai-providers", # CREDENTIAL_TYPES[:ai_provider]
          credential_id: credential_id,
          data: fake_data
        ).and_return(vault_path)

        result = provider.store_credential(
          credential_type: :ai_provider,
          credential_id: credential_id,
          data: fake_data,
          record: record
        )

        expect(result).to eq(stored_in: :vault, path: vault_path)
        expect(record.vault_path).to eq(vault_path)
        expect(record.migrated_to_vault_at).to be_a(Time)
        expect(record.updated_with).to include(:vault_path, :migrated_to_vault_at)
      end

      it "maps an unknown credential_type to its raw string for the type path" do
        expect(Security::VaultClient).to receive(:store_credential)
          .with(hash_including(credential_type: "totally_custom"))
          .and_return("some/path")

        provider.store_credential(
          credential_type: :totally_custom,
          credential_id: credential_id,
          data: fake_data,
          record: nil
        )
      end

      it "returns the vault result even when no record is supplied" do
        allow(Security::VaultClient).to receive(:store_credential).and_return("p")
        result = provider.store_credential(
          credential_type: :ai_provider, credential_id: credential_id, data: fake_data, record: nil
        )
        expect(result).to eq(stored_in: :vault, path: "p")
      end

      it "falls back to database storage when the Vault write raises VaultError" do
        record = build_record
        allow(Security::VaultClient).to receive(:store_credential)
          .and_raise(Security::VaultClient::VaultError, "vault down")

        result = provider.store_credential(
          credential_type: :ai_provider, credential_id: credential_id, data: fake_data, record: record
        )

        expect(result).to eq(stored_in: :database)
        expect(record.credentials).to eq(fake_data)
        expect(record.saved).to be true
      end
    end

    context "when Vault is unavailable" do
      subject(:provider) { provider_with_vault(false) }

      it "never calls VaultClient and stores in the database when the record supports it" do
        record = build_record
        expect(Security::VaultClient).not_to receive(:store_credential)

        result = provider.store_credential(
          credential_type: :ai_provider, credential_id: credential_id, data: fake_data, record: record
        )

        expect(result).to eq(stored_in: :database)
        expect(record.credentials).to eq(fake_data)
      end

      it "raises CredentialError when no storage method is available" do
        record = build_record(responds_to: []) # no credentials= setter

        expect do
          provider.store_credential(
            credential_type: :ai_provider, credential_id: credential_id, data: fake_data, record: record
          )
        end.to raise_error(described_class::CredentialError, /No storage method/)
      end

      it "raises CredentialError when no record is supplied at all" do
        expect do
          provider.store_credential(
            credential_type: :ai_provider, credential_id: credential_id, data: fake_data, record: nil
          )
        end.to raise_error(described_class::CredentialError)
      end
    end
  end

  describe "#get_credential" do
    context "when Vault is available" do
      subject(:provider) { provider_with_vault(true) }

      it "reads directly from record.vault_path when present" do
        record = build_record(vault_path: "secret/data/x", migrated_to_vault_at: Time.current)
        expect(Security::VaultClient).to receive(:read_secret)
          .with("secret/data/x").and_return(fake_data)

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "falls back to the convention path when the direct read raises (SecretNotFound/Connection)" do
        record = build_record(vault_path: "secret/data/x")
        allow(Security::VaultClient).to receive(:read_secret)
          .and_raise(Security::VaultClient::SecretNotFoundError, "missing")
        expect(Security::VaultClient).to receive(:get_credential).with(
          account_id: account_id, credential_type: "ai-providers", credential_id: credential_id
        ).and_return(fake_data)

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "uses the convention path when the record has no vault_path" do
        record = build_record
        expect(Security::VaultClient).not_to receive(:read_secret)
        expect(Security::VaultClient).to receive(:get_credential).and_return(fake_data)

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "falls back to record.credentials when the convention lookup returns blank" do
        record = build_record(credentials: fake_data)
        allow(Security::VaultClient).to receive(:get_credential).and_return(nil)

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "swallows VaultError on the convention lookup and falls back to the database" do
        record = build_record(credentials: fake_data)
        allow(Security::VaultClient).to receive(:get_credential)
          .and_raise(Security::VaultClient::VaultError, "auth fail")

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "returns nil when nothing is in Vault and there is no record" do
        allow(Security::VaultClient).to receive(:get_credential).and_return(nil)
        expect(
          provider.get_credential(credential_type: :ai_provider, credential_id: credential_id, record: nil)
        ).to be_nil
      end
    end

    context "when Vault is unavailable" do
      subject(:provider) { provider_with_vault(false) }

      it "never calls Vault and returns the record's database credentials" do
        record = build_record(credentials: fake_data)
        expect(Security::VaultClient).not_to receive(:read_secret)
        expect(Security::VaultClient).not_to receive(:get_credential)

        result = provider.get_credential(
          credential_type: :ai_provider, credential_id: credential_id, record: record
        )
        expect(result).to eq(fake_data)
      end

      it "returns nil when there is no record" do
        expect(
          provider.get_credential(credential_type: :ai_provider, credential_id: credential_id, record: nil)
        ).to be_nil
      end
    end
  end

  describe "#delete_credential" do
    context "when Vault is available and the record has a vault_path" do
      subject(:provider) { provider_with_vault(true) }

      it "deletes from Vault and clears the database columns" do
        record = build_record(
          vault_path: "secret/data/x",
          migrated_to_vault_at: Time.current,
          encrypted_credentials: "blob"
        )
        expect(Security::VaultClient).to receive(:delete_secret).with("secret/data/x")

        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: record)
        ).to be true

        expect(record.encrypted_credentials).to be_nil
        expect(record.vault_path).to be_nil
        expect(record.migrated_to_vault_at).to be_nil
      end

      it "still clears the database columns when the Vault delete raises VaultError" do
        record = build_record(vault_path: "secret/data/x", encrypted_credentials: "blob")
        allow(Security::VaultClient).to receive(:delete_secret)
          .and_raise(Security::VaultClient::VaultError, "vault down")

        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: record)
        ).to be true
        expect(record.encrypted_credentials).to be_nil
      end
    end

    context "when Vault is unavailable" do
      subject(:provider) { provider_with_vault(false) }

      it "skips Vault entirely and clears the database columns" do
        record = build_record(vault_path: "secret/data/x", encrypted_credentials: "blob")
        expect(Security::VaultClient).not_to receive(:delete_secret)

        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: record)
        ).to be true
        expect(record.encrypted_credentials).to be_nil
        expect(record.vault_path).to be_nil
      end

      it "returns true even when the record cannot clear encrypted_credentials" do
        record = build_record(vault_path: "p", responds_to: [])
        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: record)
        ).to be true
      end

      it "returns true with no record" do
        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: nil)
        ).to be true
      end
    end

    # The gap #purge_credential! exists to close (IMP-20fb59ec849d): with no
    # record neither branch above can fire, so this reports success having
    # purged nothing — including for material #store_credential wrote to the
    # convention path with no record. Pinned so the asymmetry is a documented
    # property of THIS method rather than a surprise at the call site.
    context "when Vault is available but the caller passes no record" do
      subject(:provider) { provider_with_vault(true) }

      it "returns true without asking Vault to delete anything" do
        expect(Security::VaultClient).not_to receive(:delete_secret)
        expect(Security::VaultClient).not_to receive(:delete_credential)

        expect(
          provider.delete_credential(credential_type: :ai_provider, credential_id: credential_id, record: nil)
        ).to be true
      end
    end
  end

  describe "#purge_credential!" do
    context "when Vault is available" do
      subject(:provider) { provider_with_vault(true) }

      it "deletes the convention path #store_credential writes to" do
        expect(Security::VaultClient).to receive(:delete_credential).with(
          account_id: account_id,
          credential_type: "docker-daemon-tls",
          credential_id: credential_id
        )

        expect(
          provider.purge_credential!(credential_type: :docker_daemon_tls, credential_id: credential_id)
        ).to be true
      end

      it "maps an unknown credential type through to its own name" do
        expect(Security::VaultClient).to receive(:delete_credential).with(
          account_id: account_id, credential_type: "not-a-known-type", credential_id: credential_id
        )

        provider.purge_credential!(credential_type: "not-a-known-type", credential_id: credential_id)
      end

      # Deliberately NOT swallowed: a teardown path that is told the secret is
      # gone when it is not is the whole defect this method was added for.
      it "propagates a Vault failure to the caller" do
        allow(Security::VaultClient).to receive(:delete_credential)
          .and_raise(Security::VaultClient::ConnectionError, "vault down")

        expect {
          provider.purge_credential!(credential_type: :docker_daemon_tls, credential_id: credential_id)
        }.to raise_error(Security::VaultClient::ConnectionError)
      end
    end

    context "when Vault is unavailable" do
      subject(:provider) { provider_with_vault(false) }

      it "answers false rather than claiming a purge it did not perform" do
        expect(Security::VaultClient).not_to receive(:delete_credential)

        expect(
          provider.purge_credential!(credential_type: :docker_daemon_tls, credential_id: credential_id)
        ).to be false
      end
    end
  end

  describe "#rotate_credential" do
    context "when Vault is available" do
      subject(:provider) { provider_with_vault(true) }

      it "rotates in Vault with the NEW data and never passes old data" do
        record = build_record(encrypted_credentials: "old-blob")
        expect(Security::VaultClient).to receive(:rotate_credential).with(
          account_id: account_id,
          credential_type: "ai-providers",
          credential_id: credential_id,
          new_data: fake_new_data
        )

        result = provider.rotate_credential(
          credential_type: :ai_provider,
          credential_id: credential_id,
          new_data: fake_new_data,
          record: record
        )

        expect(result).to eq(rotated_in: :vault)
        # Old database copy is cleared so the rotated-away secret does not linger.
        expect(record.encrypted_credentials).to be_nil
      end

      it "does not attempt to clear encrypted_credentials when there is none" do
        record = build_record(encrypted_credentials: nil)
        allow(Security::VaultClient).to receive(:rotate_credential)

        result = provider.rotate_credential(
          credential_type: :ai_provider, credential_id: credential_id, new_data: fake_new_data, record: record
        )
        expect(result).to eq(rotated_in: :vault)
        expect(record.updated_with).to be_nil # update! not invoked
      end

      it "falls back to database storage when the Vault rotate raises VaultError" do
        record = build_record
        allow(Security::VaultClient).to receive(:rotate_credential)
          .and_raise(Security::VaultClient::VaultError, "vault down")

        result = provider.rotate_credential(
          credential_type: :ai_provider, credential_id: credential_id, new_data: fake_new_data, record: record
        )

        expect(result).to eq(rotated_in: :database)
        expect(record.credentials).to eq(fake_new_data)
        expect(record.saved).to be true
      end
    end

    context "when Vault is unavailable" do
      subject(:provider) { provider_with_vault(false) }

      it "stores the new data in the database when the record supports it" do
        record = build_record
        expect(Security::VaultClient).not_to receive(:rotate_credential)

        result = provider.rotate_credential(
          credential_type: :ai_provider, credential_id: credential_id, new_data: fake_new_data, record: record
        )
        expect(result).to eq(rotated_in: :database)
        expect(record.credentials).to eq(fake_new_data)
      end

      it "raises CredentialError when no storage method is available" do
        record = build_record(responds_to: [])
        expect do
          provider.rotate_credential(
            credential_type: :ai_provider, credential_id: credential_id, new_data: fake_new_data, record: record
          )
        end.to raise_error(described_class::CredentialError, /No storage method/)
      end
    end
  end

  describe "#stored_in_vault?" do
    it "is true only when both vault_path and migrated_to_vault_at are present" do
      both = build_record(vault_path: "p", migrated_to_vault_at: Time.current)
      expect(provider.stored_in_vault?(both)).to be true
    end

    it "is false when migrated_to_vault_at is missing" do
      expect(provider.stored_in_vault?(build_record(vault_path: "p"))).to be_falsey
    end

    it "is false when vault_path is missing" do
      expect(provider.stored_in_vault?(build_record(migrated_to_vault_at: Time.current))).to be_falsey
    end

    it "is false (nil-safe) for a nil record" do
      expect(provider.stored_in_vault?(nil)).to be_falsey
    end
  end

  describe "#credential_status" do
    subject(:provider) { provider_with_vault(true) }

    it "reports :vault storage when migrated to Vault" do
      ts = Time.current
      record = build_record(vault_path: "secret/data/x", migrated_to_vault_at: ts)
      status = provider.credential_status(record)

      expect(status).to include(
        vault_path: "secret/data/x",
        migrated_to_vault_at: ts,
        has_database_encryption: false,
        vault_available: true,
        storage_location: :vault
      )
    end

    it "reports :database storage when only encrypted_credentials are present" do
      record = build_record(encrypted_credentials: "blob")
      status = provider.credential_status(record)

      expect(status[:has_database_encryption]).to be true
      expect(status[:storage_location]).to eq(:database)
    end

    it "reports :none when nothing is stored" do
      expect(provider.credential_status(build_record)[:storage_location]).to eq(:none)
    end

    it "reports :none and is nil-safe for a nil record" do
      status = provider.credential_status(nil)
      expect(status[:vault_path]).to be_nil
      expect(status[:storage_location]).to eq(:none)
    end

    it "reflects @vault_available=false in the status payload" do
      status = provider_with_vault(false).credential_status(build_record)
      expect(status[:vault_available]).to be false
    end
  end
end

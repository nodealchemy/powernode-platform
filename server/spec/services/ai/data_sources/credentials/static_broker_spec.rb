# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::StaticBroker — the no-op / generic-fallback
# broker. It performs NO exchange and makes NO outbound call: #acquire returns
# the resolved base credential UNCHANGED (the SAME object), mirroring the way
# SignerRegistry falls back to NoneSigner. This is what Registry.for resolves for
# an unknown, blank, or explicit "static" broker type, so adding a source with an
# unrecognized broker type degrades safely to "no brokering".
#
# HERMETIC by construction: there is nothing to stub (no factory, no AWS/Vault/
# OAuth seam) because the broker never reaches outside itself.
RSpec.describe Ai::DataSources::Credentials::StaticBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:data_source) { instance_double(Ai::DataSource, slug: "weather_src") }

  describe "#acquire" do
    it "returns the base_credential UNCHANGED (the same object) for a double credential" do
      base_credential = instance_double(Ai::DataSourceCredential,
                                        decrypted_api_key: "base-key",
                                        decrypted_api_secret: "base-secret")

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: {})

      # Same object identity — no BrokeredCredential is built, nothing is copied.
      expect(result).to be(base_credential)
    end

    it "returns the persisted :ai_data_source_credential record unchanged" do
      base_credential = create(:ai_data_source_credential, :with_secret)

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: {})

      expect(result).to be(base_credential)
      # The pass-through still satisfies the signer contract.
      expect(result.decrypted_api_key).to eq("test-api-key")
      expect(result.decrypted_api_secret).to eq("test-api-secret")
    end

    it "returns base_credential unchanged regardless of the config contents" do
      base_credential = instance_double(Ai::DataSourceCredential,
                                        decrypted_api_key: "k", decrypted_api_secret: "s")

      result = broker.acquire(
        data_source: data_source,
        base_credential: base_credential,
        config: { "role_arn" => "arn:aws:iam::1:role/x", "token_url" => "https://idp/token" }
      )

      expect(result).to be(base_credential)
    end

    it "passes a non-Hash config through the BaseBroker coercion without raising" do
      base_credential = instance_double(Ai::DataSourceCredential,
                                        decrypted_api_key: "k", decrypted_api_secret: "s")

      expect do
        @result = broker.acquire(data_source: data_source, base_credential: base_credential, config: nil)
      end.not_to raise_error

      expect(@result).to be(base_credential)
    end

    it "returns nil when the base_credential is nil (degrade path)" do
      expect(
        broker.acquire(data_source: data_source, base_credential: nil, config: {})
      ).to be_nil
    end

    it "makes no outbound HTTP connection (never touches the HttpConnectionFactory)" do
      base_credential = instance_double(Ai::DataSourceCredential,
                                        decrypted_api_key: "k", decrypted_api_secret: "s")
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:validate_url!)

      broker.acquire(data_source: data_source, base_credential: base_credential, config: {})
    end
  end

  describe "#broker_type" do
    it "is pinned to the canonical 'static' token" do
      # broker_type is protected; assert it via the audit line StaticBroker emits.
      expect(broker.send(:broker_type)).to eq("static")
    end
  end
end

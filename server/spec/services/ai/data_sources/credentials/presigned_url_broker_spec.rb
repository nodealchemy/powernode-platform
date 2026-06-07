# frozen_string_literal: true

require "rails_helper"
require "openssl"
require "base64"
require "uri"

# Ai::DataSources::Credentials::PresignedUrlBroker — exchanges the resolved base
# credential for a SHORT-LIVED, self-authenticating PRESIGNED URL whose query
# string carries the signature, so the later fetch needs no Authorization header
# and no separate signing step. Two providers:
#
#   (a) "s3" (DEFAULT) — Aws::S3::Presigner over the base credential's AWS keys.
#   (b) "azure_sas"   — a deterministic Azure Blob service SAS via HMAC-SHA256
#                       (OpenSSL, no SDK) over the base credential's account key.
#
# RESULT: a BrokeredCredential carrying the URL via #presigned_url; its
# decrypted_api_key is intentionally nil (the URL itself carries the auth).
#
# HERMETIC: NO outbound HTTP happens in acquisition — S3 presigning is a local
# HMAC and the Azure SAS is a local HMAC. For S3 we still stub the AWS SDK
# (Aws::S3::Client.new + Aws::S3::Presigner.new) so the test never touches AWS
# credentials/metadata endpoints and the URL is deterministic. The Azure path
# runs the REAL inline HMAC against a fixed clock, and we recompute the expected
# signature in-test to pin it.
#
# The cache uses the REAL shared Redis client (Powernode::Redis.client); each
# example flushes the ds_cred_broker:* namespace. The DataSource after_commit KG
# sync is stubbed on every factory create.
RSpec.describe Ai::DataSources::Credentials::PresignedUrlBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  # Base credential supplies the AWS keys (S3) / account name + key (Azure):
  #   decrypted_api_key    => access_key_id   (S3)  / account_name (Azure)
  #   decrypted_api_secret => secret_access_key (S3) / account_key  (Azure)
  let(:base_credential) do
    instance_double(
      "Ai::DataSourceCredential",
      decrypted_api_key: "AKIABASEKEY",
      decrypted_api_secret: "baseSecretAccessKey"
    )
  end

  let(:presigned) { "https://bucket.s3.amazonaws.com/key?X-Amz-Signature=deadbeef&X-Amz-Expires=900" }

  def flush_broker_cache!
    client = Powernode::Redis.client
    return unless client

    keys = client.keys("#{Ai::DataSources::Credentials::BrokerCache::NAMESPACE}*")
    client.del(*keys) if keys.any?
  rescue StandardError
    nil
  end

  # Wire the AWS SDK so presign returns +url+ without touching AWS. Returns the
  # presigner double so a caller can assert call counts (cache-hit verification).
  def stub_s3_presign(url: presigned)
    client = instance_double("Aws::S3::Client")
    presigner = instance_double("Aws::S3::Presigner")
    allow(Aws::S3::Client).to receive(:new).and_return(client)
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
    allow(presigner).to receive(:presigned_url).and_return(url)
    presigner
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    flush_broker_cache!
  end

  after { flush_broker_cache! }

  # ==========================================================================
  # (a) S3 presigned GET (default provider)
  # ==========================================================================
  describe "#acquire — S3 (default provider)" do
    let(:config) { { "bucket" => "b", "object_key" => "k", "region" => "us-east-1" } }

    it "defaults the provider to s3 when none is configured" do
      presigner = stub_s3_presign
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      expect(presigner).to have_received(:presigned_url)
        .with(:get_object, hash_including(bucket: "b", key: "k"))
    end

    it "returns a BrokeredCredential whose #presigned_url is the SDK-signed URL" do
      stub_s3_presign(url: presigned)
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result.presigned_url).to eq(presigned)
      expect(result["presigned_url"]).to eq(presigned)
    end

    it "leaves decrypted_api_key nil — the URL itself carries the auth" do
      stub_s3_presign
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.decrypted_api_key).to be_nil
      expect(result.decrypted_api_secret).to be_nil
    end

    it "presigns with the BASE credential's AWS keys (never config-supplied secrets)" do
      client = instance_double("Aws::S3::Client")
      presigner = instance_double("Aws::S3::Presigner")
      allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
      allow(presigner).to receive(:presigned_url).and_return(presigned)

      creds = instance_double("Aws::Credentials")
      expect(Aws::Credentials).to receive(:new)
        .with("AKIABASEKEY", "baseSecretAccessKey").and_return(creds)
      expect(Aws::S3::Client).to receive(:new)
        .with(hash_including(region: "us-east-1", credentials: creds)).and_return(client)

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
    end

    it "passes the session token to Aws::Credentials when the base credential carries one" do
      sts_base = instance_double("Ai::DataSourceCredential")
      allow(sts_base).to receive(:decrypted_api_key).and_return("AKIASTS")
      allow(sts_base).to receive(:decrypted_api_secret).and_return("stsSecret")
      allow(sts_base).to receive(:[]).with("session_token").and_return("FwoGSESSION")
      allow(sts_base).to receive(:[]).with("security_token").and_return(nil)

      client = instance_double("Aws::S3::Client")
      presigner = instance_double("Aws::S3::Presigner")
      allow(Aws::S3::Client).to receive(:new).and_return(client)
      allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
      allow(presigner).to receive(:presigned_url).and_return(presigned)

      expect(Aws::Credentials).to receive(:new)
        .with("AKIASTS", "stsSecret", "FwoGSESSION")
        .and_return(instance_double("Aws::Credentials"))

      broker.acquire(data_source: data_source, base_credential: sts_base, config: config)
    end

    it "sets expires_at ≈ now + DEFAULT_EXPIRES_IN (15 min) when expires_in is omitted" do
      stub_s3_presign
      freeze_time do
        result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
        expect(result.expires_at).to be_within(2.seconds).of(Time.current + described_class::DEFAULT_EXPIRES_IN.seconds)
      end
    end

    it "honors a configured expires_in" do
      presigner = stub_s3_presign
      cfg = config.merge("expires_in" => 300)
      broker.acquire(data_source: data_source, base_credential: base_credential, config: cfg)
      expect(presigner).to have_received(:presigned_url)
        .with(:get_object, hash_including(expires_in: 300))
    end

    it "clamps an over-large expires_in to the S3 7-day cap" do
      presigner = stub_s3_presign
      cfg = config.merge("expires_in" => 10_000_000)
      broker.acquire(data_source: data_source, base_credential: base_credential, config: cfg)
      expect(presigner).to have_received(:presigned_url)
        .with(:get_object, hash_including(expires_in: described_class::S3_MAX_EXPIRES_IN))
    end

    it "caches the signed URL across calls (presigns only once for a swarm)" do
      presigner = stub_s3_presign
      first = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      second = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(presigner).to have_received(:presigned_url).once
      expect(first.presigned_url).to eq(presigned)
      expect(second.presigned_url).to eq(presigned)
    end

    it "re-presigns when the resource (object_key) differs — distinct cache keys" do
      presigner = stub_s3_presign
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("object_key" => "other-key"))

      expect(presigner).to have_received(:presigned_url).twice
    end
  end

  # ==========================================================================
  # S3 degrade paths
  # ==========================================================================
  describe "#acquire — S3 degrades to base" do
    it "when bucket is missing (no presign attempted)" do
      expect(Aws::S3::Presigner).not_to receive(:new)
      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "object_key" => "k", "region" => "us-east-1" })
      expect(result).to eq(base_credential)
    end

    it "when object_key is missing" do
      expect(Aws::S3::Presigner).not_to receive(:new)
      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "bucket" => "b", "region" => "us-east-1" })
      expect(result).to eq(base_credential)
    end

    it "when region is missing" do
      expect(Aws::S3::Presigner).not_to receive(:new)
      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "bucket" => "b", "object_key" => "k" })
      expect(result).to eq(base_credential)
    end

    it "when the base credential carries no AWS keys" do
      keyless = instance_double("Ai::DataSourceCredential", decrypted_api_key: nil, decrypted_api_secret: nil)
      allow(keyless).to receive(:[]).and_return(nil)
      expect(Aws::S3::Presigner).not_to receive(:new)

      # Degrades to the SAME (keyless) base credential it was handed.
      result = broker.acquire(data_source: data_source, base_credential: keyless,
                              config: { "bucket" => "b", "object_key" => "k", "region" => "us-east-1" })
      expect(result).to eq(keyless)
    end

    it "when the SDK presign raises — never propagates, returns base" do
      client = instance_double("Aws::S3::Client")
      presigner = instance_double("Aws::S3::Presigner")
      allow(Aws::S3::Client).to receive(:new).and_return(client)
      allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
      allow(presigner).to receive(:presigned_url).and_raise(StandardError, "sdk boom")

      result = nil
      expect do
        result = broker.acquire(data_source: data_source, base_credential: base_credential,
                                config: { "bucket" => "b", "object_key" => "k", "region" => "us-east-1" })
      end.not_to raise_error
      expect(result).to eq(base_credential)
    end
  end

  # ==========================================================================
  # (b) Azure Blob service SAS — deterministic HMAC, no SDK
  # ==========================================================================
  describe "#acquire — azure_sas" do
    let(:account_key_b64) { Base64.strict_encode64("super-secret-32-byte-account-key!") }
    let(:azure_base) do
      instance_double(
        "Ai::DataSourceCredential",
        decrypted_api_key: "mystorageacct",
        decrypted_api_secret: account_key_b64
      )
    end
    let(:config) do
      {
        "provider" => "azure_sas",
        "container" => "container1",
        "blob" => "path/to/object.json"
      }
    end

    # Recompute the exact SAS signature the impl produces, for a frozen clock, so
    # the test pins the deterministic HMAC rather than merely asserting structure.
    def expected_azure_signature(account_name:, container:, blob:, starts_at:, expires_at:, key_b64:)
      version = described_class::AZURE_SAS_VERSION
      start_str = starts_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      expiry_str = expires_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      canonical_resource = "/blob/#{account_name}/#{container}/#{blob}"
      string_to_sign = [
        "r", start_str, expiry_str, canonical_resource,
        "", "", "https", version, described_class::AZURE_RESOURCE_BLOB,
        "", "", "", "", "", "", ""
      ].join("\n")
      key = Base64.decode64(key_b64)
      digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new("SHA256"), key, string_to_sign)
      Base64.strict_encode64(digest)
    end

    it "returns a BrokeredCredential carrying a SAS-tokenized blob URL" do
      result = broker.acquire(data_source: data_source, base_credential: azure_base, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      url = result.presigned_url
      expect(url).to start_with("https://mystorageacct.blob.core.windows.net/container1/path/to/object.json?")
      # SAS query carries the canonical signed fields + a signature.
      expect(url).to include("sv=#{described_class::AZURE_SAS_VERSION}")
      expect(url).to include("sr=#{described_class::AZURE_RESOURCE_BLOB}")
      expect(url).to include("sp=r")
      expect(url).to include("spr=https")
      expect(url).to include("sig=")
    end

    it "produces the EXACT deterministic HMAC signature for a frozen clock" do
      freeze_time do
        now = Time.current
        starts_at = now - 60
        expires_at = now + described_class::DEFAULT_EXPIRES_IN
        expected_sig = expected_azure_signature(
          account_name: "mystorageacct", container: "container1", blob: "path/to/object.json",
          starts_at: starts_at, expires_at: expires_at, key_b64: account_key_b64
        )

        result = broker.acquire(data_source: data_source, base_credential: azure_base, config: config)
        url = result.presigned_url
        sig_param = URI.decode_www_form(URI.parse(url).query).to_h["sig"]

        expect(sig_param).to eq(expected_sig)
      end
    end

    it "is STABLE across two calls for fixed inputs (same SAS URL)" do
      freeze_time do
        first = broker.acquire(data_source: data_source, base_credential: azure_base, config: config)
        # Bust the cache to prove stability comes from the deterministic HMAC, not
        # from the Redis cache returning the same blob.
        flush_broker_cache!
        second = broker.acquire(data_source: data_source, base_credential: azure_base, config: config)

        expect(first.presigned_url).to eq(second.presigned_url)
      end
    end

    it "uses config account_name when supplied, else the base credential's key" do
      cfg = config.merge("account_name" => "overridden")
      result = broker.acquire(data_source: data_source, base_credential: azure_base, config: cfg)
      expect(result.presigned_url).to start_with("https://overridden.blob.core.windows.net/")
    end

    it "honors a custom endpoint_suffix" do
      cfg = config.merge("endpoint_suffix" => "core.chinacloudapi.cn")
      result = broker.acquire(data_source: data_source, base_credential: azure_base, config: cfg)
      expect(result.presigned_url).to include(".blob.core.chinacloudapi.cn/")
    end

    it "leaves decrypted_api_key nil (the SAS URL carries the auth)" do
      result = broker.acquire(data_source: data_source, base_credential: azure_base, config: config)
      expect(result.decrypted_api_key).to be_nil
    end

    describe "degrade paths" do
      it "when the container is missing" do
        result = broker.acquire(data_source: data_source, base_credential: azure_base,
                                config: { "provider" => "azure_sas", "blob" => "b" })
        expect(result).to eq(azure_base)
      end

      it "when the blob is missing" do
        result = broker.acquire(data_source: data_source, base_credential: azure_base,
                                config: { "provider" => "azure_sas", "container" => "c" })
        expect(result).to eq(azure_base)
      end

      it "when the base credential supplies no account key" do
        no_key = instance_double("Ai::DataSourceCredential",
                                 decrypted_api_key: "acct", decrypted_api_secret: nil)
        result = broker.acquire(data_source: data_source, base_credential: no_key, config: config)
        expect(result).to eq(no_key)
      end
    end
  end

  # ==========================================================================
  # Unknown provider
  # ==========================================================================
  describe "#acquire — unknown provider" do
    it "degrades to base rather than guessing" do
      expect(Aws::S3::Presigner).not_to receive(:new)
      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "provider" => "gcs_signed", "bucket" => "b", "object_key" => "k" })
      expect(result).to eq(base_credential)
    end
  end

  # ==========================================================================
  # SECURITY — the signed URL / account key are NEVER logged
  # ==========================================================================
  describe "secret never logged" do
    let(:config) { { "bucket" => "b", "object_key" => "k", "region" => "us-east-1" } }

    it "the S3 audit line carries no signature query string and no AWS secret" do
      stub_s3_presign(url: presigned)
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      joined = logged.join("\n")
      expect(joined).to include("broker=presigned_url")
      expect(joined).to include("provider=s3")
      expect(joined).to include("outcome=acquired")
      expect(joined).not_to include("X-Amz-Signature=deadbeef")
      expect(joined).not_to include("baseSecretAccessKey")
    end

    it "the Azure path logs neither the account key nor the SAS signature" do
      account_key_b64 = Base64.strict_encode64("super-secret-32-byte-account-key!")
      azure_base = instance_double("Ai::DataSourceCredential",
                                   decrypted_api_key: "mystorageacct",
                                   decrypted_api_secret: account_key_b64)
      captured = []
      %i[debug info warn error fatal].each do |lvl|
        allow(Rails.logger).to receive(lvl) { |msg| captured << msg.to_s }
      end

      result = broker.acquire(
        data_source: data_source, base_credential: azure_base,
        config: { "provider" => "azure_sas", "container" => "c", "blob" => "obj" }
      )
      sig = URI.decode_www_form(URI.parse(result.presigned_url).query).to_h["sig"]

      blob = captured.join("\n")
      expect(blob).not_to include(account_key_b64)
      expect(blob).not_to include(sig)
    end

    it "BrokeredCredential#inspect redacts the presigned URL" do
      stub_s3_presign(url: presigned)
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.inspect).not_to include("X-Amz-Signature=deadbeef")
      expect(result.inspect).to include("fields=")
    end
  end

  # ==========================================================================
  # Registry token
  # ==========================================================================
  describe "#broker_type" do
    it "is the canonical registry token" do
      expect(broker.send(:broker_type)).to eq("presigned_url")
    end
  end
end

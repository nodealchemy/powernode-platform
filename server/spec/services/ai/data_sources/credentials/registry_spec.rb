# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::Registry — resolves the dynamic credential broker
# for a source's configured broker type (data_source.auth_config["broker"]
# ["type"]).
#
# CONTRACT:
#   - .for(token) constantizes (lazily) and instantiates the broker class mapped
#     to the NORMALIZED token (trimmed + downcased).
#   - A blank, nil, or UNKNOWN token resolves to StaticBroker — the generic
#     "no brokering" fallback, mirroring SignerRegistry's NoneSigner fallback so a
#     source with an unrecognized broker type degrades safely instead of raising.
#   - .types lists the registered token keys.
#
# HERMETIC: .for only INSTANTIATES the broker (no #acquire is called here), so no
# AWS/Vault/OAuth/HTTP seam is touched — construction alone reaches nothing
# external. The concrete classes other than StaticBroker are constantized
# on-call (lazy), exactly like SignerRegistry.
RSpec.describe Ai::DataSources::Credentials::Registry, type: :service do
  describe ".for" do
    it "maps 'static' to StaticBroker" do
      expect(described_class.for("static"))
        .to be_an_instance_of(Ai::DataSources::Credentials::StaticBroker)
    end

    it "maps 'oauth2_client_credentials' to Oauth2ClientCredentialsBroker" do
      expect(described_class.for("oauth2_client_credentials"))
        .to be_an_instance_of(Ai::DataSources::Credentials::Oauth2ClientCredentialsBroker)
    end

    it "maps 'oauth2_authorization_code' to Oauth2AuthorizationCodeBroker" do
      expect(described_class.for("oauth2_authorization_code"))
        .to be_an_instance_of(Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker)
    end

    it "maps 'aws_sts' to AwsStsBroker" do
      expect(described_class.for("aws_sts"))
        .to be_an_instance_of(Ai::DataSources::Credentials::AwsStsBroker)
    end

    it "maps 'aws_sts_web_identity' to AwsStsWebIdentityBroker" do
      expect(described_class.for("aws_sts_web_identity"))
        .to be_an_instance_of(Ai::DataSources::Credentials::AwsStsWebIdentityBroker)
    end

    it "maps 'vault_dynamic' to VaultDynamicBroker" do
      expect(described_class.for("vault_dynamic"))
        .to be_an_instance_of(Ai::DataSources::Credentials::VaultDynamicBroker)
    end

    it "maps 'presigned_url' to PresignedUrlBroker" do
      expect(described_class.for("presigned_url"))
        .to be_an_instance_of(Ai::DataSources::Credentials::PresignedUrlBroker)
    end

    it "returns a broker conforming to the CONTRACT (responds to #acquire)" do
      expect(described_class.for("aws_sts")).to respond_to(:acquire)
    end

    it "returns a fresh instance on each call (not a memoized singleton)" do
      first = described_class.for("static")
      second = described_class.for("static")
      expect(first).not_to be(second)
    end

    # ------------------------------------------------------------------------
    # Generic fallback: blank / unknown / nil => StaticBroker
    # ------------------------------------------------------------------------
    describe "generic StaticBroker fallback" do
      it "falls back to StaticBroker for an unknown token" do
        expect(described_class.for("totally_made_up"))
          .to be_an_instance_of(Ai::DataSources::Credentials::StaticBroker)
      end

      it "falls back to StaticBroker for an empty string" do
        expect(described_class.for(""))
          .to be_an_instance_of(Ai::DataSources::Credentials::StaticBroker)
      end

      it "falls back to StaticBroker for a whitespace-only string" do
        expect(described_class.for("   "))
          .to be_an_instance_of(Ai::DataSources::Credentials::StaticBroker)
      end

      it "falls back to StaticBroker for nil" do
        expect(described_class.for(nil))
          .to be_an_instance_of(Ai::DataSources::Credentials::StaticBroker)
      end
    end

    # ------------------------------------------------------------------------
    # Normalization: case-insensitive, whitespace-trimmed, Symbol-tolerant
    # ------------------------------------------------------------------------
    describe "token normalization" do
      it "matches case-insensitively (uppercase)" do
        expect(described_class.for("AWS_STS"))
          .to be_an_instance_of(Ai::DataSources::Credentials::AwsStsBroker)
      end

      it "matches case-insensitively (mixed case)" do
        expect(described_class.for("Oauth2_Client_Credentials"))
          .to be_an_instance_of(Ai::DataSources::Credentials::Oauth2ClientCredentialsBroker)
      end

      it "trims surrounding whitespace before matching" do
        expect(described_class.for("  vault_dynamic  "))
          .to be_an_instance_of(Ai::DataSources::Credentials::VaultDynamicBroker)
      end

      it "accepts a Symbol token" do
        expect(described_class.for(:presigned_url))
          .to be_an_instance_of(Ai::DataSources::Credentials::PresignedUrlBroker)
      end
    end
  end

  describe ".types" do
    it "lists exactly the registered broker type keys" do
      expect(described_class.types).to contain_exactly(
        "static",
        "oauth2_client_credentials",
        "oauth2_authorization_code",
        "aws_sts",
        "aws_sts_web_identity",
        "vault_dynamic",
        "presigned_url"
      )
    end

    it "returns an Array of String tokens" do
      expect(described_class.types).to all(be_a(String))
    end

    it "includes a resolvable broker for every advertised type (round-trips through .for)" do
      described_class.types.each do |token|
        expect(described_class.for(token)).to respond_to(:acquire)
      end
    end
  end
end

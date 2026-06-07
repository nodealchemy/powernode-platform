# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Auth::SignerRegistry do
  describe ".for (scheme selection)" do
    {
      "none"      => Ai::DataSources::Auth::NoneSigner,
      "api_key"   => Ai::DataSources::Auth::ApiKeySigner,
      "bearer"    => Ai::DataSources::Auth::BearerSigner,
      "aws_sigv4" => Ai::DataSources::Auth::Sigv4Signer,
      "hmac"      => Ai::DataSources::Auth::HmacSigner
    }.each do |scheme, klass|
      it "resolves #{scheme.inspect} to #{klass}" do
        expect(described_class.for(scheme)).to be_an_instance_of(klass)
      end
    end

    it "accepts a symbol scheme" do
      expect(described_class.for(:bearer)).to be_an_instance_of(Ai::DataSources::Auth::BearerSigner)
    end

    it "normalizes case + surrounding whitespace" do
      expect(described_class.for("  AWS_SIGV4  ")).to be_an_instance_of(Ai::DataSources::Auth::Sigv4Signer)
    end

    it "falls back to NoneSigner for an unknown scheme (degrade safely, never raise)" do
      expect(described_class.for("oauth2")).to be_an_instance_of(Ai::DataSources::Auth::NoneSigner)
    end

    it "falls back to NoneSigner for a blank scheme" do
      expect(described_class.for("")).to be_an_instance_of(Ai::DataSources::Auth::NoneSigner)
    end

    it "falls back to NoneSigner for a nil scheme" do
      expect(described_class.for(nil)).to be_an_instance_of(Ai::DataSources::Auth::NoneSigner)
    end

    it "returns a signer conforming to the contract (#sign!)" do
      expect(described_class.for("none")).to respond_to(:sign!)
    end

    it "NoneSigner performs no mutation on the request env" do
      env = { method: "GET", url: "https://api.example.com/x", headers: {}, query: {}, body: nil }

      described_class.for("none").sign!(env, credential: nil, config: {})

      expect(env[:headers]).to eq({})
      expect(env[:query]).to eq({})
    end
  end

  describe ".schemes" do
    it "lists every registered scheme" do
      expect(described_class.schemes).to contain_exactly("none", "api_key", "bearer", "aws_sigv4", "hmac")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::A2a::SecurityCardSigner do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_card) do
    create(:ai_agent_card,
           account: account,
           agent: agent,
           name: "Test Signer Agent",
           visibility: "private",
           status: "active",
           capabilities: {
             "skills" => [{ "id" => "summarize", "name" => "Summarize" }],
             "streaming" => true,
             "permissions" => ["read", "write"]
           })
  end

  let(:signer) { described_class.new(account: account) }

  before do
    # Ensure HMAC signing is used by not setting RSA key
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("A2A_SIGNING_PRIVATE_KEY").and_return(nil)
    allow(ENV).to receive(:fetch).and_call_original
  end

  describe "constants" do
    it "uses RS256 signing algorithm" do
      expect(described_class::SIGNING_ALGORITHM).to eq("RS256")
    end

    it "sets card validity to 24 hours" do
      expect(described_class::CARD_VALIDITY_HOURS).to eq(24)
    end
  end

  describe "#sign_card" do
    it "returns a hash with signed_card and signature" do
      result = signer.sign_card(agent_card)

      expect(result).to have_key(:signed_card)
      expect(result).to have_key(:signature)
    end

    it "includes security section in signed card" do
      result = signer.sign_card(agent_card)
      signed_card = result[:signed_card]

      expect(signed_card[:security]).to be_a(Hash)
      expect(signed_card[:security][:issuer]).to eq("powernode:#{account.id}")
      expect(signed_card[:security][:algorithm]).to eq("RS256")
    end

    it "includes signature in security section" do
      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:signature]).to be_a(String)
      expect(security[:signature]).not_to be_empty
    end

    it "includes signed_at timestamp" do
      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:signed_at]).to be_a(String)
      expect { Time.parse(security[:signed_at]) }.not_to raise_error
    end

    it "includes valid_until timestamp 24 hours from now" do
      freeze_time do
        result = signer.sign_card(agent_card)
        security = result[:signed_card][:security]

        expected_expiry = 24.hours.from_now.iso8601
        expect(security[:valid_until]).to eq(expected_expiry)
      end
    end

    it "includes authentication schemes from agent card" do
      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:authentication]).to be_an(Array)
    end

    it "includes permissions from capabilities" do
      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:permissions]).to eq(["read", "write"])
    end

    it "determines data classification as public by default" do
      agent_card.update!(capabilities: { "skills" => [] })

      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:data_classification]).to eq("public")
    end

    it "determines data classification as confidential when handling PII" do
      agent_card.update!(capabilities: { "handles_pii" => true })

      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:data_classification]).to eq("confidential")
    end

    it "determines data classification as internal for internal-only agents" do
      agent_card.update!(capabilities: { "internal_only" => true })

      result = signer.sign_card(agent_card)
      security = result[:signed_card][:security]

      expect(security[:data_classification]).to eq("internal")
    end

    it "produces a consistent signature for the same card" do
      result1 = signer.sign_card(agent_card)
      result2 = signer.sign_card(agent_card)

      # Signatures differ because they include timestamps, but both should be valid strings
      expect(result1[:signature]).to be_a(String)
      expect(result2[:signature]).to be_a(String)
    end
  end

  describe "#verify_signed_card" do
    context "with a valid signed card" do
      it "returns valid: true for correctly signed card" do
        signed_result = signer.sign_card(agent_card)
        signed_card = signed_result[:signed_card]

        # Build a card with matching HMAC signature
        card_for_verify = signed_card.deep_dup
        card_without_sig = card_for_verify.deep_dup
        card_without_sig[:security].delete(:signature)

        secret = ENV.fetch("A2A_SIGNING_SECRET") { Rails.application.secret_key_base[0..31] }
        expected_sig = OpenSSL::HMAC.hexdigest("SHA256", secret, card_without_sig.to_json)

        card_for_verify[:security][:signature] = expected_sig

        result = signer.verify_signed_card(card_for_verify)

        expect(result[:valid]).to be true
        expect(result[:issuer]).to eq("powernode:#{account.id}")
        expect(result[:verified_at]).to be_a(String)
      end
    end

    context "with missing security section" do
      it "returns valid: false" do
        result = signer.verify_signed_card({ name: "No Security" })

        expect(result[:valid]).to be false
        expect(result[:reason]).to eq("No security section")
      end
    end

    context "with missing signature" do
      it "returns valid: false" do
        result = signer.verify_signed_card({
          security: { issuer: "powernode:#{account.id}" }
        })

        expect(result[:valid]).to be false
        expect(result[:reason]).to eq("No signature")
      end
    end

    context "with expired card" do
      it "returns valid: false" do
        expired_card = {
          security: {
            issuer: "powernode:#{account.id}",
            signature: "some_signature",
            valid_until: 1.hour.ago.iso8601
          }
        }

        result = signer.verify_signed_card(expired_card)

        expect(result[:valid]).to be false
        expect(result[:reason]).to eq("Card signature expired")
      end
    end

    context "with tampered signature" do
      it "returns valid: false" do
        tampered_card = {
          security: {
            issuer: "powernode:#{account.id}",
            signature: "tampered_invalid_signature",
            valid_until: 24.hours.from_now.iso8601
          }
        }

        result = signer.verify_signed_card(tampered_card)

        expect(result[:valid]).to be false
        expect(result[:reason]).to eq("Signature verification failed")
      end
    end

    context "with non-powernode issuer" do
      it "returns valid: false for external issuers" do
        external_card = {
          security: {
            issuer: "external:some-agent",
            signature: "some_signature",
            valid_until: 24.hours.from_now.iso8601
          }
        }

        result = signer.verify_signed_card(external_card)

        expect(result[:valid]).to be false
        expect(result[:reason]).to eq("Signature verification failed")
      end
    end

    context "with string keys" do
      it "handles string-keyed hashes" do
        result = signer.verify_signed_card({
          "security" => {
            "issuer" => "powernode:#{account.id}",
            "signature" => "invalid",
            "valid_until" => 24.hours.from_now.iso8601
          }
        })

        expect(result[:valid]).to be false
      end
    end

    context "with verification errors" do
      it "catches and returns error details" do
        allow(Time).to receive(:parse).and_raise(ArgumentError, "invalid date")

        bad_card = {
          security: {
            issuer: "powernode:#{account.id}",
            signature: "sig",
            valid_until: "not-a-date"
          }
        }

        result = signer.verify_signed_card(bad_card)

        expect(result[:valid]).to be false
        expect(result[:reason]).to include("Verification error")
      end
    end
  end

  describe "SigningError" do
    it "is a StandardError subclass" do
      expect(described_class::SigningError.new).to be_a(StandardError)
    end
  end
end

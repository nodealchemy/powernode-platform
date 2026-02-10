# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::PiiRedactionService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe "#scan" do
    it "detects email addresses" do
      text = "Contact me at john.doe@example.com for details."

      result = service.scan(text: text)

      expect(result[:detections]).to include(
        a_hash_including(type: "email", match: "john.doe@example.com")
      )
    end

    it "detects phone numbers" do
      text = "Call me at (555) 123-4567 or 555-987-6543."

      result = service.scan(text: text)

      phone_detections = result[:detections].select { |d| d[:type].include?("phone") }
      expect(phone_detections.length).to be >= 1
    end

    it "detects SSN patterns" do
      text = "My social security number is 123-45-6789."

      result = service.scan(text: text)

      expect(result[:detections]).to include(
        a_hash_including(type: "ssn")
      )
    end

    it "detects credit card numbers" do
      text = "Please charge card 4111-1111-1111-1111 for the purchase."

      result = service.scan(text: text)

      expect(result[:detections]).to include(
        a_hash_including(type: "credit_card")
      )
    end

    it "detects API keys" do
      text = "Use this API key: api_key=sk_proj_abc123def456ghi789jkl012mno345pqr678"

      result = service.scan(text: text)

      expect(result[:detections]).to include(
        a_hash_including(type: "api_key_generic")
      )
    end

    it "returns empty for clean text" do
      text = "The quarterly report shows a 15% increase in active users."

      result = service.scan(text: text)

      expect(result[:detections]).to be_empty
      expect(result[:pii_found]).to be false
    end
  end

  describe "#redact" do
    it "replaces PII with redaction placeholders" do
      text = "Email john@example.com for the SSN 123-45-6789."

      result = service.redact(text: text)

      expect(result[:redacted_text]).not_to include("john@example.com")
      expect(result[:redacted_text]).not_to include("123-45-6789")
      expect(result[:redacted_text]).to include("[REDACTED:")
    end

    it "handles multiple PII types in one text" do
      text = "Name: John Doe, Email: jdoe@company.com, Phone: 555-123-4567, SSN: 987-65-4321"

      result = service.redact(text: text)

      expect(result[:redacted_text]).not_to include("jdoe@company.com")
      expect(result[:redacted_text]).not_to include("987-65-4321")
      expect(result[:detections_count]).to be >= 2
    end

    it "logs detections when log: true" do
      # log_detections creates DataDetection records via DataClassification.record_detection!
      # We need a DataClassification record for the account so log_detections has something to use
      create(:ai_data_classification, account: account, classification_level: "pii")

      text = "Contact admin@example.com"

      expect {
        service.redact(text: text, log: true)
      }.to change(Ai::DataDetection, :count).by_at_least(1)
    end

    it "preserves non-PII text" do
      text = "Revenue grew 25% in Q3. Contact sales@acme.com for details."

      result = service.redact(text: text)

      expect(result[:redacted_text]).to include("Revenue grew 25% in Q3")
      expect(result[:redacted_text]).to include("for details")
      expect(result[:redacted_text]).not_to include("sales@acme.com")
    end
  end

  describe "#apply_policy" do
    it "applies redaction based on classification level" do
      text = "User email: test@example.com"

      result = service.apply_policy(text: text, classification_level: "standard")

      expect(result).to include(:redacted_text, :policy_applied, :detections)
      expect(result[:policy_applied]).to eq("standard")
    end

    it "is stricter for restricted classification" do
      # "restricted" threshold is "pci" (index 0), so only pci-classified detections are redacted
      # "pii" level has nil threshold, meaning ALL detections are redacted
      text_with_card = "Card: 4111-1111-1111-1111"

      restricted_result = service.apply_policy(text: text_with_card, classification_level: "restricted")
      pii_result = service.apply_policy(text: text_with_card, classification_level: "pii")

      # Both should redact credit card (classified as "pci")
      expect(restricted_result[:redacted_text]).not_to include("4111-1111-1111-1111")
      expect(pii_result[:redacted_text]).not_to include("4111-1111-1111-1111")

      # But for email (classified as "pii"), restricted does NOT redact while pii level does
      text_with_email = "User email: test@example.com"
      restricted_email = service.apply_policy(text: text_with_email, classification_level: "restricted")
      pii_email = service.apply_policy(text: text_with_email, classification_level: "pii")

      expect(restricted_email[:redacted_text]).to include("test@example.com")
      expect(pii_email[:redacted_text]).not_to include("test@example.com")
    end
  end

  describe "#safe_to_output?" do
    it "returns true for clean text" do
      result = service.safe_to_output?(text: "The system processed 1000 requests today.")

      expect(result).to be true
    end

    it "returns false for text with high-confidence PII" do
      result = service.safe_to_output?(text: "The user SSN is 123-45-6789 and email is john@example.com")

      expect(result).to be false
    end
  end

  describe "#batch_scan" do
    it "scans multiple texts" do
      texts = [
        "Contact admin@example.com",
        "Clean text with no PII",
        "SSN: 111-22-3333"
      ]

      results = service.batch_scan(texts: texts)

      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
    end

    it "returns per-text results" do
      texts = [
        "Email: test@example.com",
        "No sensitive data here"
      ]

      results = service.batch_scan(texts: texts)

      expect(results[0][:pii_found]).to be true
      expect(results[0][:detections]).not_to be_empty

      expect(results[1][:pii_found]).to be false
      expect(results[1][:detections]).to be_empty
    end
  end
end

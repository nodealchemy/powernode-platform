# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataManagement::Sanitizer do
  # G15: secret scrubbing of (autonomous-loop) output before it is persisted/displayed.
  describe ".scrub_secrets" do
    it "redacts key/secret/token assignments while keeping the key name" do
      expect(described_class.scrub_secrets('api_key: "sk-abc123def456ghi789"')).to match(/api_key:.*\[REDACTED\]/i)
      expect(described_class.scrub_secrets("client_secret=supersecretvalue")).to match(/client_secret=\[REDACTED\]/i)
    end

    it "redacts PEM private key blocks" do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEoabc123\n-----END RSA PRIVATE KEY-----"
      expect(described_class.scrub_secrets(pem)).to eq("[REDACTED_PRIVATE_KEY]")
    end

    it "redacts Authorization bearer tokens" do
      expect(described_class.scrub_secrets("Authorization: Bearer abc.def.ghi")).to match(/Bearer \[REDACTED\]/)
    end

    it "redacts common vendor token formats" do
      expect(described_class.scrub_secrets("use ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345 now")).to include("[REDACTED_TOKEN]")
      expect(described_class.scrub_secrets("aws AKIAIOSFODNN7EXAMPLE key")).to include("[REDACTED_AWS_KEY]")
    end

    it "redacts JWTs" do
      jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
      expect(described_class.scrub_secrets("token was #{jwt} ok")).to include("[REDACTED_JWT]")
    end

    it "redacts ENV-style SECRET/TOKEN/PASSWORD assignments" do
      expect(described_class.scrub_secrets("DATABASE_PASSWORD=hunter2value")).to match(/DATABASE_PASSWORD=\[REDACTED\]/)
    end

    it "leaves ordinary loop output untouched" do
      text = "Refactored the parser and added 3 tests; all green. tokens: 1500"
      expect(described_class.scrub_secrets(text)).to eq(text)
    end

    it "is a no-op on non-strings" do
      expect(described_class.scrub_secrets(nil)).to be_nil
      expect(described_class.scrub_secrets(42)).to eq(42)
    end
  end

  # G4: secret DETECTION (returns findings) used by the land security gate.
  describe ".secret_findings" do
    it "returns a finding for a leaked credential assignment" do
      findings = described_class.secret_findings('api_key: "sk-abc123def456ghi789"')
      expect(findings).not_to be_empty
      expect(findings.map { |f| f[:category] }).to include("credential").or include("token")
    end

    it "labels a PEM private key block as private_key" do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEoabc123\n-----END RSA PRIVATE KEY-----"
      expect(described_class.secret_findings(pem)).to include(a_hash_including(category: "private_key"))
    end

    it "never echoes the raw secret value in a finding" do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEoSECRETMATERIAL\n-----END RSA PRIVATE KEY-----"
      expect(described_class.secret_findings(pem).to_s).not_to include("SECRETMATERIAL")
    end

    it "returns [] for clean text" do
      expect(described_class.secret_findings("Refactored the parser; all green.")).to eq([])
    end

    it "is a no-op (empty) on non-strings" do
      expect(described_class.secret_findings(nil)).to eq([])
      expect(described_class.secret_findings(42)).to eq([])
    end
  end

  describe ".sanitize_output" do
    it "applies BOTH PCI sanitization and secret scrubbing" do
      out = described_class.sanitize_output("card 4111111111111111 and api_key=sk-secretvalue123")
      expect(out).not_to include("4111111111111111")
      expect(out).to match(/api_key=\[REDACTED\]/i)
    end

    it "passes non-strings straight through" do
      expect(described_class.sanitize_output(nil)).to be_nil
    end
  end
end

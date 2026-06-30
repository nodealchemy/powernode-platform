# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/devops/secret_scanner"

RSpec.describe Devops::SecretScanner do
  def diff(added: [], removed: [], context: [])
    lines = ["diff --git a/config.rb b/config.rb", "--- a/config.rb", "+++ b/config.rb", "@@ -1,3 +1,4 @@"]
    context.each { |l| lines << " #{l}" }
    removed.each { |l| lines << "-#{l}" }
    added.each { |l| lines << "+#{l}" }
    lines.join("\n")
  end

  describe ".findings" do
    it "flags a secret planted on an ADDED diff line as a blocking finding" do
      text = diff(added: ['api_key = "sk-ABCDEF1234567890ABCDEF"'])
      findings = described_class.findings(text)

      expect(findings).not_to be_empty
      expect(findings.first[:scanner]).to eq(described_class::SCANNER_NAME)
      expect(findings.first[:severity]).to eq("critical")
    end

    it "returns no findings for a clean diff" do
      text = diff(added: ["def add(a, b)", "  a + b", "end"])
      expect(described_class.findings(text)).to eq([])
    end

    it "ignores a secret that is only REMOVED (not introduced by the change)" do
      text = diff(removed: ['password = "hunter2supersecret"'])
      expect(described_class.findings(text)).to eq([])
    end

    it "ignores a secret that only appears in unchanged CONTEXT lines" do
      text = diff(context: ['token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"'], added: ["x = 1"])
      expect(described_class.findings(text)).to eq([])
    end

    it "NEVER echoes the raw secret value in a finding (only a category label)" do
      secret = "sk-SUPERSECRETVALUE1234567890"
      text = diff(added: ["api_key = \"#{secret}\""])

      serialized = described_class.findings(text).to_json
      expect(serialized).not_to include(secret)
      expect(serialized).not_to include("SUPERSECRETVALUE")
    end

    it "detects a multi-line PEM private key block across added lines" do
      pem = [
        "-----BEGIN RSA PRIVATE KEY-----",
        "MIIEowIBAAKCAQEAabcdefghijklmnop",
        "-----END RSA PRIVATE KEY-----"
      ]
      text = diff(added: pem)
      findings = described_class.findings(text)
      expect(findings).not_to be_empty
      expect(findings.map { |f| f[:detail] }.join).to include("private_key")
    end

    it "returns [] for blank input" do
      expect(described_class.findings("")).to eq([])
      expect(described_class.findings(nil)).to eq([])
    end
  end
end

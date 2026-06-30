# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::SecurityGateService do
  before { Ai::Land::SecurityScannerRegistry.reset! }
  after { Ai::Land::SecurityScannerRegistry.reset! }

  let(:secret_content) { 'config: api_key="sk-abcdef0123456789ABCDEF"' }

  describe "core secret-scan (no handlers registered)" do
    it "blocks when content carries a secret" do
      result = described_class.evaluate(contents: [ secret_content ])

      expect(result[:blocked]).to be(true)
      expect(result[:findings]).to include(a_hash_including(scanner: "core_secret_scan", severity: "critical"))
      expect(result[:scanners]).to eq([])
    end

    it "allows clean content" do
      result = described_class.evaluate(contents: [ "added two specs; all green" ])
      expect(result[:blocked]).to be(false)
      expect(result[:findings]).to eq([])
    end

    it "never includes the raw secret in the findings" do
      result = described_class.evaluate(contents: [ secret_content ])
      expect(result[:findings].to_s).not_to include("sk-abcdef0123456789ABCDEF")
    end
  end

  describe "external scanner handlers" do
    it "blocks on a registered high-severity finding even with clean content" do
      Ai::Land::SecurityScannerRegistry.register(:sast) do |_ctx|
        [ { scanner: "sast", severity: "high", detail: "SQL injection" } ]
      end

      result = described_class.evaluate(contents: [ "clean change" ])
      expect(result[:blocked]).to be(true)
      expect(result[:findings]).to include(a_hash_including(scanner: "sast", severity: "high"))
      expect(result[:scanners]).to eq([ :sast ])
    end

    it "does not block on a low-severity finding" do
      Ai::Land::SecurityScannerRegistry.register(:cve) do |_ctx|
        [ { scanner: "cve", severity: "low", detail: "minor advisory" } ]
      end

      result = described_class.evaluate(contents: [ "clean change" ])
      expect(result[:blocked]).to be(false)
      expect(result[:findings].size).to eq(1)
    end

    it "aggregates findings across multiple handlers + the core scan" do
      Ai::Land::SecurityScannerRegistry.register(:sast) { |_| [ { severity: "medium", detail: "a" } ] }
      Ai::Land::SecurityScannerRegistry.register(:cve)  { |_| [ { severity: "high", detail: "b" } ] }

      result = described_class.evaluate(contents: [ secret_content ])
      scanners = result[:findings].map { |f| f[:scanner] }
      expect(scanners).to include("core_secret_scan", "sast", "cve")
      expect(result[:blocked]).to be(true) # secret + high CVE
    end

    it "fails closed (blocks) when a handler raises" do
      Ai::Land::SecurityScannerRegistry.register(:flaky) { |_| raise "boom" }
      result = described_class.evaluate(contents: [ "clean change" ])

      expect(result[:blocked]).to be(true)
      expect(result[:findings]).to include(a_hash_including(scanner: "flaky", severity: "high"))
    end

    it "passes the change context to the handler" do
      captured = nil
      Ai::Land::SecurityScannerRegistry.register(:probe) do |ctx|
        captured = ctx
        []
      end
      described_class.evaluate(changed_files: [ "app/x.rb" ], contents: [ "hi" ])
      expect(captured[:changed_files]).to eq([ "app/x.rb" ])
      expect(captured[:contents]).to eq([ "hi" ])
    end
  end

  describe "scanned_content flag (server-side diff limitation)" do
    it "is true when explicit change content is provided" do
      expect(described_class.evaluate(contents: [ "x" ])[:scanned_content]).to be(true)
    end

    it "is false when only paths are available (no diff content)" do
      expect(described_class.evaluate(changed_files: [ "a.rb" ])[:scanned_content]).to be(false)
    end
  end
end

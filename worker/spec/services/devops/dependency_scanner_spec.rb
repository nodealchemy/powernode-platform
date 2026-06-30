# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/devops/dependency_scanner"

# Generic best-effort dependency-CVE scan over a checked-out repo (G4 worker
# depth), composed into the land security-scan job alongside the secret scanner
# and Brakeman. The command runner is stubbed with canned tool output — no tool
# is actually invoked and no network call is made.
RSpec.describe Devops::DependencyScanner do
  # Maps a command substring to a canned `{ exit_code:, output:, error: }` result;
  # any command not matched returns the tool-absent shape (exit 127), so a test
  # only needs to provide output for the ecosystem(s) it exercises.
  def runner_for(outputs)
    lambda do |command|
      key = outputs.keys.find { |substring| command.include?(substring) }
      key ? outputs[key] : { exit_code: 127, output: "#{command.split.first}: command not found", error: nil }
    end
  end

  let(:bundler_audit_json) do
    {
      "version" => "0.9.1",
      "results" => [
        { "type" => "unpatched_gem", "gem" => { "name" => "nokogiri", "version" => "1.10.0" },
          "advisory" => { "id" => "CVE-2222-0001", "criticality" => "high", "title" => "XXE in Nokogiri" } },
        { "type" => "unpatched_gem", "gem" => { "name" => "rack", "version" => "2.0.0" },
          "advisory" => { "id" => "CVE-2222-0002", "criticality" => "low", "title" => "minor rack issue" } },
        { "type" => "insecure_source", "source" => "http://insecure.example/gems" }
      ]
    }.to_json
  end

  let(:npm_audit_json) do
    {
      "auditReportVersion" => 2,
      "vulnerabilities" => {
        "lodash" => { "name" => "lodash", "severity" => "critical",
                      "via" => [ { "title" => "Prototype Pollution", "url" => "https://example/adv/1", "severity" => "critical" } ] },
        "minimist" => { "name" => "minimist", "severity" => "moderate",
                        "via" => [ { "title" => "ReDoS" } ] }
      }
    }.to_json
  end

  let(:pip_audit_json) do
    {
      "dependencies" => [
        { "name" => "flask", "version" => "0.5",
          "vulns" => [ { "id" => "PYSEC-2019-179", "aliases" => [ "CVE-2019-1010083" ] } ] },
        { "name" => "safe-lib", "version" => "1.0", "vulns" => [] }
      ]
    }.to_json
  end

  describe ".scan" do
    it "reports a HIGH bundler-audit advisory with the package and advisory id in the detail" do
      findings = described_class.scan("/ws", runner: runner_for("bundle-audit" => { exit_code: 1, output: bundler_audit_json, error: nil }))

      expect(findings.size).to eq(1)
      finding = findings.first
      expect(finding[:scanner]).to eq("dependency-cve")
      expect(finding[:severity]).to eq("high")
      expect(finding[:detail]).to include("nokogiri").and include("CVE-2222-0001")
    end

    it "omits below-HIGH bundler-audit advisories and non-advisory results" do
      findings = described_class.scan("/ws", runner: runner_for("bundle-audit" => { exit_code: 1, output: bundler_audit_json, error: nil }))

      details = findings.map { |f| f[:detail] }.join
      expect(details).not_to include("rack")          # low severity → omitted
      expect(details).not_to include("insecure")      # insecure_source → no advisory
    end

    it "reports a CRITICAL npm advisory and omits MODERATE ones (moderate is not high/critical)" do
      findings = described_class.scan("/ws", runner: runner_for("npm audit" => { exit_code: 1, output: npm_audit_json, error: nil }))

      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("critical")
      expect(findings.first[:detail]).to include("lodash").and include("Prototype Pollution")
      expect(findings.map { |f| f[:detail] }.join).not_to include("minimist")
    end

    it "treats a confirmed pip-audit advisory as a blocking HIGH (fail-safe; pip-audit emits no severity)" do
      findings = described_class.scan("/ws", runner: runner_for("pip-audit" => { exit_code: 1, output: pip_audit_json, error: nil }))

      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
      expect(findings.first[:detail]).to include("flask").and include("PYSEC-2019-179")
    end

    it "aggregates findings across every ecosystem in one scan" do
      findings = described_class.scan(
        "/ws",
        runner: runner_for(
          "bundle-audit" => { exit_code: 1, output: bundler_audit_json, error: nil },
          "npm audit"    => { exit_code: 1, output: npm_audit_json, error: nil },
          "pip-audit"    => { exit_code: 1, output: pip_audit_json, error: nil }
        )
      )

      expect(findings.size).to eq(3)
      expect(findings.map { |f| f[:scanner] }.uniq).to eq([ "dependency-cve" ])
    end

    it "returns no findings for a clean dependency tree" do
      findings = described_class.scan("/ws", runner: runner_for("bundle-audit" => { exit_code: 0, output: { "results" => [] }.to_json, error: nil }))
      expect(findings).to eq([])
    end

    it "skips an ecosystem cleanly when the tool is absent (no error, no finding)" do
      # Every command falls through to the tool-absent (exit 127) default.
      expect { described_class.scan("/ws", runner: runner_for({})) }.not_to raise_error
      expect(described_class.scan("/ws", runner: runner_for({}))).to eq([])
    end

    it "skips an ecosystem cleanly when the tool emits non-JSON / garbage output" do
      findings = described_class.scan("/ws", runner: runner_for("bundle-audit" => { exit_code: 1, output: "could not load advisory db\n", error: nil }))
      expect(findings).to eq([])
    end

    it "never surfaces raw tool output (e.g. an advisory description) that could carry a secret" do
      token = "ghp_SECRETTOKEN0000000000000000000000"
      poisoned = {
        "results" => [
          { "type" => "unpatched_gem", "gem" => { "name" => "x" },
            "advisory" => { "id" => "CVE-1", "criticality" => "high", "title" => "t",
                            "description" => "leaked credential #{token} do not echo" } }
        ]
      }.to_json

      findings = described_class.scan("/ws", runner: runner_for("bundle-audit" => { exit_code: 1, output: poisoned, error: nil }))
      expect(findings.to_json).not_to include(token)
      expect(findings.to_json).not_to include("leaked credential")
    end

    it "supports the npm 6 'advisories' output shape as a fallback" do
      npm6 = {
        "advisories" => {
          "118" => { "module_name" => "handlebars", "severity" => "high", "title" => "Prototype Pollution", "id" => 118 }
        }
      }.to_json

      findings = described_class.scan("/ws", runner: runner_for("npm audit" => { exit_code: 1, output: npm6, error: nil }))
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
      expect(findings.first[:detail]).to include("handlebars")
    end

    it "supports the older pip-audit top-level-array output shape" do
      legacy = [ { "name" => "jinja2", "version" => "2.0", "vulns" => [ { "id" => "PYSEC-2020-1" } ] } ].to_json
      findings = described_class.scan("/ws", runner: runner_for("pip-audit" => { exit_code: 1, output: legacy, error: nil }))
      expect(findings.size).to eq(1)
      expect(findings.first[:detail]).to include("jinja2").and include("PYSEC-2020-1")
    end
  end
end

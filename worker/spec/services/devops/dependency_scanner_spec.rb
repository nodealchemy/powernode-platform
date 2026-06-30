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

  # pip-audit severity is sourced from OSV over HTTP. WebMock disallows real net
  # connections, so by default every OSV lookup 404s — which the scanner treats as
  # "no authoritative severity" and falls back to the fail-safe blocking default.
  # Individual examples override this with a more-specific stub (last declared
  # wins) to exercise a real OSV severity.
  before do
    stub_request(:get, /api\.osv\.dev/).to_return(status: 404, body: "{}")
  end

  # OSV `GET /v1/vulns/{id}` body carrying a CVSS v3 vector for the given id.
  def osv_cvss(id, vector, type: "CVSS_V3")
    stub_request(:get, "https://api.osv.dev/v1/vulns/#{id}")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "id" => id, "severity" => [ { "type" => type, "score" => vector } ] }.to_json)
  end

  # OSV body carrying only a textual database_specific severity (GHSA-style rating).
  def osv_db_severity(id, label)
    stub_request(:get, "https://api.osv.dev/v1/vulns/#{id}")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "id" => id, "database_specific" => { "severity" => label } }.to_json)
  end

  # Canonical CVSS v3.1 vectors with their documented base scores / buckets.
  CVSS_CRITICAL = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" # 9.8
  CVSS_HIGH     = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H" # 7.5
  CVSS_MEDIUM   = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N" # 5.3
  CVSS_LOW      = "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:N/A:N" # 3.7

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

  # pip-audit emits NO per-advisory severity, so a confirmed Python advisory was
  # historically blocked fail-safe as HIGH. We now refine that severity DOWNWARD
  # only when OSV authoritatively reports a lower CVSS/GHSA rating; on ANY OSV
  # failure the fail-safe HIGH stands, so the gate is never made less safe on error.
  describe ".scan pip-audit OSV severity sourcing" do
    let(:pip_audit_json) do
      { "dependencies" => [ { "name" => "flask", "version" => "0.5",
                              "vulns" => [ { "id" => "PYSEC-2019-179", "aliases" => [ "CVE-2019-1010083" ] } ] } ] }.to_json
    end

    def scan_pip
      described_class.scan("/ws", runner: runner_for("pip-audit" => { exit_code: 1, output: pip_audit_json, error: nil }))
    end

    it "omits a Python advisory whose OSV CVSS resolves to MEDIUM (no longer a fail-safe HIGH block)" do
      osv_cvss("PYSEC-2019-179", CVSS_MEDIUM)
      expect(scan_pip).to eq([]) # medium is below high/critical → not a blocking finding
    end

    it "omits a Python advisory whose OSV CVSS resolves to LOW" do
      osv_cvss("PYSEC-2019-179", CVSS_LOW)
      expect(scan_pip).to eq([])
    end

    it "blocks a Python advisory whose OSV CVSS resolves to HIGH (severity carried through)" do
      osv_cvss("PYSEC-2019-179", CVSS_HIGH)
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
      expect(findings.first[:detail]).to include("flask").and include("PYSEC-2019-179")
    end

    it "blocks a Python advisory whose OSV CVSS resolves to CRITICAL (severity sharpened upward)" do
      osv_cvss("PYSEC-2019-179", CVSS_CRITICAL)
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("critical")
    end

    it "honors a textual OSV database_specific severity (GHSA rating) when present" do
      osv_db_severity("PYSEC-2019-179", "MODERATE")
      expect(scan_pip).to eq([]) # MODERATE → medium → omitted
    end

    it "takes the MAX severity across the advisory id and its aliases (never under-blocks on disagreement)" do
      osv_cvss("PYSEC-2019-179", CVSS_MEDIUM)   # primary id under-rates...
      osv_cvss("CVE-2019-1010083", CVSS_CRITICAL) # ...alias is critical → critical wins
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("critical")
    end

    it "takes the MAX across multiple CVSS_V3 vectors within one OSV record" do
      stub_request(:get, "https://api.osv.dev/v1/vulns/PYSEC-2019-179")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { "id" => "PYSEC-2019-179",
                           "severity" => [ { "type" => "CVSS_V3", "score" => CVSS_LOW },
                                           { "type" => "CVSS_V3", "score" => CVSS_CRITICAL } ] }.to_json)
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("critical")
    end

    it "takes the MORE SEVERE of the CVSS vector and the textual database_specific severity" do
      stub_request(:get, "https://api.osv.dev/v1/vulns/PYSEC-2019-179")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { "id" => "PYSEC-2019-179",
                           "severity" => [ { "type" => "CVSS_V3", "score" => CVSS_LOW } ],
                           "database_specific" => { "severity" => "CRITICAL" } }.to_json)
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("critical")
    end

    it "memoizes an OSV lookup so a repeated advisory id is fetched once per scan" do
      pip = { "dependencies" => [
        { "name" => "pkg-a", "vulns" => [ { "id" => "PYSEC-2019-179" } ] },
        { "name" => "pkg-b", "vulns" => [ { "id" => "PYSEC-2019-179" } ] }
      ] }.to_json
      osv_cvss("PYSEC-2019-179", CVSS_CRITICAL)
      findings = described_class.scan("/ws", runner: runner_for("pip-audit" => { exit_code: 1, output: pip, error: nil }))
      expect(findings.size).to eq(2) # both packages reported...
      expect(a_request(:get, "https://api.osv.dev/v1/vulns/PYSEC-2019-179")).to have_been_made.once # ...from one fetch
    end

    it "falls back to the fail-safe HIGH block when the OSV lookup 404s for every id" do
      # default catch-all stub → 404 for PYSEC-2019-179 and CVE-2019-1010083
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
    end

    it "falls back to the fail-safe HIGH block when the OSV lookup times out" do
      stub_request(:get, "https://api.osv.dev/v1/vulns/PYSEC-2019-179").to_timeout
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
    end

    it "falls back to the fail-safe HIGH block when OSV returns a 500" do
      stub_request(:get, "https://api.osv.dev/v1/vulns/PYSEC-2019-179").to_return(status: 500, body: "boom")
      stub_request(:get, "https://api.osv.dev/v1/vulns/CVE-2019-1010083").to_return(status: 500, body: "boom")
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
    end

    it "falls back to the fail-safe HIGH block when OSV returns an unparseable CVSS vector" do
      osv_cvss("PYSEC-2019-179", "not-a-vector")
      stub_request(:get, "https://api.osv.dev/v1/vulns/CVE-2019-1010083").to_return(status: 404, body: "{}")
      findings = scan_pip
      expect(findings.size).to eq(1)
      expect(findings.first[:severity]).to eq("high")
    end

    it "does not surface the advisory id query as a leaked secret in the finding" do
      osv_cvss("PYSEC-2019-179", CVSS_CRITICAL)
      expect(scan_pip.to_json).not_to include("api.osv.dev")
    end
  end

  # The CVSS v3.x base-score computation is the only path that can lower a Python
  # advisory's severity below the blocking threshold, so it is unit-tested directly
  # against canonical vectors to guarantee it never under-scores a real CVSS.
  describe ".cvss_base_label" do
    it "buckets a 9.8 vector as critical" do
      expect(described_class.cvss_base_label(CVSS_CRITICAL)).to eq("critical")
    end

    it "buckets a 7.5 vector as high" do
      expect(described_class.cvss_base_label(CVSS_HIGH)).to eq("high")
    end

    it "buckets a 5.3 vector as medium" do
      expect(described_class.cvss_base_label(CVSS_MEDIUM)).to eq("medium")
    end

    it "buckets a 3.7 vector as low" do
      expect(described_class.cvss_base_label(CVSS_LOW)).to eq("low")
    end

    it "handles a scope-changed vector (e.g. 10.0 critical)" do
      # AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H → 10.0
      expect(described_class.cvss_base_label("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H")).to eq("critical")
    end

    it "returns nil for an incomplete / unparseable vector (caller fails safe)" do
      expect(described_class.cvss_base_label("CVSS:3.1/AV:N/AC:L")).to be_nil
      expect(described_class.cvss_base_label("garbage")).to be_nil
      expect(described_class.cvss_base_label(nil)).to be_nil
    end
  end
end

# frozen_string_literal: true

require "json"

module Devops
  # Worker-side best-effort dependency-CVE scan over a checked-out repo, used by
  # the land security-scan job (G4 worker depth) ALONGSIDE the secret scanner and
  # Brakeman SAST. It runs widely-available, GENERIC dependency auditors against
  # the standard lockfiles/manifests in the workspace and reports HIGH/CRITICAL
  # advisories as blocking findings to the land park-back surface.
  #
  # GENERIC by design: it uses the ecosystem-standard public tools (bundler-audit,
  # npm audit, pip-audit) — NEVER the supply-chain extension. Core/worker must not
  # hard-depend on that extension, so dependency scanning is wired here with stock
  # tooling and stays a clean no-op when a tool or manifest is absent.
  #
  # BEST-EFFORT per ecosystem, exactly like the Brakeman integration: if the tool
  # binary is missing, the manifest/lockfile is absent, or the tool errors / emits
  # unparseable output, that ecosystem is SKIPPED cleanly (no finding, no raised
  # error). A missing CVE tool is NOT a scan-infra failure — only the secret scan
  # and the diff production fail the land closed; THIS layer never fails the scan.
  #
  # Crypto/secret-safe by construction: a finding's `detail` names ONLY the
  # vulnerable package + advisory id/title — never a lockfile value, token, or raw
  # tool output (e.g. an advisory `description`) that could carry a credential.
  #
  # SBOM generation over the checkout is a SEPARATE concern, handled by the sibling
  # Devops::SbomGenerator (CycloneDX inventory) — kept apart because this scanner
  # shells out to ecosystem auditors for FINDINGS, whereas the SBOM parses lockfiles
  # for INVENTORY and never participates in the gate.
  module DependencyScanner
    SCANNER_NAME = "dependency-cve"

    # Only HIGH/CRITICAL advisories block the land. Lower-severity advisories are
    # OMITTED (not reported) so the gate is not drowned in low-signal noise — the
    # land park-back surface is for real, high-stakes findings.
    BLOCKING_SEVERITIES = %w[high critical].freeze

    # Vendor severity vocab → our scale. npm uses "moderate"; bundler-audit and the
    # OSV-backed tools use low/medium/high/critical. Unknown/absent → nil.
    SEVERITY_MAP = {
      "critical" => "critical",
      "high"     => "high",
      "moderate" => "medium",
      "medium"   => "medium",
      "low"      => "low",
      "info"     => "low",
      "none"     => "low"
    }.freeze

    # pip-audit's JSON does not surface a per-advisory severity, so a CONFIRMED
    # Python advisory is treated fail-safe as this severity (blocking) — a real CVE
    # holds the land for human triage. Refining this once a severity source (OSV
    # CVSS) is wired is a follow-up.
    PIP_DEFAULT_SEVERITY = "high"

    # Each ecosystem is a stock, manifest-driven auditor. Running the tool when its
    # manifest/binary is absent simply errors/no-ops, which we skip cleanly — so we
    # need no separate File-existence probe (mirrors how Brakeman is invoked).
    ECOSYSTEMS = [
      { command: "bundle-audit check --format json",          parser: :parse_bundler_audit },
      { command: "npm audit --json --package-lock-only",      parser: :parse_npm_audit },
      { command: "pip-audit -r requirements.txt -f json",     parser: :parse_pip_audit }
    ].freeze

    module_function

    # Run every available ecosystem auditor over the workspace and return the
    # aggregated HIGH/CRITICAL findings: [{ scanner:, severity:, detail: }].
    #
    # `runner` is a callable `->(command) { { exit_code:, output:, error: } }` (the
    # job passes a closure over DevopsWorkspaceSteps#run_workspace_command) so this
    # service stays decoupled from the job's checkout/run plumbing and is trivially
    # stubbable in tests with canned tool output.
    def scan(_workspace, runner:)
      ECOSYSTEMS.flat_map { |eco| scan_ecosystem(eco, runner) }
    end

    def scan_ecosystem(eco, runner)
      run = runner.call(eco[:command]) || {}
      output = run[:output].to_s
      return [] if output.strip.empty?

      Array(send(eco[:parser], output))
    rescue StandardError
      # Tool absent, manifest absent, non-JSON output, or an unexpected parser
      # error: skip this ecosystem cleanly. Best-effort — never fails the scan.
      []
    end

    # bundler-audit `check --format json`:
    #   { "results": [ { "type": "unpatched_gem",
    #                    "gem": { "name": ... },
    #                    "advisory": { "id": ..., "criticality": ..., "title": ... } }, ... ] }
    # Non-advisory results (e.g. "insecure_source") carry no criticality → skipped.
    def parse_bundler_audit(output)
      report = JSON.parse(output)
      results = report.is_a?(Hash) ? Array(report["results"]) : Array(report)
      results.filter_map do |result|
        advisory = result["advisory"] || {}
        severity = normalize(advisory["criticality"])
        next unless blocking?(severity)

        gem = result["gem"] || {}
        finding(severity, gem["name"], advisory["id"] || advisory["title"])
      end
    end

    # npm `audit --json` (auditReportVersion 2, npm 7+):
    #   { "vulnerabilities": { "<pkg>": { "name":, "severity":, "via": [ { "title":, "url": } ] } } }
    # Falls back to the npm 6 `advisories` shape.
    def parse_npm_audit(output)
      report = JSON.parse(output)
      vulns = report["vulnerabilities"]
      return parse_npm_advisories(report) unless vulns.is_a?(Hash)

      vulns.filter_map do |name, info|
        info ||= {}
        severity = normalize(info["severity"])
        next unless blocking?(severity)

        finding(severity, info["name"] || name, npm_advisory_label(info))
      end
    end

    # npm 6 `audit --json`: { "advisories": { "<id>": { "module_name":, "severity":, "title": } } }
    def parse_npm_advisories(report)
      advisories = report["advisories"]
      return [] unless advisories.is_a?(Hash)

      advisories.values.filter_map do |advisory|
        advisory ||= {}
        severity = normalize(advisory["severity"])
        next unless blocking?(severity)

        finding(severity, advisory["module_name"], advisory["title"] || advisory["id"]&.to_s)
      end
    end

    # pip-audit `-f json`: newer `{ "dependencies": [ { "name":, "vulns": [ { "id":, "aliases": } ] } ] }`,
    # older a top-level array of the same dependency objects.
    def parse_pip_audit(output)
      report = JSON.parse(output)
      deps = report.is_a?(Hash) ? Array(report["dependencies"]) : Array(report)
      deps.flat_map do |dep|
        dep ||= {}
        Array(dep["vulns"]).filter_map do |vuln|
          vuln ||= {}
          severity = normalize(vuln["severity"]) || PIP_DEFAULT_SEVERITY
          next unless blocking?(severity)

          finding(severity, dep["name"], pip_advisory_id(vuln))
        end
      end
    end

    def npm_advisory_label(info)
      via = Array(info["via"]).find { |entry| entry.is_a?(Hash) }
      return nil unless via

      via["title"] || via["url"] || via["source"]&.to_s
    end

    def pip_advisory_id(vuln)
      vuln["id"] || Array(vuln["aliases"]).first
    end

    def normalize(vendor_severity)
      return nil if vendor_severity.nil?

      SEVERITY_MAP[vendor_severity.to_s.strip.downcase]
    end

    def blocking?(severity)
      BLOCKING_SEVERITIES.include?(severity)
    end

    # detail names ONLY the package + advisory id/title — never raw tool output.
    def finding(severity, package, advisory)
      parts = [ package, advisory ].map { |part| part.to_s.strip }.reject(&:empty?)
      label = parts.empty? ? "unknown" : parts.join(" — ")
      { scanner: SCANNER_NAME, severity: severity, detail: "vulnerable dependency: #{label}" }
    end
  end
end

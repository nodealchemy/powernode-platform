# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

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

    # Ordering over our severity vocab, used to pick the HIGHER of two ratings when
    # authoritative sources disagree — so the gate never under-blocks on conflict.
    SEVERITY_RANK = { "low" => 1, "medium" => 2, "high" => 3, "critical" => 4 }.freeze

    # pip-audit's JSON does not surface a per-advisory severity, so a CONFIRMED
    # Python advisory is treated fail-safe as this severity (blocking) UNLESS OSV
    # authoritatively reports a real CVSS/GHSA rating for it (see #pip_severity).
    # This is the SAFE default: a real CVE holds the land for human triage whenever
    # an authoritative severity can't be sourced (OSV down/timeout/unknown id).
    PIP_DEFAULT_SEVERITY = "high"

    # OSV public vulnerability API (https://osv.dev) — unauthenticated per-advisory
    # lookup used to source a REAL severity for pip-audit Python advisories, which
    # pip-audit itself omits. Best-effort and fail-safe: a short timeout, and ANY
    # failure (network error, timeout, non-2xx, unparseable body, unknown severity)
    # falls back to PIP_DEFAULT_SEVERITY so the gate is NEVER made less safe on error.
    OSV_VULN_ENDPOINT = "https://api.osv.dev/v1/vulns"
    OSV_TIMEOUT_SECONDS = 4
    # Cap the per-advisory OSV calls (primary id + a few aliases) so a noisy
    # advisory can't fan out into an unbounded request burst.
    OSV_MAX_LOOKUPS = 4

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
      # One per-scan memo of OSV id → severity so a CVE shared by several packages
      # (and a recurring alias) is fetched at most once, bounding both duplicate
      # work and the worst-case latency when OSV is slow/unreachable.
      osv_cache = {}
      deps.flat_map do |dep|
        dep ||= {}
        Array(dep["vulns"]).filter_map do |vuln|
          vuln ||= {}
          severity = pip_severity(vuln, osv_cache)
          next unless blocking?(severity)

          finding(severity, dep["name"], pip_advisory_id(vuln))
        end
      end
    end

    # Resolve a pip-audit advisory's severity. pip-audit's own JSON carries none,
    # so we source it AUTHORITATIVELY from OSV (CVSS base score, else GHSA rating)
    # keyed by the advisory id and its aliases. We honor an OSV rating ONLY when it
    # is recognized — refining the severity DOWNWARD (so a genuinely low/moderate
    # Python advisory no longer over-blocks) as well as upward. On ANY lookup
    # failure/timeout/parse-error we fall back to the fail-safe blocking default,
    # so the gate is never made less safe when OSV is unavailable.
    def pip_severity(vuln, osv_cache)
      osv_severity(pip_advisory_ids(vuln), osv_cache) || PIP_DEFAULT_SEVERITY
    end

    # The advisory id plus its aliases, de-duped and bounded — OSV is keyed by id,
    # and a PYSEC id often lacks a severity its CVE/GHSA alias carries.
    def pip_advisory_ids(vuln)
      [ vuln["id"], *Array(vuln["aliases"]) ]
        .map { |id| id.to_s.strip }
        .reject(&:empty?)
        .uniq
        .first(OSV_MAX_LOOKUPS)
    end

    # The HIGHEST recognized OSV severity across the candidate ids, or nil. We take
    # the MAX — never the first — so when the OSV records for an advisory's id and
    # its aliases DISAGREE, the gate honors the more severe rating and never
    # under-blocks on source ambiguity. Each id is looked up at most once per scan
    # (memoized, including nil results, so an OSV outage can't re-burn the timeout).
    def osv_severity(ids, osv_cache)
      ids.reduce(nil) do |acc, id|
        severity = osv_cache.key?(id) ? osv_cache[id] : (osv_cache[id] = osv_lookup_severity(id))
        higher_severity(acc, severity)
      end
    end

    # The more severe of two ratings (nil-tolerant). Unknown labels rank lowest.
    def higher_severity(left, right)
      return left if right.nil?
      return right if left.nil?

      (SEVERITY_RANK[right].to_i > SEVERITY_RANK[left].to_i) ? right : left
    end

    def osv_lookup_severity(id)
      body = osv_fetch(id)
      return nil if body.nil?

      record = JSON.parse(body)
      return nil unless record.is_a?(Hash)

      severity_from_osv_record(record)
    rescue StandardError
      nil
    end

    # GET the OSV vuln record. Returns the raw body on a 2xx, else nil. Never
    # raises: a network/timeout/SSL error is swallowed to nil (fail-safe). Logs
    # nothing about the response body — only ids/severities ever leave this module.
    def osv_fetch(id)
      uri = URI.parse("#{OSV_VULN_ENDPOINT}/#{URI.encode_www_form_component(id)}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = OSV_TIMEOUT_SECONDS
      http.read_timeout = OSV_TIMEOUT_SECONDS

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "Powernode-DependencyScanner/1.0"

      response = http.request(request)
      response.is_a?(Net::HTTPSuccess) ? response.body : nil
    rescue StandardError
      nil
    end

    # OSV record → our severity vocab. We consider BOTH a parseable CVSS v3 vector
    # (numeric, authoritative) and OSV's textual database_specific severity (e.g. a
    # GHSA "MODERATE"/"HIGH" rating) and take the MORE SEVERE of the two — so a
    # record that pairs a low CVSS vector with a HIGH GHSA rating still blocks.
    # Unrecognized on both → nil (caller fails safe).
    def severity_from_osv_record(record)
      higher_severity(cvss_severity(record["severity"]),
                      normalize(record.dig("database_specific", "severity")))
    end

    # The MAX severity across OSV's `severity` array — the highest qualitative
    # bucket among the parseable CVSS v3 vectors, so a record carrying several
    # CVSS_V3 entries (e.g. NVD + a CNA) never resolves to a lower one. CVSS v2/v4
    # and unparseable entries are skipped and left to the textual / fail-safe paths.
    def cvss_severity(entries)
      Array(entries).reduce(nil) do |acc, entry|
        next acc unless entry.is_a?(Hash)
        next acc unless entry["type"].to_s.upcase.start_with?("CVSS_V3")

        higher_severity(acc, cvss_base_label(entry["score"]))
      end
    end

    # CVSS v3.x vector string → our severity vocab via the standard qualitative
    # rating scale, or nil for an unparseable/incomplete vector (→ fail-safe).
    def cvss_base_label(vector)
      score = cvss_base_score(vector)
      return nil if score.nil?

      cvss_qualitative(score)
    end

    # Compute the CVSS v3.1 base score from its vector string (returns a Float, or
    # nil if the vector is missing any base metric or an unknown value). Implements
    # the published formula so a miscomputation can only yield nil (fail-safe HIGH),
    # never a silently-too-low score.
    def cvss_base_score(vector)
      return nil unless vector.is_a?(String)

      metrics = {}
      vector.split("/").each do |part|
        key, value = part.split(":", 2)
        metrics[key] = value if key && value
      end
      return nil unless %w[AV AC PR UI S C I A].all? { |m| metrics.key?(m) }

      scope_changed = metrics["S"] == "C"
      av = { "N" => 0.85, "A" => 0.62, "L" => 0.55, "P" => 0.2 }[metrics["AV"]]
      ac = { "L" => 0.77, "H" => 0.44 }[metrics["AC"]]
      pr = cvss_privileges(metrics["PR"], scope_changed)
      ui = { "N" => 0.85, "R" => 0.62 }[metrics["UI"]]
      conf = cvss_impact_metric(metrics["C"])
      integ = cvss_impact_metric(metrics["I"])
      avail = cvss_impact_metric(metrics["A"])
      return nil if [ av, ac, pr, ui, conf, integ, avail ].any?(&:nil?)

      iss = 1 - ((1 - conf) * (1 - integ) * (1 - avail))
      impact = if scope_changed
                 7.52 * (iss - 0.029) - 3.25 * ((iss - 0.02)**15)
               else
                 6.42 * iss
               end
      return 0.0 if impact <= 0

      exploitability = 8.22 * av * ac * pr * ui
      raw = scope_changed ? 1.08 * (impact + exploitability) : (impact + exploitability)
      cvss_roundup([ raw, 10 ].min)
    end

    def cvss_privileges(value, scope_changed)
      case value
      when "N" then 0.85
      when "L" then scope_changed ? 0.68 : 0.62
      when "H" then scope_changed ? 0.5 : 0.27
      end
    end

    def cvss_impact_metric(value)
      { "H" => 0.56, "L" => 0.22, "N" => 0.0 }[value]
    end

    # CVSS v3.1 Roundup: smallest one-decimal value >= input, computed on integers
    # to avoid binary-float edge cases at bucket boundaries.
    def cvss_roundup(input)
      int_input = (input * 100_000).round
      if (int_input % 10_000).zero?
        int_input / 100_000.0
      else
        ((int_input / 10_000).floor + 1) / 10.0
      end
    end

    # Standard CVSS v3.1 qualitative severity rating, mapped to our vocab. "none"
    # (0.0) collapses to our lowest bucket — authoritative and below the gate.
    def cvss_qualitative(score)
      if score >= 9.0 then "critical"
      elsif score >= 7.0 then "high"
      elsif score >= 4.0 then "medium"
      else "low"
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

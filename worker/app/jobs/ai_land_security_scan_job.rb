# frozen_string_literal: true

require "shellwords"
require_relative "../services/devops/secret_scanner"
require_relative "../services/devops/dependency_scanner"
require_relative "../services/devops/sbom_generator"

# G4 worker-side DEEP security scan on the REAL staged land diff. Runs between the
# stage and CI-poll phases of the auto-land pipeline: it checks out the source
# branch (reusing the Devops checkout handler), diffs it against the land base,
# and scans the diff for leaked secrets — the depth the server-side
# Ai::Land::SecurityGateService (which only sees server-side metadata, not the
# committed diff) cannot reach. Brakeman SAST and generic dependency-CVE auditing
# (Devops::DependencyScanner: bundler-audit / npm audit / pip-audit) run
# best-effort when the respective tooling is available. The dependency scan uses
# stock, ecosystem-standard tools — NOT the supply-chain extension — so core/worker
# never hard-depends on that extension. A best-effort CycloneDX SBOM of the
# checkout's dependency manifests (Devops::SbomGenerator) is also attached to the
# job result as additive INVENTORY metadata — it is NOT a gate and never blocks or
# fails the land.
#
# Findings are POSTed to the server's land park-back surface
# (campaign_lands#security_findings), which records them under
# metadata["security_gate"] and PARKS the land when any finding is blocking —
# composing with the G4 server gate.
#
# FAIL CLOSED on an incomplete scan. The job ends on exactly one of three
# outcomes, so an autonomous land never strands silently:
#   * clean scan ............... hand off to the staged-CI poll
#   * blocking finding ......... server parks the land (real secret/SAST hit)
#   * scan could NOT complete .. server PARKS the land for human review
# The last case is the fail-closed change: an infrastructure failure (the
# checkout raised, or the diff could not be produced) means we never actually
# inspected the staged diff, so the land is HELD for an operator rather than
# slipped through to CI on an unverified change. The ONLY benign skip is a land
# with no resolvable repository — there is no diffable code that could carry a
# committed secret, the server-side G4 gate already ran, and the staged-CI gate
# still applies, so that case proceeds to CI cleanly.
class AiLandSecurityScanJob < BaseJob
  include DevopsWorkspaceSteps

  # Raised when the scan cannot be COMPLETED (vs. completing and finding
  # nothing). Carries only a generic stage label — never command output, which
  # could echo a tokened remote URL.
  class ScanIncompleteError < StandardError; end

  sidekiq_options queue: "ai_orchestration", retry: 1

  DIFF_TIMEOUT_SECONDS = 120
  BRAKEMAN_TIMEOUT_SECONDS = 180
  DEPENDENCY_SCAN_TIMEOUT_SECONDS = 180

  # Synthetic park-back finding for an incomplete scan. "high" sits at the
  # server's BLOCKING_SEVERITY threshold (Ai::Land::SecurityGateService), so the
  # existing endpoint parks the land. Mirrored by hand across the HTTP boundary.
  INCOMPLETE_SCANNER  = "land-security-scan"
  INCOMPLETE_SEVERITY = "high"

  def execute(args = {})
    land_id = args["land_id"]
    return if land_id.blank?

    repository = args["repository"].presence
    # No resolvable repo (e.g. a legacy land with no loop repository_url): the
    # server-side G4 gate already ran and the staged-CI gate still applies, so
    # skip the deep scan cleanly rather than stranding the land.
    unless repository
      log_info "[AiLandSecurityScan] land #{land_id}: no repository to scan; skipping deep scan"
      return hand_off_to_ci(land_id)
    end

    source_branch = args["source_branch"]
    target_branch = args["target_branch"].presence || "develop"
    base_sha      = args["base_sha"].presence

    workspace = nil
    sbom = nil
    begin
      workspace = checkout_workspace(repository, source_branch)
      diff = compute_diff(workspace, base_sha: base_sha, target_branch: target_branch)

      findings = Devops::SecretScanner.findings(diff)
      scanners = [ Devops::SecretScanner::SCANNER_NAME ]

      sast = run_brakeman(workspace)
      findings.concat(sast[:findings])
      scanners << "brakeman" if sast[:ran]

      # Generic dependency-CVE auditing. Unlike Brakeman (a single tool, listed
      # only when it actually ran), this layer is a best-effort composite that
      # always participates in the gate, so its scanner name is always recorded.
      findings.concat(run_dependency_scan(workspace))
      scanners << Devops::DependencyScanner::SCANNER_NAME

      # Best-effort CycloneDX SBOM over the checkout's dependency manifests. Built
      # here (inside the begin, BEFORE `ensure` removes the workspace) so it can
      # read the lockfiles; it is INVENTORY metadata, never a gate.
      sbom = build_sbom(workspace, repository)

      blocked = report_findings(land_id, findings, scanners, sbom: sbom)
      log_info "[AiLandSecurityScan] land #{land_id} findings=#{findings.size} blocked=#{blocked}"

      # Blocking finding ⇒ the server parked the land; stop the pipeline here. The
      # SBOM still rides along on the result as additive metadata.
      return { land_id: land_id, blocked: true, findings: findings.size, sbom: sbom } if blocked
    rescue StandardError => e
      # FAIL CLOSED: the scan could not complete (checkout raised, diff failed,
      # or an unexpected error around the scan / its park-back POST). We never
      # inspected the staged diff, so PARK the land for human review instead of
      # advancing it to CI on an unverified change.
      log_error "[AiLandSecurityScan] deep scan could not complete for land #{land_id}; parking for review", e
      return park_incomplete_scan(land_id, e)
    ensure
      FileUtils.rm_rf(workspace) if workspace.present? && File.directory?(workspace)
    end

    hand_off_to_ci(land_id, sbom: sbom)
  end

  private

  # Diff the checked-out branch against the land base. Prefer the exact base SHA
  # the stage phase recorded (what staged CI ran against); fall back to the
  # target's remote-tracking ref, which a full clone always has. A non-zero exit
  # is a real failure (bad ref / not a repo), NOT an empty diff (clean diff =>
  # exit 0, empty output) — so when the diff cannot be produced we raise to fail
  # the scan CLOSED rather than scanning empty output and silently passing.
  def compute_diff(workspace, base_sha:, target_branch:)
    primary = base_sha || "origin/#{target_branch}"
    run = run_workspace_command(workspace, diff_command(primary), timeout_secs: DIFF_TIMEOUT_SECONDS)
    return run[:output] if run[:exit_code].to_i.zero?

    fallback = "origin/#{target_branch}"
    raise ScanIncompleteError, "could not diff the land against its base" if primary == fallback

    run = run_workspace_command(workspace, diff_command(fallback), timeout_secs: DIFF_TIMEOUT_SECONDS)
    return run[:output] if run[:exit_code].to_i.zero?

    raise ScanIncompleteError, "could not diff the land against its base"
  end

  def diff_command(base)
    "git diff #{Shellwords.escape(base)}...HEAD"
  end

  # Best-effort Brakeman SAST over the checkout. Skips cleanly (ran: false) when
  # the binary/gem is absent or the run produces no parseable JSON.
  def run_brakeman(workspace)
    run = run_workspace_command(
      workspace,
      "brakeman -q -f json --no-pager #{Shellwords.escape(workspace)}",
      timeout_secs: BRAKEMAN_TIMEOUT_SECONDS
    )
    report = JSON.parse(run[:output].to_s)
    findings = Array(report["warnings"]).filter_map do |w|
      severity = brakeman_severity(w["confidence"])
      next unless severity

      # File path + warning type only — never source content.
      { scanner: "brakeman", severity: severity, detail: "SAST: #{w['warning_type']} (#{w['file']})" }
    end
    { ran: true, findings: findings }
  rescue StandardError => e
    log_info "[AiLandSecurityScan] brakeman unavailable/failed; skipping SAST (#{e.class})"
    { ran: false, findings: [] }
  end

  def brakeman_severity(confidence)
    case confidence.to_s.downcase
    when "high"   then "high"
    when "medium" then "medium"
    end
  end

  # Best-effort generic dependency-CVE scan over the checkout. Delegates the
  # per-ecosystem run/parse to Devops::DependencyScanner, handing it a closure
  # over the shared workspace command runner. The scanner already skips each
  # ecosystem cleanly on a missing tool/manifest; this rescue is a final
  # best-effort backstop so a dependency-tool problem never fails the land closed
  # (only the secret scan + diff do that).
  def run_dependency_scan(workspace)
    Devops::DependencyScanner.scan(
      workspace,
      runner: ->(command) { run_workspace_command(workspace, command, timeout_secs: DEPENDENCY_SCAN_TIMEOUT_SECONDS) }
    )
  rescue StandardError => e
    log_info "[AiLandSecurityScan] dependency-CVE scan unavailable/failed; skipping (#{e.class})"
    []
  end

  # Best-effort CycloneDX SBOM over the checkout's dependency manifests. PURE
  # INVENTORY metadata, NOT a gate: it never blocks and never fails the land. Any
  # error is swallowed into a degraded result so an SBOM problem can't trip the
  # fail-closed park path (only the secret scan + diff production do that). Belt
  # and suspenders: Devops::SbomGenerator.generate already rescues internally; this
  # outer rescue guarantees build_sbom itself never raises.
  def build_sbom(workspace, repository)
    sbom = Devops::SbomGenerator.generate(workspace, component_name: repository)
    log_info "[AiLandSecurityScan] SBOM #{sbom[:format]} #{sbom[:spec_version]}: " \
             "#{sbom[:component_count]} components (generated=#{sbom[:generated]})"
    sbom
  rescue StandardError => e
    # Defensive: Devops::SbomGenerator.generate already rescues internally and
    # returns a degraded result, so this should never fire — but if it ever does,
    # return the SAME shape (an empty-but-valid CycloneDX document) so a downstream
    # consumer always sees a Hash document.
    log_info "[AiLandSecurityScan] SBOM generation failed; attaching degraded result (#{e.class})"
    {
      format: "CycloneDX", spec_version: "1.5", generated: false, component_count: 0, truncated: false,
      document: { "bomFormat" => "CycloneDX", "specVersion" => "1.5", "version" => 1, "components" => [] }
    }
  end

  # Post findings to the land park-back surface; returns whether the server
  # blocked (parked) the land. The optional CycloneDX `sbom` rides along as
  # additive INVENTORY metadata so the server can persist it (the server caps
  # its stored size) — it is NOT a gate and never changes the blocking decision.
  # Omitted entirely when nil (e.g. the fail-closed incomplete-scan park-back,
  # where no scan ran) so the server stays back-compatible.
  def report_findings(land_id, findings, scanners, sbom: nil)
    payload = { findings: findings, scanners: scanners }
    payload[:sbom] = sbom unless sbom.nil?
    resp = api_client.post(
      "/api/v1/internal/ai/campaign_lands/#{land_id}/security_findings",
      payload
    )
    data = resp.is_a?(Hash) ? (resp["data"] || resp) : {}
    !!data["blocked"]
  end

  def hand_off_to_ci(land_id, sbom: nil)
    AiCampaignLandCiPollJob.perform_async("land_id" => land_id, "gate" => "staged", "attempt" => 0)
    result = { land_id: land_id, blocked: false }
    result[:sbom] = sbom unless sbom.nil?
    result
  end

  # Fail-closed park-back: POST a synthetic blocking finding so the existing
  # server endpoint parks the land for human review. The detail is generic — a
  # stage label for our own ScanIncompleteError, otherwise just the error CLASS
  # name (never the message, which could echo a tokened URL or other content).
  # Does NOT chain the CI poll. If the park-back POST itself fails the error
  # propagates so Sidekiq retries; the land stays held, never slipped to CI.
  def park_incomplete_scan(land_id, error)
    reason = error.is_a?(ScanIncompleteError) ? error.message : error.class.name
    finding = {
      scanner: INCOMPLETE_SCANNER,
      severity: INCOMPLETE_SEVERITY,
      detail: "could not complete security scan: #{reason}"
    }
    report_findings(land_id, [ finding ], [ INCOMPLETE_SCANNER ])
    { land_id: land_id, blocked: true, scan_incomplete: true }
  rescue StandardError => e
    log_error "[AiLandSecurityScan] failed to park-back the incomplete scan for land #{land_id}", e
    raise
  end
end

# frozen_string_literal: true

require "shellwords"
require_relative "../services/devops/secret_scanner"

# G4 worker-side DEEP security scan on the REAL staged land diff. Runs between the
# stage and CI-poll phases of the auto-land pipeline: it checks out the source
# branch (reusing the Devops checkout handler), diffs it against the land base,
# and scans the diff for leaked secrets — the depth the server-side
# Ai::Land::SecurityGateService (which only sees server-side metadata, not the
# committed diff) cannot reach. Brakeman SAST runs best-effort when the binary is
# available; dependency-CVE / SBOM scanning over the diff (via the supply-chain
# step handlers) is a deliberate follow-up — core must not hard-depend on that
# extension, so it is NOT wired here.
#
# Findings are POSTed to the server's land park-back surface
# (campaign_lands#security_findings), which records them under
# metadata["security_gate"] and PARKS the land when any finding is blocking —
# composing with the G4 server gate. On a clean scan (or when no repository can be
# resolved / the checkout fails) the job hands off to the CI poll so the land
# still faces its normal staged-CI gate and never strands.
class AiLandSecurityScanJob < BaseJob
  include DevopsWorkspaceSteps

  sidekiq_options queue: "ai_orchestration", retry: 1

  DIFF_TIMEOUT_SECONDS = 120
  BRAKEMAN_TIMEOUT_SECONDS = 180

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
    begin
      workspace = checkout_workspace(repository, source_branch)
      diff = compute_diff(workspace, base_sha: base_sha, target_branch: target_branch)

      findings = Devops::SecretScanner.findings(diff)
      scanners = [ Devops::SecretScanner::SCANNER_NAME ]

      sast = run_brakeman(workspace)
      findings.concat(sast[:findings])
      scanners << "brakeman" if sast[:ran]

      blocked = report_findings(land_id, findings, scanners)
      log_info "[AiLandSecurityScan] land #{land_id} findings=#{findings.size} blocked=#{blocked}"

      # Blocking finding ⇒ the server parked the land; stop the pipeline here.
      return { land_id: land_id, blocked: true, findings: findings.size } if blocked
    rescue StandardError => e
      # An infrastructure failure (clone/diff) must not permanently block a land.
      # Actual secret/SAST FINDINGS still park above; here we fall through to the
      # standard CI gate so the land keeps moving.
      log_error "[AiLandSecurityScan] deep scan failed for land #{land_id}; falling back to CI gate", e
    ensure
      FileUtils.rm_rf(workspace) if workspace.present? && File.directory?(workspace)
    end

    hand_off_to_ci(land_id)
  end

  private

  # Diff the checked-out branch against the land base. Prefer the exact base SHA
  # the stage phase recorded (what staged CI ran against); fall back to the
  # target's remote-tracking ref, which a full clone always has.
  def compute_diff(workspace, base_sha:, target_branch:)
    primary = base_sha || "origin/#{target_branch}"
    run = run_workspace_command(workspace, diff_command(primary), timeout_secs: DIFF_TIMEOUT_SECONDS)
    return run[:output] if run[:exit_code].to_i.zero?

    fallback = "origin/#{target_branch}"
    return run[:output] if primary == fallback

    run_workspace_command(workspace, diff_command(fallback), timeout_secs: DIFF_TIMEOUT_SECONDS)[:output]
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

  # Post findings to the land park-back surface; returns whether the server
  # blocked (parked) the land.
  def report_findings(land_id, findings, scanners)
    resp = api_client.post(
      "/api/v1/internal/ai/campaign_lands/#{land_id}/security_findings",
      { findings: findings, scanners: scanners }
    )
    data = resp.is_a?(Hash) ? (resp["data"] || resp) : {}
    !!data["blocked"]
  end

  def hand_off_to_ci(land_id)
    AiCampaignLandCiPollJob.perform_async("land_id" => land_id, "gate" => "staged", "attempt" => 0)
    { land_id: land_id, blocked: false }
  end
end

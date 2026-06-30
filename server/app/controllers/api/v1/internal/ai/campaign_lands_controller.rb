# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Worker-driven auto-land pipeline. The land scheduler/worker calls these
        # to drive each Ai::CampaignLand through its phases (one phase per call,
        # idempotent). Authenticated as the worker via mTLS (InternalBaseController).
        class CampaignLandsController < Api::V1::Internal::InternalBaseController
          before_action :set_land, except: [ :process_queue ]

          # Max serialized size (bytes) for a stored land-scan SBOM. The SBOM is
          # additive INVENTORY metadata (never a gate); the jsonb metadata column
          # loads with every land row, so an oversized document is reduced to a
          # compact summary rather than bloating the row. ~256 KB comfortably holds
          # a real CycloneDX manifest while bounding pathological inputs.
          SBOM_MAX_BYTES = 256 * 1024

          # POST /api/v1/internal/ai/campaign_lands/process_queue
          # Pick the next queued land per (account, target) whose slot is free.
          def process_queue
            picked = []
            ::Ai::CampaignLand.queued.distinct.pluck(:account_id, :target_branch).each do |account_id, target|
              account = Account.find_by(id: account_id)
              next unless account&.active? && !account.ai_suspended?

              land = ::Ai::Land::LandingQueue.next_for(target_branch: target, account: account)
              picked << land.summary if land
            end
            render_success(lands: picked)
          end

          def show
            render_success(land: @land.summary)
          end

          def stage
            render_success(land: service.stage!.summary)
          end

          def merge
            render_success(land: service.merge!.summary)
          end

          # GET .../ci_status?gate=staged|target — read CI for the relevant SHA.
          def ci_status
            sha = params[:gate] == "target" ? @land.merged_sha : @land.staged_sha
            ci = ::Ai::Land::CiGate.status_for(sha: sha)
            render_success(land_id: @land.id, gate: params[:gate] || "staged", sha: sha, ci_status: ci)
          end

          # POST .../verify — after develop CI on merged_sha is terminal:
          #   success → land; failure → rollback; still pending → report.
          def verify
            status = ::Ai::Land::CiGate.status_for(sha: @land.merged_sha)
            case status
            when :success
              @land.land!
              service.cleanup!
              notify_source_landed
              # Campaign-only post-land helpers: rebase advisory + deploy are keyed
              # to a campaign. Non-campaign land sources (missions) skip them; their
              # post-land follow-up runs via notify_source_landed above.
              if @land.campaign
                advise_other_campaigns_to_rebase
                deploy_landed_change
              end
            when :failure
              service.rollback!
            end
            render_success(land: @land.reload.summary, ci_status: status)
          end

          def park
            render_success(land: service.park(params[:reason].presence || "parked by worker").summary)
          end

          def rollback
            render_success(land: service.rollback!.summary)
          end

          def cleanup
            render_success(land: service.cleanup!.summary)
          end

          # POST .../security_findings — park-back surface for the worker-side deep
          # security scan (G4 worker depth). The worker scans the REAL staged diff
          # (secrets + best-effort Brakeman) and posts findings here. We record them
          # under metadata["security_gate"]["worker_scan"] — composing with the
          # server-side gate's findings — and PARK the land when any finding is
          # blocking (reusing LandService#park). Findings carry only
          # scanner/severity/detail labels (never raw secret values), so the stored
          # metadata is safe to persist/display.
          #
          # An OPTIONAL CycloneDX `sbom` (additive dependency INVENTORY built by the
          # worker scan) is persisted under metadata["security_gate"]["sbom"] when
          # present. It is NOT a gate and never changes the blocking decision; it is
          # size-bounded (see #bounded_sbom) so an oversized document can never bloat
          # the land row or fail the land. Omitting it is fully back-compatible.
          def security_findings
            findings = Array(params[:findings]).map do |f|
              (f.respond_to?(:permit) ? f.permit(:scanner, :severity, :detail, :category).to_h : f.to_h).stringify_keys
            end
            scanners = Array(params[:scanners]).map(&:to_s)
            blocked = ::Ai::Land::SecurityGateService.blocking?(findings)

            gate = (@land.metadata.to_h["security_gate"] || {}).deep_dup
            gate["worker_scan"] = {
              "blocked" => blocked,
              "scanners" => scanners,
              "findings" => findings,
              "evaluated_at" => Time.current.iso8601
            }
            sbom = bounded_sbom(params[:sbom])
            gate["sbom"] = sbom if sbom
            @land.update!(metadata: @land.metadata.to_h.merge("security_gate" => gate))

            if blocked && !@land.terminal? && @land.status != "parked"
              service.park("worker security scan blocked: #{worker_findings_summary(findings)}")
            end

            render_success(land_id: @land.id, blocked: blocked, land_status: @land.reload.status)
          end

          private

          # Coerce the OPTIONAL inbound `:sbom` param into a safe, size-bounded Hash
          # for storage, or nil when absent (back-compat: store nothing). Never
          # raises and never participates in the gate: a missing, malformed, or
          # oversized SBOM degrades gracefully so it can neither fail the land nor
          # change the findings/scanners behavior. An oversized document is reduced
          # to its inventory summary fields with a `truncated` flag (the heavy
          # component list is dropped) so the row stays bounded.
          def bounded_sbom(raw)
            return nil if raw.blank?

            hash = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw).deep_stringify_keys
            return hash if hash.to_json.bytesize <= SBOM_MAX_BYTES

            {
              "truncated" => true,
              "format" => hash["format"],
              "spec_version" => hash["spec_version"],
              "generated" => hash["generated"],
              "component_count" => hash["component_count"]
            }.compact
          rescue StandardError => e
            Rails.logger.warn("[CampaignLands#security_findings] dropping unparseable SBOM (#{e.class})")
            nil
          end

          # Compact "scanner:severity" summary for the park reason. Labels only.
          def worker_findings_summary(findings)
            return "policy violation" if findings.blank?

            findings.map { |f| "#{f['scanner']}:#{f['severity']}" }.uniq.join(", ")
          end

          # Notify the land's source (campaign, mission, ...) that the change
          # landed + post-merge CI passed, so it can advance its own workflow
          # (e.g. a mission advances out of the merging phase). Best-effort: a
          # source callback failure must never affect the land response.
          def notify_source_landed
            src = @land.source
            src.on_land_completed!(@land) if src.respond_to?(:on_land_completed!)
          rescue StandardError => e
            Rails.logger.warn("[CampaignLands#verify] source land-completed callback failed: #{e.message}")
          end

          # The change is on the target branch — run the deploy orchestrator. dry-run by
          # default (records a DeployRun + audit without touching infra); a REAL deploy only
          # happens when the campaign/land opted in (deploy config auto_deploy/dry_run:false).
          # Best-effort: a deploy-orchestration failure must never affect the land response.
          def deploy_landed_change
            ::Ai::Deploy::Orchestrator.new(account: @land.account).deploy_for_land(@land)
          rescue StandardError => e
            Rails.logger.warn("[CampaignLands#verify] deploy orchestration failed: #{e.message}")
          end

          # A land just advanced the target branch, so every OTHER open campaign is now
          # behind it. Advise their drivers to rebase early (conflict avoidance). Best-effort:
          # never let an advisory failure affect the land response.
          def advise_other_campaigns_to_rebase
            ::Ai::Land::RebaseAdvisor.new(account: @land.account)
                                     .notify_stale!(target_branch: @land.target_branch, exclude: @land.campaign)
          rescue StandardError => e
            Rails.logger.warn("[CampaignLands#verify] rebase advisory failed: #{e.message}")
          end

          def set_land
            @land = ::Ai::CampaignLand.find(params[:id])
          end

          def service
            @service ||= ::Ai::Land::LandService.new(@land)
          end
        end
      end
    end
  end
end

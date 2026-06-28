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
              advise_other_campaigns_to_rebase
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

          private

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

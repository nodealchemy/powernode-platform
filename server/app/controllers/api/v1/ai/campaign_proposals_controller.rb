# frozen_string_literal: true

module Api
  module V1
    module Ai
      # REST surface for the campaign-proposal queue (Campaign Discovery & Delegation
      # Control Plane, increment 1). Lists/filters the deduped queue, supports manual
      # proposal entry, and the review transitions (queue/approve/reject). Approving a
      # proposal spawns its campaign in increment 3 (the spawn hook lands there); here
      # approve! only advances status. Reuses the ai.campaigns.{read,manage} gate — the
      # proposal queue is part of the campaigns domain, so no new permission family.
      class CampaignProposalsController < ApplicationController
        before_action :require_read, only: %i[index show]
        before_action :require_manage, only: %i[create queue approve reject spawn]
        before_action :set_proposal, only: %i[show queue approve reject spawn]
        # Kill-switch: spawning arms an autonomous campaign loop — refuse while AI is suspended.
        before_action :reject_if_ai_suspended, only: %i[spawn]

        # A refusal from the shared campaign check inside a service is a 403, whichever
        # action reached it.
        rescue_from ::Ai::Campaigns::Authorization::Refused do |exception|
          render_forbidden(exception.message) unless performed?
        end

        def index
          scope = current_user.account.ai_campaign_proposals
          scope = scope.by_status(params[:status]) if params[:status].present?
          total = scope.count # true total for the filter, not the limited page size
          proposals = scope.recent(params.fetch(:limit, 100).to_i)
          render_success(
            proposals: proposals.map { |p| serialize(p) },
            total_count: total
          )
        end

        def show
          render_success(serialize(@proposal))
        end

        def create
          proposal = ::Ai::CampaignProposal.propose!(
            account: current_user.account,
            actor: current_user,
            title: params.require(:title),
            objective: params.require(:objective),
            source: params.fetch(:source, "manual"),
            scope: params[:scope],
            suggested_workload: params[:suggested_workload],
            suggested_driver: params[:suggested_driver],
            decision_authority: params.fetch(:decision_authority, "trusted"),
            configuration: permitted_hash(:configuration),
            evidence: permitted_hash(:evidence)
          )
          render_success(serialize(proposal), status: :created)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        def queue
          @proposal.queue!(current_user)
          render_success(serialize(@proposal))
        end

        def approve
          @proposal.approve!(current_user)
          render_success(serialize(@proposal))
        end

        def reject
          @proposal.reject!(current_user, reason: params[:reason])
          render_success(serialize(@proposal))
        end

        # Spawn the proposal's campaign (idempotent). Approve is the decision; spawn is
        # the action that creates the Ai::Campaign + its dev-loop. Delegation of that
        # loop's driver happens separately (increment 4).
        def spawn
          campaign = ::Ai::CampaignProposals::SpawnService.new(
            account: current_user.account, user: current_user
          ).spawn!(@proposal)
          render_success(serialize(@proposal.reload).merge(spawned_campaign: campaign.summary))
        rescue ::Ai::Campaigns::Authorization::Refused => e
          render_forbidden(e.message)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def set_proposal
          @proposal = current_user.account.ai_campaign_proposals.find(params[:id])
        end

        def require_read
          require_permission("ai.campaigns.read")
        end

        # Answered for the account whose proposals this controller touches (the user's own),
        # through the shared campaign check, never from an account-switch session's
        # delegation, which carries another account's permissions.
        def require_manage
          permission = ::Ai::Campaigns::Authorization::MANAGE_PERMISSION
          return if ::Ai::Campaigns::Authorization.permitted?(user: current_user, account: current_user&.account)

          raise ::Authentication::PermissionDenied.new("Permission denied: #{permission}", permission: permission)
        end

        def reject_if_ai_suspended
          return unless current_user.account.ai_suspended?

          render_error("AI activity is suspended for this account", status: :conflict)
        end

        def serialize(proposal)
          proposal.summary
        end

        def permitted_hash(key)
          raw = params[key]
          return {} if raw.blank?
          return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
          return raw if raw.is_a?(Hash)

          {} # a scalar/array for an object param is ignored rather than 500-ing on .to_h
        end
      end
    end
  end
end

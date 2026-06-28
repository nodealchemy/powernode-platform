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

        def index
          proposals = current_user.account.ai_campaign_proposals
          proposals = proposals.by_status(params[:status]) if params[:status].present?
          proposals = proposals.recent(params.fetch(:limit, 100).to_i)
          render_success(
            proposals: proposals.map { |p| serialize(p) },
            total_count: proposals.size
          )
        end

        def show
          render_success(serialize(@proposal))
        end

        def create
          proposal = ::Ai::CampaignProposal.propose!(
            account: current_user.account,
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
          @proposal.queue!
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

        def require_manage
          require_permission("ai.campaigns.manage")
        end

        def serialize(proposal)
          proposal.summary
        end

        def permitted_hash(key)
          raw = params[key]
          return {} if raw.blank?

          raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        end
      end
    end
  end
end

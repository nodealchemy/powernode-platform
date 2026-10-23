# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Time-boxed promotion grants (Ai::PromotionGrant). The ONLY door that
      # issues one: a person, in their own session, holding
      # ai.promotion_grants.manage and the gated verb's own permission. Revoking
      # only tightens, so any REST session holding the permission may revoke.
      # Reading needs ai.promotion_grants.read (or .manage).
      class PromotionGrantsController < ApplicationController
        include ::HumanSession

        MANAGE = "ai.promotion_grants.manage"
        READ = "ai.promotion_grants.read"
        EXPIRY_PRESETS_HOURS = [ 1, 4, 8, 24 ].freeze
        LIST_LIMIT = 100

        before_action :require_read, only: %i[index show options]
        before_action :require_manage, only: %i[create revoke]
        before_action :set_grant, only: %i[show revoke]

        # GET /api/v1/ai/promotion_grants
        # Active grants first, then the recent rest. ?active=true for only the live ones.
        def index
          scope = account.ai_promotion_grants.includes(:granted_by, :revoked_by, :agent, :environment)
          scope = scope.active if params[:active] == "true"
          grants = scope.recent.limit(LIST_LIMIT).to_a
          now = Time.current
          grants = grants.sort_by { |g| [ g.active?(now) ? 0 : 1, -g.created_at.to_f ] }

          render_success(promotion_grants: grants.map { |g| serialize(g, now: now) })
        end

        # GET /api/v1/ai/promotion_grants/:id — with the operations that ran under it.
        def show
          uses = @grant.deferred_operations.order(created_at: :desc).limit(LIST_LIMIT).map do |op|
            { deferred_operation_id: op.id, status: op.status, description: op.description,
              created_at: op.created_at.iso8601, executed_at: op.executed_at&.iso8601 }
          end
          render_success(promotion_grant: serialize(@grant).merge(uses: uses))
        end

        # GET /api/v1/ai/promotion_grants/options — what the create form offers.
        def options
          categories = ::Ai::PromotionGrants::Grantable.categories
          category = categories.first || ::Ai::PromotionGrant::CATEGORIES.first
          # `strict` and the two limits are what the server enforces on that
          # plane (Ai::PromotionGrant.strict_environment?); the form shows them.
          environments = ::Ai::Environment.ladder_for(account).map do |e|
            strict = ::Ai::PromotionGrant.strict_environment?(e)
            { id: e.id, slug: e.slug, name: e.name, tier: e.tier, is_protected: e.protected?,
              strict: strict, max_lifetime_hours: (::Ai::PromotionGrant.max_lifetime_for(e) / 1.hour).to_i,
              max_uses_limit: strict ? ::Ai::PromotionGrant::STRICT_MAX_USES : nil }
          end
          render_success(
            categories: categories,
            environments: environments,
            modules: ::Ai::PromotionGrants::Catalog.subjects(account: account, action_category: category),
            expiry_presets_hours: EXPIRY_PRESETS_HOURS,
            max_lifetime_hours: (::Ai::PromotionGrant::MAX_LIFETIME / 1.hour).to_i,
            required_permission: ::Ai::PromotionGrants::Catalog.required_permission(category)
          )
        end

        # POST /api/v1/ai/promotion_grants
        def create
          attributes = grant_attributes
          return render_error(attributes[:error], status: :unprocessable_content) if attributes[:error]

          grant = ::Ai::PromotionGrants::Ledger.issue!(
            account: account, granted_by: current_user, origin: human_decision_origin,
            attributes: attributes, request: request
          )
          render_success({ promotion_grant: serialize(grant) }, status: :created)
        rescue ::Ai::PromotionGrants::Ledger::Refused => e
          render_error(e.message, status: e.status)
        end

        # POST /api/v1/ai/promotion_grants/:id/revoke
        def revoke
          ::Ai::PromotionGrants::Ledger.revoke!(@grant, by: current_user, request: request,
                                                        impersonator: impersonating? ? impersonator : nil)
          render_success(promotion_grant: serialize(@grant.reload))
        rescue ::Ai::PromotionGrants::Ledger::Refused => e
          render_error(e.message, status: e.status)
        end

        private

        def account
          current_user.account
        end

        def require_read
          return if current_user.has_permission?(READ) || current_user.has_permission?(MANAGE)

          render_error("Permission denied: #{READ}", status: :forbidden)
        end

        def require_manage
          return if current_user.has_permission?(MANAGE)

          render_error("Permission denied: #{MANAGE}", status: :forbidden)
        end

        def set_grant
          @grant = account.ai_promotion_grants.find_by(id: params[:id].to_s)
          render_error("Promotion grant not found", status: :not_found) unless @grant
        end

        # Expiry is asked for as a lifetime (expires_in_hours, the form's
        # presets) or an absolute expires_at; the row enforces the caps. A
        # lifetime that is not a finite, positive number comes back as
        # { error: } and is refused with a 422, never raised.
        def grant_attributes
          permitted = params.permit(:ai_agent_id, :environment_id, :action_category, :max_uses, :reason,
                                    :expires_at, :expires_in_hours, :granter_driven_only, module_ids: [])
          attrs = permitted.to_h.symbolize_keys
          raw = attrs.delete(:expires_in_hours)
          return attrs if raw.blank? || attrs[:expires_at].present?

          hours = Float(raw.to_s, exception: false)
          return { error: "expires_in_hours must be a positive, finite number of hours" } unless hours&.finite? && hours.positive?

          attrs.merge(expires_at: Time.current + (hours * 3600).round)
        end

        def serialize(grant, now: Time.current)
          {
            id: grant.id,
            action_category: grant.action_category,
            status: grant.status(now),
            agent: grant.agent && { id: grant.agent.id, name: grant.agent.name, agent_type: grant.agent.agent_type },
            environment: grant.environment && {
              id: grant.environment.id, slug: grant.environment.slug, name: grant.environment.name,
              is_protected: grant.environment.protected?
            },
            module_ids: grant.module_ids,
            granter_driven_only: grant.granter_driven_only,
            strict_plane: grant.strict_plane?,
            binding: { kind: grant.binding_kind, id: grant.binding_id,
                       description: ::Ai::PromotionGrants::Binding.describe(kind: grant.binding_kind,
                                                                            id: grant.binding_id, agent: grant.agent) },
            max_uses: grant.max_uses,
            uses_count: grant.uses_count,
            uses_remaining: grant.uses_remaining,
            expires_at: grant.expires_at.iso8601,
            seconds_remaining: grant.seconds_remaining(now),
            reason: grant.reason,
            granted_by: grant.granted_by && { id: grant.granted_by.id, name: grant.granted_by.full_name,
                                              email: grant.granted_by.email },
            revoked_at: grant.revoked_at&.iso8601,
            revoked_by: grant.revoked_by && { id: grant.revoked_by.id, name: grant.revoked_by.full_name },
            created_at: grant.created_at.iso8601
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Security
        class AgentIdentityController < ApplicationController
          before_action :authenticate_request
          before_action :validate_permissions

          # GET /api/v1/ai/security/identities
          def index
            identities = ::Ai::AgentIdentity.where(account: current_account)
            identities = identities.for_agent(params[:agent_id]) if params[:agent_id].present?
            identities = identities.where(status: params[:status]) if params[:status].present?
            identities = identities.order(created_at: :desc)

            page_params = pagination_params
            total = identities.count
            items = identities.offset((page_params[:page] - 1) * page_params[:per_page])
                              .limit(page_params[:per_page])

            render_success(data: {
              items: items.map { |i| identity_json(i) },
              pagination: {
                current_page: page_params[:page],
                per_page: page_params[:per_page],
                total_count: total,
                total_pages: (total.to_f / page_params[:per_page]).ceil
              }
            })
          end

          # GET /api/v1/ai/security/identities/:id
          def show
            identity = ::Ai::AgentIdentity.where(account: current_account).find(params[:id])
            render_success(data: identity_json(identity))
          rescue ActiveRecord::RecordNotFound
            render_not_found("AgentIdentity")
          end

          # POST /api/v1/ai/security/identities
          def provision
            agent = current_account.ai_agents.find(params[:agent_id])
            identity = service.provision!(agent: agent)

            render_success(data: identity_json(identity), status: :created)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent")
          rescue ::Ai::Security::AgentIdentityService::IdentityError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/identities/:id/rotate
          def rotate
            identity = ::Ai::AgentIdentity.where(account: current_account).find(params[:id])
            agent = current_account.ai_agents.find(identity.agent_id)
            new_identity = service.rotate!(agent: agent)

            render_success(data: identity_json(new_identity))
          rescue ActiveRecord::RecordNotFound
            render_not_found("AgentIdentity")
          rescue ::Ai::Security::AgentIdentityService::IdentityError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/identities/:id/revoke
          def revoke
            identity = ::Ai::AgentIdentity.where(account: current_account).find(params[:id])
            agent = current_account.ai_agents.find(identity.agent_id)
            result = service.revoke!(agent: agent, reason: params[:reason] || "Manual revocation")

            render_success(data: result)
          rescue ActiveRecord::RecordNotFound
            render_not_found("AgentIdentity")
          rescue ::Ai::Security::AgentIdentityService::IdentityError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/identities/verify
          def verify
            result = service.verify(
              agent_id: params[:agent_id],
              payload: params[:payload],
              signature: params[:signature]
            )

            render_success(data: result)
          rescue ::Ai::Security::AgentIdentityService::VerificationError => e
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker || current_service

            require_permission("ai.security.manage")
          end

          def service
            @service ||= ::Ai::Security::AgentIdentityService.new(account: current_account)
          end

          def identity_json(identity)
            {
              id: identity.id,
              agent_id: identity.agent_id,
              key_fingerprint: identity.key_fingerprint,
              algorithm: identity.algorithm,
              status: identity.status,
              agent_uri: identity.agent_uri,
              attestation_claims: identity.attestation_claims,
              capabilities: identity.capabilities,
              rotated_at: identity.rotated_at&.iso8601,
              revoked_at: identity.revoked_at&.iso8601,
              revocation_reason: identity.revocation_reason,
              rotation_overlap_until: identity.rotation_overlap_until&.iso8601,
              expires_at: identity.expires_at&.iso8601,
              created_at: identity.created_at.iso8601,
              updated_at: identity.updated_at.iso8601
            }
          end
        end
      end
    end
  end
end

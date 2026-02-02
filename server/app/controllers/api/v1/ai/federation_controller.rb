# frozen_string_literal: true

module Api
  module V1
    module Ai
      class FederationController < ApplicationController
        include AuditLogging

        before_action :set_partner, only: %i[show update destroy verify agents sync]

        # GET /api/v1/ai/federation/partners
        def index
          scope = current_user.account.federation_partners

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.active if params[:active] == "true"

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:partner_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("ai.federation.list", current_user.account)
        end

        # GET /api/v1/ai/federation/partners/:id
        def show
          render_success(partner: @partner.partner_details)
          log_audit_event("ai.federation.read", @partner)
        end

        # POST /api/v1/ai/federation/partners
        # Register a new federation partner
        def create
          partner = current_user.account.federation_partners.build(partner_params)
          partner.initiated_by = current_user

          # Generate federation key if not provided
          partner.federation_key ||= SecureRandom.urlsafe_base64(32)

          if partner.save
            render_success({ partner: partner.partner_details }, status: :created)
            log_audit_event("ai.federation.register", partner)
          else
            render_error(partner.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/ai/federation/partners/:id
        def update
          if @partner.update(partner_params)
            render_success(partner: @partner.partner_details)
            log_audit_event("ai.federation.update", @partner)
          else
            render_error(@partner.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/ai/federation/partners/:id
        def destroy
          @partner.destroy!
          render_success(message: "Federation partner removed")
          log_audit_event("ai.federation.delete", @partner)
        end

        # POST /api/v1/ai/federation/partners/:id/verify
        # Verify federation partner connection
        def verify
          result = @partner.verify_connection!

          if result[:success]
            render_success(
              message: "Federation partner verified",
              partner: @partner.reload.partner_details
            )
            log_audit_event("ai.federation.verify", @partner)
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        # GET /api/v1/ai/federation/partners/:id/agents
        # List agents available from this federation partner
        def agents
          unless @partner.verified?
            render_error("Partner must be verified first", status: :unprocessable_entity)
            return
          end

          result = @partner.fetch_agents(
            category: params[:category],
            query: params[:query]
          )

          if result[:success]
            render_success(agents: result[:agents])
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/federation/partners/:id/sync
        # Sync agent catalog from federation partner
        def sync
          result = @partner.sync_agents!

          if result[:success]
            render_success(
              message: "Synced #{result[:count]} agents",
              partner: @partner.reload.partner_details
            )
            log_audit_event("ai.federation.sync", @partner)
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/federation/register
        # External endpoint for other organizations to register with us
        def register_external
          # Validate the incoming registration request
          unless params[:organization_name].present? && params[:endpoint_url].present?
            render_error("organization_name and endpoint_url are required", status: :unprocessable_entity)
            return
          end

          # Find or create the federation partner record
          partner = FederationPartner.find_or_initialize_by(
            endpoint_url: params[:endpoint_url]
          )

          partner.assign_attributes(
            organization_name: params[:organization_name],
            organization_id: params[:organization_id],
            contact_email: params[:contact_email],
            federation_key: params[:federation_key],
            mtls_certificate: params[:mtls_certificate],
            status: "pending_verification"
          )

          if partner.save
            render_success(
              message: "Registration received",
              federation_key: partner.federation_key,
              status: partner.status
            )
          else
            render_error(partner.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/federation/verify_key
        # Verify a federation key from another organization
        def verify_key
          partner = FederationPartner.find_by(federation_key: params[:federation_key])

          if partner&.active?
            render_success(
              valid: true,
              organization_name: partner.organization_name,
              organization_id: partner.organization_id
            )
          else
            render_success(valid: false)
          end
        end

        # GET /api/v1/ai/federation/discover
        # Discover all agents across federated partners
        def discover
          agents = []

          current_user.account.federation_partners.active.verified.find_each do |partner|
            result = partner.fetch_agents(
              category: params[:category],
              query: params[:query]
            )

            if result[:success]
              agents.concat(result[:agents].map { |a| a.merge(federation_partner_id: partner.id) })
            end
          end

          # Sort by reputation/rating
          agents.sort_by! { |a| -(a[:reputation_score] || 0) }

          # Apply limit
          agents = agents.first(params[:limit]&.to_i || 50)

          render_success(agents: agents)
        end

        private

        def set_partner
          @partner = current_user.account.federation_partners.find(params[:id])
        end

        def partner_params
          params.require(:partner).permit(
            :organization_name,
            :organization_id,
            :endpoint_url,
            :contact_email,
            :federation_key,
            :mtls_certificate,
            :status,
            :trust_level,
            allowed_skills: [],
            configuration: {}
          )
        end
      end
    end
  end
end

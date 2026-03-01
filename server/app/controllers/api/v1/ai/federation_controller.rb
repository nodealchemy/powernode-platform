# frozen_string_literal: true

module Api
  module V1
    module Ai
      class FederationController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_partner, only: %i[show update destroy verify agents sync]
        before_action :validate_permissions

        # GET /api/v1/ai/federation/partners
        def index
          scope = current_user.account.federation_partners

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.active if params[:active] == "true"

          # Sorting and pagination
          scope = scope.order("federation_partners.created_at DESC")
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

          if partner.save
            render_success({ partner: partner.partner_details }, status: :created)
            log_audit_event("ai.federation.register", partner)
          else
            render_error(partner.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/ai/federation/partners/:id
        def update
          if @partner.update(partner_params)
            render_success(partner: @partner.partner_details)
            log_audit_event("ai.federation.update", @partner)
          else
            render_error(@partner.errors.full_messages, status: :unprocessable_content)
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
            render_success(data: {
              message: "Federation partner verified",
              partner: @partner.reload.partner_details
            })
            log_audit_event("ai.federation.verify", @partner)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/federation/partners/:id/agents
        # List agents available from this federation partner
        def agents
          unless @partner.verified?
            render_error("Partner must be verified first", status: :unprocessable_content)
            return
          end

          result = @partner.fetch_agents(
            category: params[:category],
            query: params[:query]
          )

          if result[:success]
            render_success(agents: result[:agents])
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/federation/partners/:id/sync
        # Sync agent catalog from federation partner
        def sync
          result = @partner.sync_agents!

          if result[:success]
            render_success(data: {
              message: "Synced #{result[:count] || result[:synced]} agents",
              partner: @partner.reload.partner_details
            })
            log_audit_event("ai.federation.sync", @partner)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/federation/register
        # External endpoint for other organizations to register with us
        def register_external
          # Validate the incoming registration request
          unless params[:organization_name].present? && params[:endpoint_url].present?
            render_error("organization_name and endpoint_url are required", status: :unprocessable_content)
            return
          end

          # Find or create the federation partner record
          partner = FederationPartner.find_or_initialize_by(
            endpoint_url: params[:endpoint_url]
          )

          partner.account ||= current_user.account
          partner.assign_attributes(
            organization_name: params[:organization_name],
            organization_id: params[:organization_id] || "ext-#{SecureRandom.hex(8)}",
            tls_config: (partner.tls_config || {}).merge(
              "contact_email" => params[:contact_email],
              "mtls_certificate" => params[:mtls_certificate]
            ).compact,
            status: "pending"
          )

          if partner.save
            render_success({
              message: "Registration received",
              federation_key: partner.organization_id,
              status: partner.status
            })
          else
            render_error(partner.errors.full_messages, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/federation/verify_key
        # Verify a federation key from another organization
        def verify_key
          partner = FederationPartner.find_by(organization_id: params[:federation_key])

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

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "agents", "discover"
            require_permission("ai.federation.read")
          when "create"
            require_permission("ai.federation.create")
          when "update"
            require_permission("ai.federation.update")
          when "destroy"
            require_permission("ai.federation.delete")
          when "verify", "verify_key"
            require_permission("ai.federation.verify")
          when "sync", "register_external"
            require_permission("ai.federation.sync")
          end
        end

        def set_partner
          @partner = current_user.account.federation_partners.find(params[:id])
        end

        def partner_params
          permitted = params.require(:partner).permit(
            :organization_name,
            :organization_id,
            :endpoint_url,
            :status,
            :trust_level,
            :contact_email,
            allowed_capabilities: []
          )

          # Store contact_email in tls_config if provided
          if permitted[:contact_email].present?
            contact_email = permitted.delete(:contact_email)
            permitted[:tls_config] = (@partner&.tls_config || {}).merge("contact_email" => contact_email)
          end

          permitted
        end
      end
    end
  end
end

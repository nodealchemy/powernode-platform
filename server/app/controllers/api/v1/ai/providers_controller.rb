# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ProvidersController < ApplicationController
        include AuditLogging

        # metadata keys only the server writes: params can neither set nor erase them.
        SERVER_METADATA_KEYS = %w[
          claimed_from is_default execution_source model_sync_pending_at
          last_sync_error last_sync_failed_at last_sync_skipped_at last_sync_skipped_reason
        ].freeze
        include ::Ai::ProviderSerialization

        before_action :set_provider, only: [
          :show, :update, :destroy,
          :models, :usage_summary, :check_availability, :make_default, :release
        ]
        before_action :validate_permissions

        # GET /api/v1/ai/providers
        def index
          account = current_account || current_user&.account
          return render_error("No account context", status: :unauthorized) unless account

          providers = account.ai_providers.includes(:provider_credentials)

          providers = providers.active unless current_worker || current_user&.has_permission?("admin.ai.providers.read")

          providers = apply_provider_filters(providers)
          providers = apply_sorting(providers)
          providers = apply_pagination(providers)

          render_success({
            items: providers.map { |p| serialize_provider(p) },
            pagination: pagination_data(providers)
          })

          log_audit_event("ai.providers.read", current_user.account)
        end

        # GET /api/v1/ai/providers/:id
        def show
          render_success({
            provider: serialize_provider_detail(@provider)
          })

          log_audit_event("ai.providers.read", @provider)
        end

        # POST /api/v1/ai/providers
        def create
          attrs = ::Ai::ProviderCatalog.merge_defaults(provider_params.to_h)

          # The wizard adds one provider per entry. It first claims a same-type
          # row nobody has configured (a seeded catalog row), taking the entry's
          # name and base URL; only when every same-type row is configured does
          # it add a row, numbering the name if it is taken.
          claimed = nil
          saved = false
          # Claim and save are one transaction, and the claim locks the row it
          # takes (SKIP LOCKED), so two concurrent entries never share a row.
          ::Ai::Provider.transaction do
            claimed = params[:dedupe_name].present? ? claim_unconfigured_provider(attrs) : nil
            @provider = claimed || ::Ai::Provider.new(attrs).tap do |new_provider|
              new_provider.account = current_user.account
              new_provider.name = unique_provider_name(new_provider.name) if params[:dedupe_name].present?
            end
            saved = @provider.save
            raise ActiveRecord::Rollback unless saved
          end

          if saved
            # A provider syncs its models the moment it is added, on every
            # creation path. Types that need a credential defer until one is
            # saved (the credential create syncs again).
            sync = ::Ai::Providers::ModelSyncAndActivate.call(@provider, activate: false, preserve_on_failure: true, budget: true)

            render_success({
              provider: serialize_provider_detail(@provider.reload),
              model_sync: sync.to_h,
              claimed: claimed.present?
            }, status: :created)

            log_audit_event("ai.providers.create", @provider,
              provider_type: @provider.provider_type
            )
          else
            render_validation_error(@provider.errors)
          end
        end

        # PATCH /api/v1/ai/providers/:id
        # A connection edit (base URL, endpoint, type) or turning the provider
        # on syncs its models inline (Ai::Providers::UpdateWithModelSync).
        # Enabling activates only on a sync that returned models; otherwise the
        # other edits stay saved and the answer is 422 with the sync's reason.
        def update
          attrs = provider_params
          if attrs.key?(:metadata)
            # A metadata replace must not erase the server-owned markers.
            attrs[:metadata] = (attrs[:metadata].to_h).merge((@provider.metadata || {}).slice(*SERVER_METADATA_KEYS))
          end

          outcome = ::Ai::Providers::UpdateWithModelSync.call(@provider, attrs)
          return render_validation_error(@provider.errors) unless outcome.saved

          log_audit_event("ai.providers.update", @provider, changes: outcome.changes)
          payload = { provider: serialize_provider_detail(@provider), model_sync: outcome.sync&.to_h }.compact

          if outcome.activation_failed
            render_error(outcome.message, status: :unprocessable_content, code: "model_sync_failed", details: payload)
          else
            render_success(payload)
          end
        end

        # DELETE /api/v1/ai/providers/:id
        def destroy
          provider_name = @provider.name
          blockers = []
          destroyed = false

          # Release the agents and destroy the provider in ONE transaction: a
          # refused delete leaves every clone where it was.
          ::Ai::Provider.transaction do
            blockers = ::Ai::ProviderDefaultService.release_clones!(@provider)
            raise ActiveRecord::Rollback if blockers.any?

            destroyed = @provider.destroy.present?
            raise ActiveRecord::Rollback unless destroyed
          end

          if blockers.any?
            render_error(
              "Cannot delete this provider: still used by #{blockers.map(&:name).to_sentence}. Move or remove those agents first.",
              status: :conflict
            )
          elsif destroyed
            render_success({ message: "AI provider deleted successfully" })

            log_audit_event("ai.providers.delete", current_user.account,
              provider_name: provider_name
            )
          elsif @provider.errors.any?
            render_validation_error(@provider.errors)
          else
            render_error("Failed to delete provider", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/providers/:id/models
        def models
          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            models: @provider.supported_models || [],
            count: @provider.supported_models&.length || 0
          })
        end

        # GET /api/v1/ai/providers/:id/usage_summary
        def usage_summary
          period_days = params[:period]&.to_i || 30
          period = period_days.days

          summary = ::Ai::ProviderManagementService.provider_usage_summary(
            @provider,
            current_user.account,
            period
          )

          render_success({
            provider: serialize_provider(@provider),
            usage_summary: summary,
            period: {
              days: period_days,
              start_date: period_days.days.ago.to_date,
              end_date: Date.current
            }
          })
        end

        # POST /api/v1/ai/providers/:id/release
        # Gives back a seeded row the setup wizard claimed (it did not create
        # it): the catalog name and base URL return, its credentials go, the
        # default flag clears, and the row stays. A row the wizard created is
        # deleted instead.
        def release
          origin = @provider.metadata&.dig("claimed_from")
          unless origin
            return render_error("This provider was not claimed by the setup wizard", status: :unprocessable_content)
          end
          # Only the wizard's own credential may go: a row with more has been
          # worked on since and is no longer the wizard's to give back.
          if @provider.provider_credentials.count > 1
            return render_error("This provider has other credentials and cannot be released", status: :unprocessable_content)
          end

          ::Ai::Provider.transaction do
            @provider.provider_credentials.find_each do |credential|
              # Through the model, so each removal is audited; the only-credential
              # guard is for operators, not for giving a claimed row back.
              credential.skip_last_credential_guard = true
              credential.destroy!
              log_audit_event("ai.providers.credential.delete", credential, provider_name: @provider.name)
            end
            @provider.update_columns(
              name: origin["name"],
              api_base_url: origin["api_base_url"],
              metadata: @provider.metadata.except("claimed_from").merge("is_default" => false),
              updated_at: Time.current
            )
          end
          ::Ai::ProviderDefaultService.heal!(@provider.account)

          render_success({ provider: serialize_provider_detail(@provider.reload) })

          log_audit_event("ai.providers.release", @provider, provider_type: @provider.provider_type)
        end

        # POST /api/v1/ai/providers/:id/make_default
        # The operator's default provider, on the existing priority_order /
        # is_default mechanism. Only a working provider qualifies.
        def make_default
          ::Ai::ProviderDefaultService.set_default!(@provider)

          render_success({ provider: serialize_provider_detail(@provider.reload) })

          log_audit_event("ai.providers.make_default", @provider, provider_type: @provider.provider_type)
        rescue ::Ai::ProviderDefaultService::NotEligible => e
          render_error("Cannot make this provider the default: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/ai/providers/catalog
        # Read-only provider-type catalog used to auto-fill the provider form.
        def catalog
          render_success({
            items: ::Ai::ProviderCatalog.form_entries,
            known_capabilities: ::Ai::Provider::KNOWN_CAPABILITIES
          })
        end

        # GET /api/v1/ai/providers/available
        def available
          providers = ::Ai::ProviderManagementService.get_available_providers_for_account(current_user.account)

          render_success({
            providers: providers.map { |p| serialize_provider(p) },
            count: providers.count
          })
        end

        # GET /api/v1/ai/providers/statistics
        def statistics
          providers = current_user.account.ai_providers

          stats = {
            total_providers: providers.count,
            active_providers: providers.where(is_active: true).count,
            providers_by_type: providers.group(:provider_type).count,
            total_credentials: ::Ai::ProviderCredential.joins(:provider)
                                                  .where(ai_providers: { account_id: current_user.account_id })
                                                  .count,
            total_api_calls: calculate_total_api_calls,
            total_cost: calculate_total_cost
          }

          render_success({ statistics: stats })
        end

        # GET /api/v1/ai/providers/:id/check_availability
        def check_availability
          availability_result = ProviderAvailabilityService.check_provider(@provider)

          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            availability: {
              available: availability_result[:available],
              reason: availability_result[:reason],
              is_active: @provider.is_active?,
              is_healthy: @provider.healthy?,
              has_credentials: @provider.provider_credentials.where(is_active: true).exists?,
              has_models: @provider.available_models.any?,
              health_status: @provider.health_status
            }
          })
        end

        private

        # A same-type, routable row with no credential and no operator
        # customisation (not the default, never synced). Its name and base URL
        # become the entry's.
        def claim_unconfigured_provider(attrs)
          type = attrs[:provider_type] || attrs["provider_type"]
          return nil if type.blank?

          ids = current_user.account.ai_providers.platform_routable.where(provider_type: type)
                            .where.not(id: ::Ai::ProviderCredential.select(:ai_provider_id))
                            .order(:priority_order, :name).pluck(:id)
          candidate = nil
          ids.each do |id|
            # Lock one row at a time and skip any another request holds.
            row = ::Ai::Provider.where(id: id).lock("FOR UPDATE SKIP LOCKED").first
            next unless row

            meta = row.metadata || {}
            # A deferred sync (last_sync_skipped_*) is what an untouched row looks
            # like; a recorded failure, a default flag or an earlier claim is
            # someone's choice.
            next if meta["is_default"] == true || meta.key?("claimed_from")
            next unless (meta.keys & %w[last_sync_error last_sync_failed_at]).empty?

            candidate = row
            break
          end
          return nil unless candidate

          # Remember what the row was, so a release can restore it.
          candidate.metadata = (candidate.metadata || {}).merge(
            "claimed_from" => { "name" => candidate.name, "api_base_url" => candidate.api_base_url }
          )
          requested = attrs[:name] || attrs["name"]
          candidate.name = unique_provider_name(requested, except: candidate) if requested.present?
          base_url = attrs[:api_base_url] || attrs["api_base_url"]
          candidate.api_base_url = base_url if base_url.present?
          candidate
        end

        def unique_provider_name(name, except: nil)
          taken = current_user.account.ai_providers.where.not(id: except&.id).pluck(:name).to_set
          return name unless taken.include?(name)

          suffix = 2
          suffix += 1 while taken.include?("#{name} (#{suffix})")
          "#{name} (#{suffix})"
        end

        def set_provider
          scope = current_account&.ai_providers || current_user&.account&.ai_providers
          return render_error("No account context", status: :unauthorized) unless scope

          @provider = scope.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "available", "catalog", "statistics", "models", "usage_summary", "check_availability"
            require_permission("ai.providers.read")
          when "create"
            require_permission("ai.providers.create")
          when "update", "make_default"
            require_permission("ai.providers.update")
          when "release"
            require_permission("ai.providers.update")
            require_permission("ai.credentials.delete")
          when "destroy"
            require_permission("ai.providers.delete")
          end
        end

        def provider_params
          permitted = params.require(:provider).permit(
            :name, :provider_type, :api_base_url, :is_active,
            :priority_order, :description, :api_endpoint, :documentation_url,
            :status_url, :requires_auth, :supports_streaming, :supports_functions,
            :supports_vision, :supports_code_execution, :slug,
            capabilities: [],
            supported_models: [ :name, :id, :context_length, :max_output_tokens, :cost_per_token,
                              { cost_per_1k_tokens: [ :input, :output ] }, :capabilities, :features,
                              :default_parameters ],
            default_parameters: {},
            rate_limits: {},
            pricing_info: {},
            configuration_schema: {},
            metadata: {}
          )
          # Server-owned markers (the default flag, the Claude Code scope, the
          # wizard claim, sync bookkeeping) are never written from params.
          if permitted[:metadata].respond_to?(:except)
            permitted[:metadata] = permitted[:metadata].except(*SERVER_METADATA_KEYS)
          end
          permitted
        end

        def apply_provider_filters(providers)
          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?
          providers = providers.platform_routable if params[:platform_routable].present?
          providers = providers.supporting_capability(params[:capability]) if params[:capability].present?
          providers = providers.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?
          providers
        end

        def apply_sorting(collection)
          sort = params[:sort] || "priority"

          case sort
          when "name"
            collection.order(:name)
          when "priority"
            collection.order(:priority_order, :name)
          when "created_at"
            collection.order(created_at: :desc)
          else
            collection.ordered_by_priority rescue collection.order(:name)
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        def calculate_total_api_calls
          ::Ai::AgentExecution.joins(agent: :provider)
                              .where(ai_providers: { account_id: current_user.account_id })
                              .count
        end

        def calculate_total_cost
          ::Ai::AgentExecution.joins(agent: :provider)
                              .where(ai_providers: { account_id: current_user.account_id })
                              .sum(:cost_usd)
                              .round(2)
        end
      end
    end
  end
end

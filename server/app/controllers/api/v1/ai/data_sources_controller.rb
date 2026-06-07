# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DataSourcesController < ApplicationController
        include AuditLogging
        include ::Ai::DataSourceSerialization
        include ::Ai::DataSourceEndpoints

        before_action :set_data_source, only: [
          :show, :update, :destroy,
          :test_connection, :quota_status,
          :endpoints_index, :endpoints_create, :endpoints_update,
          :endpoints_destroy, :endpoints_query,
          :schema_history, :quality, :contract, :introspect,
          :subscriptions_index, :subscriptions_create, :subscriptions_destroy
        ]
        before_action :set_endpoint, only: [
          :endpoints_update, :endpoints_destroy, :endpoints_query,
          :schema_history, :quality, :contract
        ]
        before_action :validate_permissions

        # GET /api/v1/ai/data_sources
        def index
          account = current_account || current_user&.account
          return render_error("No account context", status: :unauthorized) unless account

          data_sources = account.ai_data_sources.includes(:credentials)
          data_sources = apply_filters(data_sources)
          data_sources = apply_sorting(data_sources)
          data_sources = apply_pagination(data_sources)

          render_success({
            items: data_sources.map { |ds| serialize_data_source(ds) },
            pagination: pagination_data(data_sources)
          })
        end

        # POST /api/v1/ai/data_sources/discover
        # Semantic discovery: rank the account's data sources by relevance to a
        # natural-language need, blended with effectiveness/health/recency signals.
        def discover
          account = current_account || current_user&.account
          return render_error("No account context", status: :unauthorized) unless account

          query = params[:query].to_s
          return render_error("query is required", status: :unprocessable_entity) if query.blank?

          ranked = ::Ai::DataSources::SemanticDiscoveryService.new(account).discover(
            query: query,
            limit: (params[:limit] || 10).to_i.clamp(1, 50),
            rerank: ActiveModel::Type::Boolean.new.cast(params[:rerank])
          )

          render_success({
            query: query,
            count: ranked.size,
            results: ranked.map do |r|
              serialize_data_source(r[:data_source]).merge(
                score: r[:score],
                signals: r[:signals]
              )
            end
          })
        end

        # GET /api/v1/ai/data_sources/:id
        def show
          render_success({
            data_source: serialize_data_source_detail(@data_source)
          })
        end

        # POST /api/v1/ai/data_sources
        def create
          @data_source = ::Ai::DataSource.new(data_source_params)
          @data_source.account = current_user.account

          if @data_source.save
            render_success({
              data_source: serialize_data_source_detail(@data_source)
            }, status: :created)

            log_audit_event("ai.data_sources.create", @data_source,
              source_type: @data_source.source_type
            )
          else
            render_validation_error(@data_source.errors)
          end
        end

        # PATCH /api/v1/ai/data_sources/:id
        def update
          if @data_source.update(data_source_params)
            render_success({
              data_source: serialize_data_source_detail(@data_source)
            })

            log_audit_event("ai.data_sources.update", @data_source,
              changes: @data_source.previous_changes.keys
            )
          else
            render_validation_error(@data_source.errors)
          end
        end

        # DELETE /api/v1/ai/data_sources/:id
        def destroy
          ds_name = @data_source.name

          if @data_source.destroy
            render_success({ message: "Data source deleted successfully" })

            log_audit_event("ai.data_sources.delete", current_user.account,
              data_source_name: ds_name
            )
          else
            if @data_source.errors.any?
              render_validation_error(@data_source.errors)
            else
              render_error("Failed to delete data source", status: :unprocessable_content)
            end
          end
        end

        # POST /api/v1/ai/data_sources/:id/test_connection
        def test_connection
          credential = @data_source.active_credential

          unless credential
            return render_error("No active credential available for testing", status: :unprocessable_content)
          end

          begin
            uri = URI.parse(@data_source.api_base_url.to_s)
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "https")
            http.open_timeout = 10
            http.read_timeout = 10

            request = Net::HTTP::Get.new(uri)
            request["User-Agent"] = "Powernode/1.0"
            request["Accept"] = "application/json"

            if @data_source.requires_auth && credential.decrypted_api_key.present?
              request["Authorization"] = "Bearer #{credential.decrypted_api_key}"
            end

            response = http.request(request)
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

            success = response.code.to_i < 400

            if success
              credential.record_success!
            else
              credential.record_failure!("HTTP #{response.code}: #{response.message}")
            end

            render_success({
              success: success,
              status_code: response.code.to_i,
              response_time_ms: elapsed_ms,
              message: success ? "Connection successful" : "Connection failed: HTTP #{response.code}"
            })

            log_audit_event("ai.data_sources.test_connection", @data_source, success: success)
          rescue StandardError => e
            credential.record_failure!(e.message)

            render_success({
              success: false,
              error: e.message,
              message: "Connection failed: #{e.class.name}"
            })
          end
        end

        # GET /api/v1/ai/data_sources/:id/quota_status
        def quota_status
          render_success({
            data_source: {
              id: @data_source.id,
              name: @data_source.name,
              source_type: @data_source.source_type
            },
            quota: @data_source.quota_summary,
            check: @data_source.check_quota!
          })
        end

        private

        def set_data_source
          scope = current_account&.ai_data_sources || current_user&.account&.ai_data_sources
          return render_error("No account context", status: :unauthorized) unless scope

          # Nested endpoint routes key the source on :data_source_id; the top-level
          # member routes use :id.
          @data_source = scope.find(params[:data_source_id] || params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data source not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "quota_status", "endpoints_index", "discover", "subscriptions_index"
            require_permission("ai.data_sources.read")
          when "create"
            require_permission("ai.data_sources.create")
          when "update"
            require_permission("ai.data_sources.update")
          when "destroy"
            require_permission("ai.data_sources.delete")
          when "test_connection"
            require_permission("ai.data_sources.read")
          when "endpoints_create", "endpoints_update", "endpoints_destroy"
            # Endpoint mutations are data-source updates — managing the source's
            # endpoints requires update authority (or the manage super-grant).
            require_any_permission("ai.data_sources.update", "ai.data_sources.manage")
          when "endpoints_query"
            require_permission("ai.data_sources.query")
          when "schema_history", "quality", "contract"
            # Phase 2b read-only observability — same read grant as index/show.
            require_permission("ai.data_sources.read")
          when "subscriptions_create", "subscriptions_destroy"
            # Phase 3 — creating/cancelling a pull-based subscription is gated by
            # the stream grant (same as the MCP data_source_subscribe action).
            require_permission("ai.data_sources.stream")
          when "introspect"
            # OpenAPI import creates endpoints (even dry_run is a write surface),
            # so it is gated by the manage super-grant.
            require_permission("ai.data_sources.manage")
          end
        end

        def data_source_params
          params.require(:data_source).permit(
            :name, :slug, :source_type, :category, :protocol, :description, :api_base_url,
            :is_active, :requires_auth, :priority_order, :documentation_url,
            :respect_robots, :crawl_delay_seconds,
            capabilities: [],
            configuration: {},
            rate_limits: {},
            default_parameters: {},
            metadata: {}
          )
        end

        def apply_filters(data_sources)
          data_sources = data_sources.where(source_type: params[:source_type]) if params[:source_type].present?
          data_sources = data_sources.by_category(params[:category]) if params[:category].present?
          data_sources = data_sources.where(is_active: params[:is_active]) if params[:is_active].present?
          if params[:search].present?
            data_sources = data_sources.where(
              "name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
            )
          end
          data_sources
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
            collection.ordered_by_priority
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [params[:per_page]&.to_i || 20, 100].min

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
      end
    end
  end
end

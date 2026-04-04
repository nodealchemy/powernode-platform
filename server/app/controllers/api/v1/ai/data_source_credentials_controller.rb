# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DataSourceCredentialsController < ApplicationController
        include AuditLogging
        include ::Ai::DataSourceSerialization

        before_action :set_data_source
        before_action :set_credential, only: [:show, :update, :destroy, :test, :make_default]
        before_action :validate_permissions

        # GET /api/v1/ai/data_sources/:data_source_id/credentials
        def index
          credentials = @data_source.credentials
          credentials = apply_credential_filters(credentials)
          credentials = apply_pagination(credentials)

          render_success({
            credentials: credentials.map { |c| serialize_data_source_credential(c) },
            pagination: pagination_data(credentials),
            total_count: credentials.total_count
          })
        end

        # GET /api/v1/ai/data_sources/:data_source_id/credentials/:id
        def show
          render_success({
            credential: serialize_data_source_credential(@credential)
          })
        end

        # POST /api/v1/ai/data_sources/:data_source_id/credentials
        def create
          @credential = @data_source.credentials.build(credential_params)
          @credential.account = current_user.account

          if @credential.save
            render_success({
              credential: serialize_data_source_credential(@credential)
            }, status: :created)

            log_audit_event("ai.data_sources.credential.create", @credential,
              data_source_name: @data_source.name
            )
          else
            render_validation_error(@credential.errors)
          end
        end

        # PATCH /api/v1/ai/data_sources/:data_source_id/credentials/:id
        def update
          if @credential.update(credential_params)
            render_success({
              credential: serialize_data_source_credential(@credential),
              message: "Credential updated successfully"
            })

            log_audit_event("ai.data_sources.credential.update", @credential,
              changes: @credential.previous_changes.keys
            )
          else
            render_validation_error(@credential.errors)
          end
        end

        # DELETE /api/v1/ai/data_sources/:data_source_id/credentials/:id
        def destroy
          credential_name = @credential.name
          ds_name = @data_source.name

          if @credential.destroy
            render_success({ message: "Credential deleted successfully" })

            log_audit_event("ai.data_sources.credential.delete", current_user.account,
              credential_name: credential_name,
              data_source_name: ds_name
            )
          else
            if @credential.errors.any?
              render_validation_error(@credential.errors)
            else
              render_error("Failed to delete credential", status: :unprocessable_content)
            end
          end
        end

        # POST /api/v1/ai/data_sources/:data_source_id/credentials/:id/test
        def test
          unless @credential.healthy?
            return render_error("Credential is not healthy (expired or too many failures)", status: :unprocessable_content)
          end

          begin
            ds = @credential.data_source
            uri = URI.parse(ds.api_base_url.to_s)
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "https")
            http.open_timeout = 10
            http.read_timeout = 10

            request = Net::HTTP::Get.new(uri)
            request["User-Agent"] = "Powernode/1.0"
            request["Accept"] = "application/json"

            if ds.requires_auth && @credential.decrypted_api_key.present?
              request["Authorization"] = "Bearer #{@credential.decrypted_api_key}"
            end

            response = http.request(request)
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

            success = response.code.to_i < 400

            if success
              @credential.record_success!
            else
              @credential.record_failure!("HTTP #{response.code}: #{response.message}")
            end

            render_success({
              success: success,
              status_code: response.code.to_i,
              response_time_ms: elapsed_ms,
              message: success ? "Credential test successful" : "Credential test failed: HTTP #{response.code}"
            })

            log_audit_event("ai.data_sources.credential.test", @credential, success: success)
          rescue StandardError => e
            @credential.record_failure!(e.message)

            render_success({
              success: false,
              error: e.message,
              message: "Credential test failed: #{e.class.name}"
            })
          end
        end

        # POST /api/v1/ai/data_sources/:data_source_id/credentials/:id/make_default
        def make_default
          @credential.make_default!

          render_success({
            credential: serialize_data_source_credential(@credential.reload),
            message: "Credential set as default"
          })

          log_audit_event("ai.data_sources.credential.make_default", @credential)
        end

        private

        def set_data_source
          return if current_worker

          @data_source = current_user.account.ai_data_sources.find(params[:data_source_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data source not found", status: :not_found)
        end

        def set_credential
          @credential = @data_source.credentials
                                    .where(account_id: current_user.account_id)
                                    .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Credential not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show"
            require_permission("ai.data_sources.read")
          when "create"
            require_permission("ai.data_sources.create")
          when "update", "make_default"
            require_permission("ai.data_sources.update")
          when "destroy"
            require_permission("ai.data_sources.delete")
          when "test"
            require_permission("ai.data_sources.read")
          end
        end

        def credential_params
          params.require(:credential).permit(
            :name, :is_active, :is_default, :expires_at,
            :encrypted_api_key, :encrypted_api_secret,
            rate_limits: {}
          )
        end

        def apply_credential_filters(credentials)
          credentials = credentials.where(is_active: params[:active]) if params[:active].present?
          credentials = credentials.where(is_default: true) if params[:default_only] == "true"
          if params[:search].present?
            credentials = credentials.where(
              "name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
            )
          end
          credentials
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

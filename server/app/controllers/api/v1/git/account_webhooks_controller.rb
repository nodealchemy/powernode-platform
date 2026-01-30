# frozen_string_literal: true

module Api
  module V1
    module Git
      class AccountWebhooksController < ApplicationController
        before_action :set_webhook, only: %i[show update destroy test toggle_status regenerate_secret]
        before_action :validate_permissions

        # GET /api/v1/git/account_webhooks
        def index
          webhooks = current_user.account.account_git_webhook_configs

          # Filters
          webhooks = webhooks.where(status: params[:status]) if params[:status].present?

          if params[:search].present?
            search = "%#{params[:search]}%"
            webhooks = webhooks.where("name ILIKE ? OR url ILIKE ?", search, search)
          end

          # Pagination
          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 50].min, 10].max
          total = webhooks.count
          webhooks = webhooks.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

          render_success({
            webhooks: webhooks.map { |w| serialize_webhook(w) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total
            }
          })
        end

        # GET /api/v1/git/account_webhooks/:id
        def show
          render_success({ webhook: serialize_webhook_detail(@webhook) })
        end

        # POST /api/v1/git/account_webhooks
        def create
          webhook = current_user.account.account_git_webhook_configs.new(webhook_params)
          webhook.created_by = current_user

          if webhook.save
            render_success({ webhook: serialize_webhook_detail(webhook) }, status: :created)
          else
            render_validation_error(webhook.errors)
          end
        end

        # PATCH/PUT /api/v1/git/account_webhooks/:id
        def update
          if @webhook.update(webhook_params)
            render_success({ webhook: serialize_webhook_detail(@webhook) })
          else
            render_validation_error(@webhook.errors)
          end
        end

        # DELETE /api/v1/git/account_webhooks/:id
        def destroy
          @webhook.destroy!
          render_success({ message: "Account webhook deleted successfully" })
        end

        # POST /api/v1/git/account_webhooks/:id/test
        def test
          test_payload = {
            event_type: "test.webhook",
            timestamp: Time.current.iso8601,
            account_id: current_user.account.id,
            webhook_config_id: @webhook.id,
            message: "This is a test webhook delivery from Powernode"
          }

          # Queue test delivery
          begin
            WorkerApiClient.new.deliver_account_webhook(
              webhook_config_id: @webhook.id,
              payload: test_payload,
              event_type: "test.webhook"
            )

            render_success({
              message: "Test webhook queued for delivery",
              test_payload: test_payload
            })
          rescue WorkerApiClient::ApiError => e
            render_error("Failed to queue test webhook: #{e.message}", status: :service_unavailable)
          end
        end

        # POST /api/v1/git/account_webhooks/:id/toggle_status
        def toggle_status
          new_status = @webhook.active? ? "inactive" : "active"
          @webhook.update!(status: new_status, is_active: new_status == "active")

          render_success({
            webhook: serialize_webhook(@webhook),
            message: "Webhook #{new_status == 'active' ? 'activated' : 'deactivated'} successfully"
          })
        end

        # POST /api/v1/git/account_webhooks/:id/regenerate_secret
        def regenerate_secret
          @webhook.regenerate_secret!

          render_success({
            webhook: serialize_webhook_detail(@webhook),
            message: "Secret regenerated successfully"
          })
        end

        # GET /api/v1/git/account_webhooks/available_events
        def available_events
          render_success({
            event_types: Devops::AccountGitWebhookConfig::EVENT_TYPES,
            event_categories: {
              "Git Events" => %w[push pull_request pull_request_review merge_request],
              "Issues & PRs" => %w[issues issue_comment pull_request_review_comment],
              "Repository Events" => %w[create delete fork release],
              "CI/CD Events" => %w[workflow_run workflow_job deployment deployment_status],
              "Checks & Status" => %w[check_run check_suite status],
              "Other" => %w[ping]
            }
          })
        end

        private

        def set_webhook
          @webhook = current_user.account.account_git_webhook_configs.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Account webhook not found", status: :not_found)
        end

        def validate_permissions
          require_permission("git.account_webhooks.manage")
        end

        def webhook_params
          params.permit(
            :name,
            :url,
            :description,
            :status,
            :is_active,
            :branch_filter,
            :branch_filter_type,
            :content_type,
            :timeout_seconds,
            :retry_limit,
            :retry_backoff,
            event_types: [],
            custom_headers: {}
          )
        end

        def serialize_webhook(webhook)
          {
            id: webhook.id,
            name: webhook.name,
            url: webhook.url,
            description: webhook.description,
            status: webhook.status,
            is_active: webhook.is_active,
            event_types: webhook.event_types,
            branch_filter: webhook.branch_filter,
            branch_filter_type: webhook.branch_filter_type,
            branch_filter_enabled: webhook.branch_filter_enabled?,
            content_type: webhook.content_type,
            timeout_seconds: webhook.timeout_seconds,
            retry_limit: webhook.retry_limit,
            retry_backoff: webhook.retry_backoff,
            custom_headers_count: webhook.custom_headers&.keys&.length || 0,
            success_count: webhook.success_count,
            failure_count: webhook.failure_count,
            success_rate: webhook.success_rate,
            health_status: webhook.health_status,
            last_delivery_at: webhook.last_delivery_at&.iso8601,
            created_at: webhook.created_at.iso8601,
            updated_at: webhook.updated_at.iso8601
          }
        end

        def serialize_webhook_detail(webhook)
          serialize_webhook(webhook).merge(
            masked_secret: webhook.masked_secret,
            custom_headers: webhook.custom_headers,
            created_by: webhook.created_by ? {
              id: webhook.created_by.id,
              name: webhook.created_by.name,
              email: webhook.created_by.email
            } : nil
          )
        end
      end
    end
  end
end

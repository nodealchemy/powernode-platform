# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class SubscriptionsController < ApplicationController
        before_action :set_subscription, only: [ :show, :update, :destroy, :pause, :resume, :configure ]

        # GET /api/v1/marketplace/subscriptions
        # Lists all subscriptions for the current account
        def index
          subscriptions = current_account.marketplace_subscriptions

          # Filter by type
          subscriptions = subscriptions.for_type(params[:type]) if params[:type].present?

          # Filter by status
          subscriptions = subscriptions.where(status: params[:status]) if params[:status].present?

          # Ordering
          subscriptions = subscriptions.recent

          # Pagination
          pagination = pagination_params
          total_count = subscriptions.count
          subscriptions = subscriptions.offset((pagination[:page] - 1) * pagination[:per_page]).limit(pagination[:per_page])

          render_success(
            subscriptions.map { |s| serialize_subscription(s) },
            meta: {
              current_page: pagination[:page],
              per_page: pagination[:per_page],
              total_count: total_count,
              total_pages: (total_count.to_f / pagination[:per_page]).ceil,
              counts_by_type: subscription_counts_by_type,
              counts_by_status: subscription_counts_by_status
            }
          )
        end

        # GET /api/v1/marketplace/subscriptions/:id
        def show
          render_success(serialize_subscription(@subscription, detailed: true))
        end

        # POST /api/v1/marketplace/subscriptions
        # Creates a new subscription
        def create
          orchestrator = ::Marketplace::SubscriptionOrchestrator.new(
            account: current_account,
            user: current_user
          )

          result = orchestrator.subscribe(
            item_type: params[:item_type],
            item_id: params[:item_id],
            options: subscription_options
          )

          if result[:success]
            render_success(serialize_subscription(result[:data]), status: :created)
          else
            render_error(result[:errors].join(", "), :unprocessable_content)
          end
        end

        # PATCH /api/v1/marketplace/subscriptions/:id
        # Updates subscription configuration
        def update
          if @subscription.merge_config(params[:configuration] || {})
            render_success(serialize_subscription(@subscription))
          else
            render_validation_error(@subscription)
          end
        end

        # DELETE /api/v1/marketplace/subscriptions/:id
        # Cancels a subscription
        def destroy
          orchestrator = ::Marketplace::SubscriptionOrchestrator.new(
            account: current_account,
            user: current_user
          )

          result = orchestrator.unsubscribe(
            subscription_id: @subscription.id,
            reason: params[:reason]
          )

          if result[:success]
            render_success({ message: "Subscription cancelled successfully" })
          else
            render_error(result[:errors].join(", "), :unprocessable_content)
          end
        end

        # POST /api/v1/marketplace/subscriptions/:id/pause
        def pause
          if @subscription.pause!(params[:reason])
            render_success(serialize_subscription(@subscription))
          else
            render_error("Failed to pause subscription", :unprocessable_content)
          end
        end

        # POST /api/v1/marketplace/subscriptions/:id/resume
        def resume
          if @subscription.resume!
            render_success(serialize_subscription(@subscription))
          else
            render_error("Failed to resume subscription", :unprocessable_content)
          end
        end

        # PATCH /api/v1/marketplace/subscriptions/:id/configure
        def configure
          config = params[:configuration] || {}

          if @subscription.merge_config(config)
            render_success(serialize_subscription(@subscription))
          else
            render_error("Failed to update configuration", :unprocessable_content)
          end
        end

        # POST /api/v1/marketplace/subscriptions/:id/upgrade_tier
        def upgrade_tier
          new_tier = params[:tier]

          if @subscription.upgrade_tier!(new_tier)
            render_success(serialize_subscription(@subscription))
          else
            render_error("Failed to upgrade tier", :unprocessable_content)
          end
        end

        # GET /api/v1/marketplace/subscriptions/:id/usage
        def usage
          render_success({
            subscription_id: @subscription.id,
            usage_metrics: @subscription.usage_metrics,
            usage_within_limits: @subscription.usage_within_limits?,
            subscription_age_days: @subscription.subscription_age_in_days
          })
        end

        private

        def set_subscription
          @subscription = current_account.marketplace_subscriptions.find_by(id: params[:id])
          render_error("Subscription not found", :not_found) unless @subscription
        end

        def subscription_options
          {
            tier: params[:tier] || "standard",
            plan_id: params[:plan_id],
            configuration: params[:configuration] || {},
            create_workflow: params[:create_workflow] == "true",
            workflow_name: params[:workflow_name],
            source: "subscription_api"
          }
        end

        def serialize_subscription(subscription, detailed: false)
          data = {
            id: subscription.id,
            item_id: subscription.subscribable_id,
            item_type: subscription.subscription_type,
            item_name: subscription.item_name,
            item_slug: subscription.item_slug,
            status: subscription.status,
            tier: subscription.tier,
            subscribed_at: subscription.subscribed_at.iso8601,
            configuration: subscription.configuration
          }

          if detailed
            data.merge!(
              usage_metrics: subscription.usage_metrics,
              metadata: subscription.metadata,
              next_billing_at: subscription.next_billing_at&.iso8601,
              days_until_billing: subscription.days_until_billing,
              subscription_age_days: subscription.subscription_age_in_days,
              item: serialize_item(subscription.subscribable, subscription.subscription_type)
            )
          end

          data
        end

        def serialize_item(item, type)
          return nil unless item

          case type
          when "app"
            {
              id: item.id,
              name: item.name,
              slug: item.slug,
              description: item.description,
              version: item.version,
              category: item.category
            }
          when "plugin", "integration"
            {
              id: item.id,
              name: item.name,
              slug: item.slug,
              description: item.description,
              version: item.version,
              capabilities: item.capabilities
            }
          when "template"
            {
              id: item.id,
              name: item.name,
              slug: item.slug,
              description: item.description,
              version: item.version,
              category: item.category,
              difficulty_level: item.difficulty_level
            }
          end
        end

        def subscription_counts_by_type
          {
            app: current_account.marketplace_subscriptions.for_apps.count,
            plugin: current_account.marketplace_subscriptions.for_plugins.count,
            template: current_account.marketplace_subscriptions.for_templates.count,
            integration: current_account.marketplace_subscriptions.for_integrations.count
          }
        end

        def subscription_counts_by_status
          {
            active: current_account.marketplace_subscriptions.active.count,
            paused: current_account.marketplace_subscriptions.paused.count,
            cancelled: current_account.marketplace_subscriptions.cancelled.count
          }
        end
      end
    end
  end
end

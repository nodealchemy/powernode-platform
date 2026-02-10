# frozen_string_literal: true

module Api
  module BaaS
    module V1
      class SubscriptionsController < Api::BaaS::BaseController
        before_action :require_subscriptions_scope

        # GET /api/baas/v1/subscriptions
        def index
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.list_subscriptions(
            status: params[:status],
            customer_id: params[:customer_id],
            page: params[:page],
            per_page: params[:per_page]
          )

          if result[:success]
            render_success(result[:subscriptions], meta: { pagination: result[:pagination] })
          else
            render_error(result[:error])
          end
        end

        # GET /api/baas/v1/subscriptions/:id
        def show
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.get_subscription(params[:id])

          if result[:success]
            render_success(result[:subscription])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/baas/v1/subscriptions
        def create
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.create_subscription(subscription_params)

          if result[:success]
            render_success(result[:subscription], status: :created)
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # PATCH /api/baas/v1/subscriptions/:id
        def update
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.update_subscription(params[:id], subscription_params)

          if result[:success]
            render_success(result[:subscription])
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # POST /api/baas/v1/subscriptions/:id/cancel
        def cancel
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.cancel_subscription(params[:id], cancel_params)

          if result[:success]
            render_success(result[:subscription], message: "Subscription canceled")
          else
            render_error(result[:error])
          end
        end

        # POST /api/baas/v1/subscriptions/:id/pause
        def pause
          subscription = current_tenant.subscriptions.find_by(external_id: params[:id])
          return render_error("Subscription not found", status: :not_found) unless subscription

          if subscription.pause!
            render_success(subscription.summary, message: "Subscription paused")
          else
            render_error("Cannot pause subscription")
          end
        end

        # POST /api/baas/v1/subscriptions/:id/resume
        def resume
          subscription = current_tenant.subscriptions.find_by(external_id: params[:id])
          return render_error("Subscription not found", status: :not_found) unless subscription

          if subscription.resume!
            render_success(subscription.summary, message: "Subscription resumed")
          else
            render_error("Cannot resume subscription")
          end
        end

        private

        def require_subscriptions_scope
          require_scope("subscriptions")
        end

        def subscription_params
          params.permit(
            :customer_id, :external_id, :plan_id, :billing_interval,
            :billing_interval_count, :unit_amount, :currency, :quantity,
            :trial_days, metadata: {}
          )
        end

        def cancel_params
          params.permit(:reason, :at_period_end)
        end
      end
    end
  end
end

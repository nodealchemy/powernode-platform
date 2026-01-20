# frozen_string_literal: true

module Api
  module V1
    module Ai
      class PublisherController < ApplicationController
        before_action :set_publisher, only: [:show, :dashboard, :analytics, :earnings, :templates, :payouts, :request_payout, :stripe_setup, :stripe_status]
        before_action -> { require_permission("ai.publisher.read") }, only: [:index, :show, :dashboard, :analytics, :earnings, :templates, :payouts]
        before_action -> { require_permission("ai.publisher.manage") }, only: [:create, :update, :request_payout, :stripe_setup]

        # GET /api/v1/ai/publisher
        def index
          publishers = ::Ai::PublisherAccount.includes(:account).order(created_at: :desc)

          if params[:status].present?
            publishers = publishers.where(status: params[:status])
          end

          paginated = publishers.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

          render_success(
            paginated.map { |p| publisher_data(p) },
            meta: pagination_meta(paginated)
          )
        end

        # GET /api/v1/ai/publisher/:id
        def show
          render_success(data: publisher_data(@publisher, include_details: true))
        end

        # POST /api/v1/ai/publisher
        def create
          existing = current_account.ai_publisher_account
          if existing
            return render_error("Account already has a publisher profile", status: :unprocessable_content)
          end

          publisher = ::Ai::PublisherAccount.new(publisher_params)
          publisher.account = current_account
          publisher.primary_user = current_user

          if publisher.save
            render_success(
              data: publisher_data(publisher),
              message: "Publisher profile created successfully",
              status: :created
            )
          else
            render_validation_error(publisher.errors)
          end
        end

        # GET /api/v1/ai/publisher/:id/dashboard
        def dashboard
          authorize_publisher_action!

          templates = @publisher.agent_templates
          active_templates = templates.published
          pending_templates = templates.where(status: "pending_review")

          stats = {
            publisher: publisher_data(@publisher),
            overview: {
              total_templates: templates.count,
              active_templates: active_templates.count,
              pending_templates: pending_templates.count,
              total_installations: templates.sum(:installation_count),
              active_installations: templates.sum(:active_installations),
              average_rating: templates.average(:average_rating)&.round(2),
              total_reviews: templates.sum(:review_count)
            },
            earnings: {
              lifetime_earnings: @publisher.lifetime_earnings_usd,
              pending_payout: @publisher.pending_payout_usd,
              revenue_share: @publisher.revenue_share_percentage
            },
            recent_sales: recent_sales(@publisher),
            top_templates: top_performing_templates(@publisher)
          }

          render_success(data: stats)
        end

        # GET /api/v1/ai/publisher/:id/analytics
        def analytics
          authorize_publisher_action!

          period = (params[:period] || 30).to_i.days
          start_date = period.ago.to_date
          end_date = Date.current

          templates = @publisher.agent_templates.published

          # Aggregate metrics across all templates
          metrics = ::Ai::TemplateUsageMetric
                    .where(agent_template: templates)
                    .for_period(start_date, end_date)

          analytics_data = {
            period: { start: start_date, end: end_date },
            summary: {
              total_revenue: metrics.sum(:gross_revenue),
              publisher_revenue: metrics.sum(:publisher_revenue),
              platform_commission: metrics.sum(:platform_commission),
              total_installations: metrics.sum(:new_installations),
              total_uninstallations: metrics.sum(:uninstallations),
              net_installations: metrics.sum(:new_installations) - metrics.sum(:uninstallations),
              total_executions: metrics.sum(:total_executions),
              page_views: metrics.sum(:page_views),
              unique_visitors: metrics.sum(:unique_visitors)
            },
            daily_metrics: aggregate_daily_metrics(metrics),
            template_breakdown: template_performance_breakdown(templates, start_date, end_date)
          }

          render_success(data: analytics_data)
        end

        # GET /api/v1/ai/publisher/:id/earnings
        def earnings
          authorize_publisher_action!

          # Get earnings snapshots
          snapshots = ::Ai::PublisherEarningsSnapshot
                      .where(publisher: @publisher)
                      .order(snapshot_date: :desc)
                      .limit(90)

          # Get recent transactions
          transactions = ::Ai::MarketplaceTransaction
                         .where(publisher: @publisher)
                         .completed
                         .order(created_at: :desc)
                         .limit(50)

          earnings_data = {
            current: {
              lifetime_earnings: @publisher.lifetime_earnings_usd,
              pending_payout: @publisher.pending_payout_usd,
              revenue_share_percentage: @publisher.revenue_share_percentage,
              payout_enabled: @publisher.stripe_payout_enabled
            },
            history: snapshots.map { |s| earnings_snapshot_data(s) },
            recent_transactions: transactions.map { |t| transaction_data(t) }
          }

          render_success(data: earnings_data)
        end

        # GET /api/v1/ai/publisher/:id/templates
        def templates
          authorize_publisher_action!

          templates = @publisher.agent_templates.includes(:categories)

          if params[:status].present?
            templates = templates.where(status: params[:status])
          end

          paginated = templates.order(created_at: :desc).page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

          render_success(
            paginated.map { |t| template_summary(t) },
            meta: pagination_meta(paginated)
          )
        end

        # GET /api/v1/ai/publisher/:id/payouts
        def payouts
          authorize_publisher_action!

          # For now, return transaction history as payouts
          # In a full implementation, there would be a separate payouts table
          payouts = ::Ai::MarketplaceTransaction
                    .where(publisher: @publisher, transaction_type: "payout")
                    .order(created_at: :desc)

          paginated = payouts.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

          render_success(
            paginated.map { |p| transaction_data(p) },
            meta: pagination_meta(paginated)
          )
        end

        # POST /api/v1/ai/publisher/:id/request_payout
        def request_payout
          authorize_publisher_action!

          amount = params[:amount].to_f
          if amount <= 0
            return render_error("Invalid payout amount", status: :bad_request)
          end

          service = ::Ai::MarketplacePaymentService.new(account: current_account, user: current_user)
          result = service.process_publisher_payout(publisher: @publisher, amount: amount)

          if result[:success]
            render_success(
              data: { transfer_id: result[:transfer_id], amount: result[:amount] },
              message: "Payout processed successfully"
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/publisher/:id/stripe_setup
        def stripe_setup
          authorize_publisher_action!

          return_url = params[:return_url]
          refresh_url = params[:refresh_url]

          unless return_url.present? && refresh_url.present?
            return render_error("return_url and refresh_url are required", status: :bad_request)
          end

          service = ::Ai::MarketplacePaymentService.new(account: current_account, user: current_user)
          result = service.setup_stripe_connect(
            publisher: @publisher,
            return_url: return_url,
            refresh_url: refresh_url
          )

          if result[:success]
            render_success(data: { onboarding_url: result[:onboarding_url] })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/publisher/:id/stripe_status
        def stripe_status
          authorize_publisher_action!

          service = ::Ai::MarketplacePaymentService.new(account: current_account, user: current_user)
          result = service.verify_stripe_account(publisher: @publisher)

          if result[:success]
            render_success(data: result.except(:success))
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/publisher/me
        def me
          publisher = current_account.ai_publisher_account

          if publisher
            render_success(data: publisher_data(publisher, include_details: true))
          else
            render_error("No publisher profile found", status: :not_found)
          end
        end

        private

        def set_publisher
          @publisher = if params[:id] == "me"
                         current_account.ai_publisher_account
                       else
                         ::Ai::PublisherAccount.find(params[:id])
                       end

          render_error("Publisher not found", status: :not_found) unless @publisher
        rescue ActiveRecord::RecordNotFound
          render_error("Publisher not found", status: :not_found)
        end

        def authorize_publisher_action!
          unless @publisher.account == current_account || current_user.has_permission?("ai.publisher.manage")
            render_error("Access denied", status: :forbidden)
          end
        end

        def publisher_params
          params.permit(:publisher_name, :publisher_slug, :description, :website_url, :support_email, :branding => {})
        end

        def publisher_data(publisher, include_details: false)
          data = {
            id: publisher.id,
            publisher_name: publisher.publisher_name,
            publisher_slug: publisher.publisher_slug,
            status: publisher.status,
            verification_status: publisher.verification_status,
            total_templates: publisher.total_templates,
            total_installations: publisher.total_installations,
            average_rating: publisher.average_rating,
            created_at: publisher.created_at
          }

          if include_details
            data.merge!(
              account_id: publisher.account_id,
              description: publisher.description,
              website_url: publisher.website_url,
              support_email: publisher.support_email,
              revenue_share_percentage: publisher.revenue_share_percentage,
              lifetime_earnings_usd: publisher.lifetime_earnings_usd,
              pending_payout_usd: publisher.pending_payout_usd,
              stripe_account_status: publisher.stripe_account_status,
              stripe_payout_enabled: publisher.stripe_payout_enabled,
              branding: publisher.branding
            )
          end

          data
        end

        def recent_sales(publisher)
          ::Ai::MarketplaceTransaction
            .where(publisher: publisher, transaction_type: "purchase")
            .completed
            .order(created_at: :desc)
            .limit(10)
            .map { |t| transaction_data(t) }
        end

        def top_performing_templates(publisher)
          publisher.agent_templates
                   .published
                   .order(installation_count: :desc)
                   .limit(5)
                   .map { |t| template_summary(t) }
        end

        def aggregate_daily_metrics(metrics)
          metrics.group(:metric_date)
                 .select(
                   "metric_date",
                   "SUM(gross_revenue) as revenue",
                   "SUM(new_installations) as installations",
                   "SUM(page_views) as page_views"
                 )
                 .order(metric_date: :asc)
                 .map do |m|
            {
              date: m.metric_date,
              revenue: m.revenue,
              installations: m.installations,
              page_views: m.page_views
            }
          end
        end

        def template_performance_breakdown(templates, start_date, end_date)
          templates.map do |template|
            metrics = template.usage_metrics.for_period(start_date, end_date)
            {
              id: template.id,
              name: template.name,
              revenue: metrics.sum(:gross_revenue),
              installations: metrics.sum(:new_installations),
              executions: metrics.sum(:total_executions),
              rating: template.average_rating
            }
          end.sort_by { |t| -t[:revenue] }
        end

        def template_summary(template)
          {
            id: template.id,
            name: template.name,
            slug: template.slug,
            status: template.status,
            pricing_type: template.pricing_type,
            price_usd: template.price_usd,
            installation_count: template.installation_count,
            active_installations: template.active_installations,
            average_rating: template.average_rating,
            review_count: template.review_count,
            is_featured: template.is_featured,
            is_verified: template.is_verified,
            created_at: template.created_at
          }
        end

        def transaction_data(transaction)
          {
            id: transaction.id,
            transaction_type: transaction.transaction_type,
            status: transaction.status,
            gross_amount: transaction.gross_amount_usd,
            publisher_amount: transaction.publisher_amount_usd,
            commission_amount: transaction.commission_amount_usd,
            template_name: transaction.agent_template&.name,
            created_at: transaction.created_at
          }
        end

        def earnings_snapshot_data(snapshot)
          {
            date: snapshot.snapshot_date,
            gross_earnings: snapshot.gross_earnings,
            net_earnings: snapshot.net_earnings,
            pending_payout: snapshot.pending_payout,
            paid_out: snapshot.paid_out,
            total_sales: snapshot.total_sales
          }
        end

        def pagination_meta(paginated)
          {
            pagination: {
              current_page: paginated.current_page,
              per_page: paginated.limit_value,
              total_pages: paginated.total_pages,
              total_count: paginated.total_count
            }
          }
        end
      end
    end
  end
end

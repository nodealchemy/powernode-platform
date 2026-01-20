# frozen_string_literal: true

module Api
  module V1
    class ResellersController < ApplicationController
      before_action :set_reseller, only: [:show, :update, :dashboard, :request_payout, :commissions, :referrals, :payouts]
      before_action -> { require_permission("resellers.read") }, only: [:index]
      before_action -> { require_permission("resellers.manage") }, only: [:approve, :activate, :suspend, :process_payout]

      # GET /api/v1/resellers
      def index
        service = ResellerService.new(account: current_account, user: current_user)
        resellers = service.list_resellers(filters: filter_params)

        paginated = resellers.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map { |r| reseller_data(r) },
          meta: pagination_meta(paginated)
        )
      end

      # GET /api/v1/resellers/:id
      def show
        render_success(data: reseller_data(@reseller, include_details: true))
      end

      # POST /api/v1/resellers
      def create
        service = ResellerService.new(account: current_account, user: current_user)
        result = service.apply(reseller_params)

        if result[:success]
          render_success(
            data: reseller_data(result[:reseller]),
            message: "Reseller application submitted successfully",
            status: :created
          )
        else
          render_error(
            result[:error] || result[:errors]&.join(", ") || "Failed to create reseller",
            status: :unprocessable_content
          )
        end
      end

      # PATCH /api/v1/resellers/:id
      def update
        authorize_reseller_action!

        if @reseller.update(update_params)
          render_success(
            data: reseller_data(@reseller),
            message: "Reseller updated successfully"
          )
        else
          render_validation_error(@reseller.errors)
        end
      end

      # GET /api/v1/resellers/:id/dashboard
      def dashboard
        authorize_reseller_action!

        service = ResellerService.new(account: current_account, user: current_user)
        result = service.dashboard_stats(reseller: @reseller)

        if result[:success]
          render_success(data: result[:stats])
        else
          render_error(result[:error], status: :forbidden)
        end
      end

      # POST /api/v1/resellers/:id/request_payout
      def request_payout
        authorize_reseller_action!

        amount = params[:amount].to_f
        if amount <= 0
          return render_error("Invalid payout amount", status: :unprocessable_content)
        end

        service = ResellerService.new(account: current_account, user: current_user)
        result = service.request_payout(reseller: @reseller, amount: amount)

        if result[:success]
          render_success(
            data: result[:payout].summary,
            message: "Payout requested successfully"
          )
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      end

      # GET /api/v1/resellers/:id/commissions
      def commissions
        authorize_reseller_action!

        commissions = @reseller.commissions.order(earned_at: :desc)

        if params[:status].present?
          commissions = commissions.where(status: params[:status])
        end

        if params[:start_date].present? && params[:end_date].present?
          commissions = commissions.for_period(params[:start_date].to_date, params[:end_date].to_date)
        end

        paginated = commissions.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map { |c| commission_data(c) },
          meta: pagination_meta(paginated)
        )
      end

      # GET /api/v1/resellers/:id/referrals
      def referrals
        authorize_reseller_action!

        referrals = @reseller.referrals.includes(:referred_account).order(referred_at: :desc)

        if params[:status].present?
          referrals = referrals.where(status: params[:status])
        end

        paginated = referrals.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      end

      # GET /api/v1/resellers/:id/payouts
      def payouts
        authorize_reseller_action!

        payouts = @reseller.payouts.order(requested_at: :desc)

        if params[:status].present?
          payouts = payouts.where(status: params[:status])
        end

        paginated = payouts.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      end

      # Admin: POST /api/v1/resellers/:id/approve
      def approve
        reseller = Reseller.find(params[:id])
        service = ResellerService.new(account: current_account, user: current_user)
        result = service.approve_application(reseller: reseller)

        if result[:success]
          render_success(
            data: reseller_data(result[:reseller]),
            message: "Reseller approved successfully"
          )
        else
          render_error(result[:error] || result[:errors]&.join(", "), status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Reseller not found", status: :not_found)
      end

      # Admin: POST /api/v1/resellers/:id/activate
      def activate
        reseller = Reseller.find(params[:id])
        service = ResellerService.new(account: current_account, user: current_user)
        result = service.activate_reseller(reseller: reseller)

        if result[:success]
          render_success(
            data: reseller_data(result[:reseller]),
            message: "Reseller activated successfully"
          )
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Reseller not found", status: :not_found)
      end

      # Admin: POST /api/v1/resellers/:id/suspend
      def suspend
        reseller = Reseller.find(params[:id])

        if reseller.suspend!(reason: params[:reason])
          render_success(
            data: reseller_data(reseller),
            message: "Reseller suspended"
          )
        else
          render_error("Failed to suspend reseller", status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Reseller not found", status: :not_found)
      end

      # Admin: POST /api/v1/resellers/payouts/:payout_id/process
      def process_payout
        payout = ResellerPayout.find(params[:payout_id])
        service = ResellerService.new(account: current_account, user: current_user)
        result = service.process_payout(payout: payout)

        if result[:success]
          render_success(
            data: result[:payout].summary,
            message: "Payout processed successfully"
          )
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Payout not found", status: :not_found)
      end

      # GET /api/v1/resellers/me
      def me
        reseller = current_account.reseller
        if reseller
          render_success(data: reseller_data(reseller, include_details: true))
        else
          render_error("No reseller profile found", status: :not_found)
        end
      end

      # POST /api/v1/resellers/track_referral
      def track_referral
        referral_code = params[:referral_code]
        referred_account_id = params[:referred_account_id]

        unless referral_code.present?
          return render_error("Referral code is required", status: :bad_request)
        end

        referred_account = Account.find(referred_account_id)
        service = ResellerService.new(account: current_account, user: current_user)
        result = service.track_referral(referred_account: referred_account, referral_code: referral_code)

        if result[:success]
          render_success(message: "Referral tracked successfully")
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Account not found", status: :not_found)
      end

      # GET /api/v1/resellers/tiers
      def tiers
        tiers = Reseller::TIER_BENEFITS.map do |tier, benefits|
          {
            tier: tier,
            commission_percentage: benefits[:commission],
            min_referrals: benefits[:min_referrals],
            revenue_threshold: benefits[:revenue_threshold]
          }
        end

        render_success(data: tiers)
      end

      private

      def set_reseller
        @reseller = if params[:id] == "me"
                      current_account.reseller
                    else
                      Reseller.find(params[:id])
                    end

        render_error("Reseller not found", status: :not_found) unless @reseller
      rescue ActiveRecord::RecordNotFound
        render_error("Reseller not found", status: :not_found)
      end

      def authorize_reseller_action!
        unless @reseller.account == current_account || current_user.has_permission?("resellers.manage")
          render_error("Access denied", status: :forbidden)
        end
      end

      def reseller_params
        params.permit(
          :company_name, :contact_email, :contact_phone, :website_url,
          :tax_id, :payout_method, payout_details: {}
        )
      end

      def update_params
        params.permit(
          :contact_email, :contact_phone, :website_url,
          :payout_method, payout_details: {}, branding: {}
        )
      end

      def filter_params
        params.permit(:status, :tier)
      end

      def reseller_data(reseller, include_details: false)
        data = {
          id: reseller.id,
          company_name: reseller.company_name,
          referral_code: reseller.referral_code,
          tier: reseller.tier,
          status: reseller.status,
          commission_percentage: reseller.commission_percentage,
          lifetime_earnings: reseller.lifetime_earnings,
          pending_payout: reseller.pending_payout,
          total_referrals: reseller.total_referrals,
          active_referrals: reseller.active_referrals,
          created_at: reseller.created_at,
          activated_at: reseller.activated_at
        }

        if include_details
          data.merge!(
            contact_email: reseller.contact_email,
            contact_phone: reseller.contact_phone,
            website_url: reseller.website_url,
            payout_method: reseller.payout_method,
            total_paid_out: reseller.total_paid_out,
            total_revenue_generated: reseller.total_revenue_generated,
            tier_benefits: reseller.tier_benefits,
            eligible_for_upgrade: reseller.eligible_for_tier_upgrade?,
            next_tier: reseller.next_tier_name,
            can_request_payout: reseller.can_receive_payouts?,
            branding: reseller.branding
          )
        end

        data
      end

      def commission_data(commission)
        {
          id: commission.id,
          commission_type: commission.commission_type,
          source_type: commission.source_type,
          gross_amount: commission.gross_amount,
          commission_percentage: commission.commission_percentage,
          commission_amount: commission.commission_amount,
          status: commission.status,
          earned_at: commission.earned_at,
          available_at: commission.available_at,
          paid_at: commission.paid_at,
          days_until_available: commission.days_until_available
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

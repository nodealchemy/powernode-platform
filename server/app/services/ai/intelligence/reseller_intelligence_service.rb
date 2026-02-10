# frozen_string_literal: true

module Ai
  module Intelligence
    class ResellerIntelligenceService
      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Score resellers based on referral volume, commission earnings, payout history
      def performance_scores
        resellers = Reseller.where(account_id: @account.id).active
        scores = resellers.map { |r| score_reseller(r) }.sort_by { |s| -s[:score] }

        success_response(
          scores: scores,
          total_resellers: resellers.count,
          top_performers: scores.first(5),
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("performance_scores", e)
      end

      # Analyze commission rates vs performance, recommend adjustments
      def commission_optimization
        resellers = Reseller.where(account_id: @account.id).active.includes(:commissions)
        recommendations = resellers.filter_map { |r| analyze_commission(r) }

        success_response(
          recommendations: recommendations.sort_by { |r| -r[:potential_impact] },
          total_analyzed: resellers.count,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("commission_optimization", e)
      end

      # Check referred accounts for churn signals
      def referral_churn_risks
        referrals = ResellerReferral.joins(:reseller)
                                    .where(resellers: { account_id: @account.id })
                                    .active
                                    .includes(:referred_account, :reseller)

        risks = referrals.filter_map { |ref| assess_referral_churn(ref) }
                         .sort_by { |r| -r[:risk_score] }

        success_response(
          risks: risks,
          total_referrals: referrals.count,
          high_risk_count: risks.count { |r| r[:risk_level] == "high" },
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("referral_churn_risks", e)
      end

      private

      def score_reseller(reseller)
        referral_count = reseller.referrals.active.count
        total_commissions = reseller.commissions.sum(:commission_amount).to_f
        paid_payouts = reseller.payouts.where(status: "completed").sum(:amount).to_f
        active_referrals = reseller.referrals.active.count

        # Score 0-100 based on weighted factors
        referral_score = [referral_count * 5, 40].min
        commission_score = [total_commissions / 100.0, 35].min
        payout_score = paid_payouts > 0 ? [paid_payouts / 200.0, 25].min : 0

        total_score = (referral_score + commission_score + payout_score).round(1)

        {
          reseller_id: reseller.id,
          company_name: reseller.company_name,
          tier: reseller.tier,
          score: total_score,
          referral_count: referral_count,
          active_referrals: active_referrals,
          total_commissions: total_commissions.round(2),
          total_payouts: paid_payouts.round(2),
          performance_tier: performance_tier(total_score)
        }
      end

      def performance_tier(score)
        if score >= 80 then "excellent"
        elsif score >= 60 then "strong"
        elsif score >= 40 then "average"
        elsif score >= 20 then "developing"
        else "underperforming"
        end
      end

      def analyze_commission(reseller)
        commissions = reseller.commissions.where("earned_at >= ?", 90.days.ago)
        return nil if commissions.empty?

        total_earned = commissions.sum(:commission_amount).to_f
        avg_rate = commissions.average(:commission_percentage)&.to_f || 0
        referral_count = reseller.referrals.active.count

        # Determine if rate adjustment is warranted
        recommendation = if referral_count >= 15 && avg_rate < 20
                           "increase"
                         elsif referral_count < 3 && avg_rate > 15
                           "decrease"
                         else
                           "maintain"
                         end

        suggested_rate = case recommendation
                         when "increase" then [avg_rate + 5, 25].min
                         when "decrease" then [avg_rate - 3, 10].max
                         else avg_rate
                         end

        potential_impact = ((suggested_rate - avg_rate) / 100.0 * total_earned).abs.round(2)

        {
          reseller_id: reseller.id,
          company_name: reseller.company_name,
          current_rate: avg_rate.round(2),
          suggested_rate: suggested_rate.round(2),
          recommendation: recommendation,
          referral_count: referral_count,
          quarterly_earnings: total_earned.round(2),
          potential_impact: potential_impact
        }
      end

      def assess_referral_churn(referral)
        account = referral.referred_account
        return nil unless account

        subscription = account.subscription
        days_since_referral = (Time.current - referral.referred_at).to_f / 1.day

        risk_score = 0.0
        risk_factors = []

        # Check subscription status
        if subscription.nil?
          risk_score += 0.4
          risk_factors << "no_active_subscription"
        elsif subscription.respond_to?(:status)
          case subscription.status
          when "past_due"
            risk_score += 0.3
            risk_factors << "past_due_subscription"
          when "canceled", "cancelled"
            risk_score += 0.5
            risk_factors << "canceled_subscription"
          end
        end

        # Check inactivity
        last_login = account.users.maximum(:last_sign_in_at)
        if last_login.nil? || last_login < 30.days.ago
          risk_score += 0.3
          risk_factors << "inactive_account"
        end

        # Early churn is more impactful
        if days_since_referral < 90
          risk_score += 0.1
          risk_factors << "early_lifecycle"
        end

        risk_score = risk_score.clamp(0, 1)
        return nil if risk_score < 0.2

        {
          referral_id: referral.id,
          reseller_id: referral.reseller_id,
          reseller_name: referral.reseller.company_name,
          referred_account_id: account.id,
          risk_score: risk_score.round(3),
          risk_level: risk_score > 0.6 ? "high" : risk_score > 0.3 ? "medium" : "low",
          risk_factors: risk_factors,
          days_since_referral: days_since_referral.round(0)
        }
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::ResellerIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end
    end
  end
end

# frozen_string_literal: true

module PowernodeEnterprise
  module Features
    # Enterprise feature flags registered with Flipper
    ENTERPRISE_FLAGS = %i[
      enterprise_baas
      enterprise_credits
      enterprise_marketplace_monetization
      enterprise_mcp_hosting
      enterprise_governance
      enterprise_compliance
      enterprise_outcome_billing
      enterprise_revenue_intelligence
      enterprise_intelligence
      enterprise_reseller
      enterprise_advanced_admin
    ].freeze

    # Maps feature names to minimum plan tier
    FEATURE_TIERS = {
      "baas" => "enterprise",
      "credits" => "business",
      "marketplace_monetization" => "business",
      "mcp_hosting" => "business",
      "governance" => "enterprise",
      "compliance" => "enterprise",
      "outcome_billing" => "enterprise",
      "revenue_intelligence" => "business",
      "intelligence" => "business",
      "reseller" => "enterprise",
      "advanced_admin" => "enterprise"
    }.freeze

    TIER_ORDER = %w[community business enterprise].freeze

    class << self
      def available?(feature, account: nil)
        return false unless defined?(PowernodeEnterprise::Engine)
        return false unless PowernodeEnterprise::License.valid? || PowernodeEnterprise::License.grace_period?

        # Check plan tier
        required_tier = FEATURE_TIERS[feature.to_s]
        return false unless required_tier

        license_tier = PowernodeEnterprise::License.edition
        return false unless tier_sufficient?(license_tier, required_tier)

        # Check feature flag if Flipper is available
        flag_name = :"enterprise_#{feature}"
        if defined?(Flipper) && ENTERPRISE_FLAGS.include?(flag_name)
          return Flipper.enabled?(flag_name, account)
        end

        true
      end

      private

      def tier_sufficient?(current_tier, required_tier)
        current_index = TIER_ORDER.index(current_tier) || 0
        required_index = TIER_ORDER.index(required_tier) || 0
        current_index >= required_index
      end
    end
  end
end

# frozen_string_literal: true

module EnterpriseFeatureGate
  extend ActiveSupport::Concern

  class_methods do
    # Require an enterprise feature for all actions in this controller
    #
    # @param feature [String] Enterprise feature name (e.g., "baas", "credits")
    # @param options [Hash] Standard before_action options (:only, :except, etc.)
    def require_enterprise_feature(feature, **options)
      before_action(**options) do
        unless Shared::FeatureGateService.available?(feature, account: current_account)
          render_error("This feature requires an enterprise license", :forbidden)
        end
      end
    end
  end
end

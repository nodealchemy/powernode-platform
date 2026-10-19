# frozen_string_literal: true

# Register core's intervention-policy domains (Ai::InterventionPolicies::CorePolicyDomains)
# with Ai::ClaudeExport::PolicyDomains. `to_prepare`, not `after_initialize`:
# PolicyDomains is autoloaded and its registry is a module ivar, so a dev-mode
# reload empties it and this re-registers after every reload (the system
# extension registers its own table the same way).
Rails.application.config.to_prepare do
  Ai::InterventionPolicies::CorePolicyDomains.register!
rescue StandardError => e
  Rails.logger.warn "[CorePolicyDomains] Could not register core policy domains: #{e.message}"
end

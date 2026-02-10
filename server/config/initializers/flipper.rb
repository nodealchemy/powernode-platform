# frozen_string_literal: true

require "flipper"
require "flipper/adapters/active_record"

Flipper.configure do |config|
  config.default do
    adapter = Flipper::Adapters::ActiveRecord.new
    Flipper.new(adapter)
  end
end

# Register feature flags on boot (idempotent — safe to re-run)
Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?(:flipper_features)

  flags = %w[
    self_healing_remediation
    trajectory_analysis
    prompt_caching
    agent_introspection
    agent_evaluation
    cross_system_triggers
    enterprise_mode
  ]

  flags.each do |flag|
    Flipper.add(flag) unless Flipper.exist?(flag)
  end

  # Auto-enable enterprise flags when enterprise engine is loaded
  if defined?(PowernodeEnterprise::Engine)
    # Master toggle
    Flipper.enable(:enterprise_mode) unless Flipper.enabled?(:enterprise_mode)

    # Register and enable individual enterprise feature flags
    if defined?(PowernodeEnterprise::Features::ENTERPRISE_FLAGS)
      PowernodeEnterprise::Features::ENTERPRISE_FLAGS.each do |flag|
        Flipper.add(flag) unless Flipper.exist?(flag)
        Flipper.enable(flag) unless Flipper.enabled?(flag)
      end
    end
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[Flipper] Skipping flag registration: #{e.message}"
end

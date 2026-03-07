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
    skill_lifecycle_research
    skill_lifecycle_auto_create
    skill_conflict_auto_resolve
    skill_self_learning
    skill_optimization
    compound_learning_injection
    compound_learning_promotion
  ]

  flags.each do |flag|
    Flipper.add(flag) unless Flipper.exist?(flag)
  end

  # Auto-enable skill self-learning (safe — SelfLearningService has per-method rescue guards)
  Flipper.enable(:skill_self_learning) unless Flipper.enabled?(:skill_self_learning)

  # Auto-enable compound learning injection/promotion for AI learning feedback loop
  Flipper.enable(:compound_learning_injection) unless Flipper.enabled?(:compound_learning_injection)
  Flipper.enable(:compound_learning_promotion) unless Flipper.enabled?(:compound_learning_promotion)

  # Auto-enable enterprise flags when enterprise engine is loaded
  if Powernode::ExtensionRegistry.loaded?("enterprise")
    # Master toggle
    Flipper.enable(:enterprise_mode) unless Flipper.enabled?(:enterprise_mode)

    # Register and enable individual enterprise feature flags
    if Powernode::ExtensionRegistry.loaded?("enterprise") && defined?(PowernodeEnterprise::Features::ENTERPRISE_FLAGS)
      PowernodeEnterprise::Features::ENTERPRISE_FLAGS.each do |flag|
        Flipper.add(flag) unless Flipper.exist?(flag)
        Flipper.enable(flag) unless Flipper.enabled?(flag)
      end
    end
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[Flipper] Skipping flag registration: #{e.message}"
end

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

  # Core platform flags — always present. Extension flags (the per-extension
  # <slug>_mode flags) are registered separately below from extensions/*/extension.json
  # so they appear if and only if the extension exists on disk.
  flags = %w[
    self_healing_remediation
    trajectory_analysis
    prompt_caching
    agent_introspection
    agent_evaluation
    cross_system_triggers
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

  # Sync extension feature flags to extensions on disk.
  #
  # An extension's <slug>_mode flag must exist iff extensions/<slug>/extension.json
  # is present. When a manifest is added the flag appears; when the directory is
  # removed (submodule deinit, rm -rf) the flag is pruned so the admin UI never
  # offers a toggle for an absent extension.
  extensions_dir = Rails.root.join("..", "extensions")
  extension_flag_names = Set.new
  # Extensions live flat under extensions/<slug>; private ones under
  # extensions/private/<slug>. "private" is a grouping dir, never a slug.
  ext_dirs = []
  if File.directory?(extensions_dir)
    extensions_dir.children.select(&:directory?).each do |d|
      ext_dirs << d unless d.basename.to_s == "private"
    end
    private_dir = extensions_dir.join("private")
    ext_dirs.concat(private_dir.children.select(&:directory?)) if private_dir.directory?
  end
  unless ext_dirs.empty?
    ext_dirs.each do |ext_dir|
      manifest = ext_dir.join("extension.json")
      next unless manifest.exist?

      begin
        meta = JSON.parse(manifest.read)
      rescue JSON::ParserError => e
        Rails.logger.warn("[Flipper] Invalid manifest #{manifest}: #{e.message}")
        next
      end

      flag_name = meta["feature_flag"]
      next if flag_name.blank?

      extension_flag_names << flag_name.to_s
      Flipper.add(flag_name) unless Flipper.exist?(flag_name)
    end
  end

  # Prune orphan extension flags: any *_mode feature whose extension manifest
  # is no longer on disk. We only touch flags that look like extension flags
  # (suffix "_mode") to avoid removing core platform flags. Each manifest-declared
  # <slug>_mode flag is whitelisted via extension_flag_names when the
  # extension is present.
  Flipper.features.each do |feature|
    name = feature.name.to_s
    next unless name.end_with?("_mode")
    next if extension_flag_names.include?(name)
    next if flags.include?(name) # don't prune anything in the static core list

    Rails.logger.info("[Flipper] Pruning orphan extension flag #{name} (no manifest on disk)")
    Flipper.remove(name)
  end

  # Auto-enable skill self-learning (safe — SelfLearningService has per-method rescue guards)
  Flipper.enable(:skill_self_learning) unless Flipper.enabled?(:skill_self_learning)

  # Auto-enable compound learning injection/promotion for AI learning feedback loop
  Flipper.enable(:compound_learning_injection) unless Flipper.enabled?(:compound_learning_injection)
  Flipper.enable(:compound_learning_promotion) unless Flipper.enabled?(:compound_learning_promotion)

  # Extension feature flags (e.g. <slug>_mode + per-feature flags) are registered
  # and enabled by each extension's OWN engine initializer — core only adds the
  # manifest-declared <slug>_mode flags generically (above) and prunes orphans, so
  # no extension is named here.
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[Flipper] Skipping flag registration: #{e.message}"
end

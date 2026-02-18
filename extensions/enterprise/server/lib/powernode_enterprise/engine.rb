# frozen_string_literal: true

module PowernodeEnterprise
  class Engine < ::Rails::Engine
    isolate_namespace PowernodeEnterprise

    # Add enterprise app directories to autoload paths
    initializer "powernode_enterprise.autoload", before: :set_autoload_paths do |app|
      engine_root = root

      %w[models services controllers controllers/concerns].each do |subdir|
        path = engine_root.join("app", subdir)
        app.config.autoload_paths << path.to_s if path.exist?
      end
    end

    # Load decorators that extend core models
    config.to_prepare do
      Dir[PowernodeEnterprise::Engine.root.join("app", "decorators", "**", "*_decorator.rb")].each do |decorator|
        load decorator
      end
    end

    # Enterprise routes are loaded automatically by Rails::Engine via
    # the add_routing_paths initializer (config/routes.rb is auto-discovered).
    # The routes file uses Rails.application.routes.draw to register routes.

    # Add enterprise migrations to the application migration paths
    initializer "powernode_enterprise.migrations" do |app|
      migrations_path = root.join("db", "migrate")
      if migrations_path.exist?
        app.config.paths["db/migrate"] << migrations_path.to_s
      end
    end

    # Validate enterprise license on boot
    initializer "powernode_enterprise.license_check", after: :load_config_initializers do
      config.after_initialize do
        unless PowernodeEnterprise::License.valid?
          if PowernodeEnterprise::License.grace_period?
            Rails.logger.warn "[PowernodeEnterprise] License expired — running in grace period (#{PowernodeEnterprise::License.grace_days_remaining} days remaining)"
          else
            Rails.logger.error "[PowernodeEnterprise] No valid license found. Enterprise features are disabled."
          end
        end
      end
    end

    # Register enterprise feature flags with Flipper
    initializer "powernode_enterprise.feature_flags", after: :load_config_initializers do
      config.after_initialize do
        if defined?(Flipper) && PowernodeEnterprise::License.valid?
          PowernodeEnterprise::Features::ENTERPRISE_FLAGS.each do |flag|
            Flipper.add(flag) unless Flipper.features.map(&:name).include?(flag.to_s)
          end
        end
      rescue StandardError => e
        Rails.logger.warn "[PowernodeEnterprise] Could not register feature flags: #{e.message}"
      end
    end
  end
end

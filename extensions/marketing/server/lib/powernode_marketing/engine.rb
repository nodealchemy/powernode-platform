# frozen_string_literal: true

module PowernodeMarketing
  class Engine < ::Rails::Engine
    isolate_namespace PowernodeMarketing

    # Add extension directories to autoload paths
    initializer "powernode_marketing.autoload", before: :set_autoload_paths do |app|
      %w[models services controllers channels].each do |subdir|
        path = root.join("app", subdir)
        app.config.autoload_paths << path.to_s if path.exist?
      end
    end

    # Load decorators that extend core models
    config.to_prepare do
      Dir[PowernodeMarketing::Engine.root.join("app", "decorators", "**", "*_decorator.rb")].each do |decorator|
        load decorator
      end
    end

    # Add extension migrations to the application migration paths
    initializer "powernode_marketing.migrations" do |app|
      path = root.join("db", "migrate")
      app.config.paths["db/migrate"] << path.to_s if path.exist?
    end

    # Register with the dynamic extension registry
    initializer "powernode_marketing.register", after: :load_config_initializers do
      config.after_initialize do
        Powernode::ExtensionRegistry.register(
          slug: "marketing",
          engine: PowernodeMarketing::Engine,
          version: PowernodeMarketing::VERSION
        )
      end
    end
  end
end

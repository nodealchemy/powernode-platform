# frozen_string_literal: true

module AdminSettings
  module ExtensionActions
    extend ActiveSupport::Concern

    # GET /api/v1/admin_settings/extensions
    def extensions
      extension_dirs = Shared::ExtensionPaths.extension_dirs
      extensions = []

      unless extension_dirs.empty?
        extension_dirs.each do |ext_dir|
          meta_file = ext_dir.join("extension.json")
          next unless meta_file.exist?

          begin
            meta = JSON.parse(meta_file.read)
            slug = meta["slug"] || ext_dir.basename.to_s
            extensions << {
              slug: slug,
              name: meta["name"] || slug.titleize,
              description: meta["description"],
              icon: meta["icon"],
              version: meta["version"],
              author: meta["author"],
              homepage: meta["homepage"],
              capabilities: meta["capabilities"] || [],
              installed: extension_installed?(slug),
              enabled: extension_enabled?(slug, meta)
            }
          rescue JSON::ParserError => e
            Rails.logger.warn "Invalid extension.json in #{ext_dir.basename}: #{e.message}"
          end
        end
      end

      render_success(extensions: extensions)
    end

    # PUT /api/v1/admin_settings/extensions/:slug/toggle
    def toggle_extension
      slug = params[:slug]
      meta_file = Shared::ExtensionPaths.manifest_for(slug)

      unless meta_file&.exist?
        return render_error("Extension '#{slug}' not found", :not_found)
      end

      meta = JSON.parse(meta_file.read)
      feature_flag = meta["feature_flag"]

      unless feature_flag.present?
        return render_error("Extension '#{slug}' does not support toggling", :unprocessable_content)
      end

      # Note: we deliberately do not gate on `extension_installed?` here. Once an
      # extension is disabled via the state file, its engine is not loaded into
      # this process — but we must still allow the user to re-enable it via the
      # same endpoint. Manifest presence (checked above via `meta_file.exist?`)
      # is the canonical "this extension exists and can be toggled" check.
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])

      if defined?(Flipper)
        if enabled
          Flipper.enable(feature_flag.to_sym)
        else
          Flipper.disable(feature_flag.to_sym)
        end
      end

      # Persist the disable decision so backend, worker, and Vite build-time loaders
      # can skip the extension on next boot. Flipper handles runtime gating; this
      # store handles load-time gating (the Engine, worker requires, Vite glob).
      Shared::ExtensionStateStore.set_disabled!(slug, disabled: !enabled)

      new_state = extension_enabled?(slug, meta)

      log_audit_event("extension_toggle", "SystemSettings",
                      metadata: { extension: slug, enabled: new_state })

      render_success(
        slug: slug,
        enabled: new_state,
        requires_restart: true,
        requires_frontend_rebuild: true,
        message: "#{meta['name'] || slug.titleize} #{new_state ? 'enabled' : 'disabled'}. Restart backend/worker and rebuild frontend to take full effect."
      )
    rescue JSON::ParserError
      render_error("Invalid extension metadata for '#{slug}'", :unprocessable_content)
    end

    # GET /api/v1/admin_settings/development
    def development
      render_success(Shared::FeatureGateService.development_info)
    end

    # PUT /api/v1/admin_settings/development
    def update_development
      slug = params[:slug].to_s
      unless Shared::FeatureGateService.extension_loaded?(slug)
        return render_error("Extension '#{slug}' is not loaded", :unprocessable_content)
      end

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      new_state = Shared::FeatureGateService.set_extension_enabled!(slug, enabled)

      log_audit_event("admin.extension.toggle", "SystemSettings",
                      metadata: { slug: slug, enabled: new_state })

      render_success(
        slug: slug,
        enabled: new_state,
        message: "Extension '#{slug}' #{new_state ? 'enabled' : 'disabled'}"
      )
    end

    private

    # Check if an extension's engine is loaded in the Rails runtime
    def extension_installed?(slug)
      Shared::FeatureGateService.extension_loaded?(slug)
    end

    # Check if an extension is enabled via its feature flag
    def extension_enabled?(slug, _meta = nil)
      Shared::FeatureGateService.extension_enabled?(slug)
    end
  end
end

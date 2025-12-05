# frozen_string_literal: true

module Api
  module V1
    class PluginsController < ApplicationController
      before_action :set_plugin, only: [:show, :update, :destroy, :install, :uninstall]

      # GET /api/v1/plugins
      def index
        plugins = current_account.plugins
                                .includes(:source_marketplace, :plugin_installations)
                                .order(created_at: :desc)

        # Apply filters
        plugins = apply_filters(plugins)

        render_success(
          plugins: plugins.as_json(
            include: {
              source_marketplace: { only: [:id, :name] },
              plugin_installations: {
                only: [:id, :status, :installed_at],
                methods: [:execution_count]
              }
            },
            methods: [:install_count, :average_rating]
          )
        )
      end

      # GET /api/v1/plugins/:id
      def show
        installation = @plugin.installation_for(current_account)

        render_success(
          plugin: @plugin.as_json(
            include: {
              source_marketplace: { only: [:id, :name] },
              ai_provider_plugin: {},
              workflow_node_plugins: {},
              plugin_reviews: {
                include: { user: { only: [:id, :email, :full_name] } }
              }
            }
          ),
          installation: installation&.as_json(methods: [:execution_count, :total_cost]),
          is_installed: installation&.status == 'active'
        )
      end

      # POST /api/v1/plugins
      def create
        plugin = current_account.plugins.build(plugin_params)
        plugin.creator = current_user

        if plugin.save
          render_success(
            plugin: plugin.as_json,
            message: 'Plugin created successfully'
          )
        else
          render_validation_error(plugin.errors)
        end
      end

      # PATCH /api/v1/plugins/:id
      def update
        if @plugin.update(plugin_params)
          render_success(
            plugin: @plugin.as_json,
            message: 'Plugin updated successfully'
          )
        else
          render_validation_error(@plugin.errors)
        end
      end

      # DELETE /api/v1/plugins/:id
      def destroy
        @plugin.destroy!
        render_success(message: 'Plugin deleted successfully')
      rescue StandardError => e
        render_error("Failed to delete plugin: #{e.message}", status: :unprocessable_content)
      end

      # POST /api/v1/plugins/:id/install
      def install
        service = PluginInstallationService.new
        installation = service.install_plugin(
          @plugin,
          current_account,
          current_user,
          install_params[:configuration] || {}
        )

        render_success(
          installation: installation.as_json(include: :plugin),
          message: "Plugin '#{@plugin.name}' installed successfully"
        )
      rescue StandardError => e
        render_error("Installation failed: #{e.message}", status: :unprocessable_content)
      end

      # DELETE /api/v1/plugins/:id/uninstall
      def uninstall
        installation = @plugin.installation_for(current_account)

        if installation.nil?
          return render_error('Plugin is not installed', status: :unprocessable_content)
        end

        service = PluginInstallationService.new
        service.uninstall_plugin(installation)

        render_success(message: "Plugin '#{@plugin.name}' uninstalled successfully")
      rescue StandardError => e
        render_error("Uninstallation failed: #{e.message}", status: :unprocessable_content)
      end

      # GET /api/v1/plugins/search
      def search
        query = params[:q] || params[:query]
        plugins = current_account.plugins.search_by_text(query)

        render_success(plugins: plugins.as_json)
      end

      # GET /api/v1/plugins/by_capability
      def by_capability
        capability = params[:capability]
        plugins = current_account.plugins.with_capability(capability)

        render_success(plugins: plugins.as_json)
      end

      private

      def set_plugin
        @plugin = current_account.plugins.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Plugin not found')
      end

      def plugin_params
        params.require(:plugin).permit(
          :plugin_id, :name, :description, :version, :author,
          :homepage, :license, :source_type, :source_url, :source_ref,
          :status, :is_verified, :is_official,
          plugin_types: [], capabilities: [],
          manifest: {}, configuration: {}, metadata: {}
        )
      end

      def install_params
        params.permit(configuration: {})
      end

      def apply_filters(plugins)
        plugins = plugins.by_type(params[:type]) if params[:type].present?
        plugins = plugins.where(status: params[:status]) if params[:status].present?
        plugins = plugins.verified if params[:verified] == 'true'
        plugins = plugins.official if params[:official] == 'true'
        plugins
      end
    end
  end
end

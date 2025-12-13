# frozen_string_literal: true

module Api
  module V1
    class PluginMarketplacesController < ApplicationController
      before_action :set_marketplace, only: [ :show, :update, :destroy, :sync ]

      # GET /api/v1/plugin_marketplaces
      def index
        marketplaces = current_account.plugin_marketplaces
                                      .includes(:creator)
                                      .order(created_at: :desc)

        render_success(
          marketplaces: marketplaces.as_json(
            include: { creator: { only: [ :id, :email, :full_name ] } },
            methods: [ :plugin_count ]
          )
        )
      end

      # GET /api/v1/plugin_marketplaces/:id
      def show
        render_success(
          marketplace: @marketplace.as_json(
            include: {
              creator: { only: [ :id, :email, :full_name ] },
              plugins: {
                only: [ :id, :plugin_id, :name, :version, :description, :status ],
                methods: [ :install_count ]
              }
            }
          )
        )
      end

      # POST /api/v1/plugin_marketplaces
      def create
        marketplace = current_account.plugin_marketplaces.build(marketplace_params)
        marketplace.creator = current_user

        if marketplace.save
          render_success(
            marketplace: marketplace.as_json,
            message: "Marketplace created successfully"
          )
        else
          render_validation_error(marketplace.errors)
        end
      end

      # PATCH /api/v1/plugin_marketplaces/:id
      def update
        if @marketplace.update(marketplace_params)
          render_success(
            marketplace: @marketplace.as_json,
            message: "Marketplace updated successfully"
          )
        else
          render_validation_error(@marketplace.errors)
        end
      end

      # DELETE /api/v1/plugin_marketplaces/:id
      def destroy
        @marketplace.destroy!
        render_success(message: "Marketplace deleted successfully")
      rescue StandardError => e
        render_error("Failed to delete marketplace: #{e.message}", status: :unprocessable_content)
      end

      # POST /api/v1/plugin_marketplaces/:id/sync
      def sync
        sync_service = PluginMarketplaceSyncService.new(@marketplace)
        result = sync_service.sync

        render_success(
          marketplace: @marketplace.reload.as_json,
          synced_plugins: result[:synced_count],
          new_plugins: result[:new_count],
          updated_plugins: result[:updated_count],
          message: "Synced #{result[:synced_count]} plugins"
        )
      rescue StandardError => e
        render_error("Sync failed: #{e.message}", status: :unprocessable_content)
      end

      private

      def set_marketplace
        @marketplace = current_account.plugin_marketplaces.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Marketplace not found")
      end

      def marketplace_params
        params.require(:marketplace).permit(
          :name, :owner, :description, :marketplace_type,
          :source_type, :source_url, :visibility,
          configuration: {}
        )
      end
    end
  end
end

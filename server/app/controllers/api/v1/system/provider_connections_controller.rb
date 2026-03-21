# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderConnectionsController < BaseController
        before_action :set_account
        before_action :set_connection, only: [:show, :update, :destroy, :test]

        def index
          authorize_permission!("system.connections.read")
          connections = @account.system_provider_connections.includes(:provider)
          connections = apply_filters(connections)
          connections = paginate(connections)
          render_success(provider_connections: serialize_collection(connections), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.connections.read")
          render_success(provider_connection: serialize_connection(@connection))
        end

        def create
          authorize_permission!("system.connections.create")
          connection = @account.system_provider_connections.build(connection_params)

          if connection.save
            render_success(provider_connection: serialize_connection(connection), status: :created)
          else
            render_validation_error(connection)
          end
        end

        def update
          authorize_permission!("system.connections.update")

          if @connection.update(connection_params)
            render_success(provider_connection: serialize_connection(@connection))
          else
            render_validation_error(@connection)
          end
        end

        def destroy
          authorize_permission!("system.connections.delete")

          if @connection.destroy
            render_success(message: "Connection deleted successfully")
          else
            render_error("Failed to delete connection", status: :unprocessable_entity)
          end
        end

        def test
          authorize_permission!("system.connections.test")
          @connection.test_connection!
          render_success(
            message: "Connection test initiated",
            data: {
              connection_id: @connection.id,
              last_tested_at: @connection.last_tested_at,
              status: @connection.status
            }
          )
        end

        private

        def set_connection
          @connection = @account.system_provider_connections.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider Connection")
        end

        def connection_params
          params.require(:provider_connection).permit(
            :name, :description, :provider_id, :endpoint_url, :enabled,
            :access_key, :secret_key, :tenant,
            config: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.for_provider(params[:provider_id]) if params[:provider_id].present?
          scope
        end

        def serialize_connection(connection)
          ::System::ProviderConnectionSerializer.new(connection).as_json
        end

        def serialize_collection(connections)
          connections.map { |c| serialize_connection(c) }
        end
      end
    end
  end
end

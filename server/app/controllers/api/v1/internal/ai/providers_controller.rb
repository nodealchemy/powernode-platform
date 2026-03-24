# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ProvidersController < InternalBaseController
          def index
            providers = ::Ai::Provider.all
            providers = providers.where(enabled: true) unless params[:include_disabled] == "true"

            render_success(providers: providers.map { |p|
              { id: p.id, name: p.name, provider_type: p.provider_type,
                api_base_url: p.api_base_url, enabled: p.enabled }
            })
          end
        end
      end
    end
  end
end

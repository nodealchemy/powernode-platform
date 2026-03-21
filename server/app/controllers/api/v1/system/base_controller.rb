# frozen_string_literal: true

module Api
  module V1
    module System
      class BaseController < ApplicationController
        include Paginatable

        before_action :require_system_permission

        private

        def require_system_permission
          # Override in subclasses to check specific permissions
        end

        def set_account
          @account = current_account
        end

        def system_params_filter(allowed_keys)
          params.require(:data).permit(*allowed_keys)
        end
      end
    end
  end
end

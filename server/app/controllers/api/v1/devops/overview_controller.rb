# frozen_string_literal: true

module Api
  module V1
    module Devops
      class OverviewController < ApplicationController
        def show
          service = ::Devops::OverviewService.new(account: current_user.account)
          data = service.generate(force_refresh: params[:refresh].present?)
          render_success(data)
        rescue StandardError => e
          Rails.logger.error("DevOps overview failed: #{e.message}")
          render_error("Failed to generate DevOps overview", :internal_server_error)
        end
      end
    end
  end
end

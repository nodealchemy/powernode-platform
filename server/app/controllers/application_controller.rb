# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Authentication
  include ApiResponse

  # Standard pagination parameters helper
  def pagination_params
    {
      page: [ params[:page]&.to_i || 1, 1 ].max,
      per_page: [ [ params[:per_page]&.to_i || 20, 1 ].max, 100 ].min
    }
  end
end

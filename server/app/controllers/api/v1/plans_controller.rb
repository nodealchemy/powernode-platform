# frozen_string_literal: true

class Api::V1::PlansController < ApplicationController
  skip_before_action :authenticate_request, only: [:public_index]

  # GET /api/v1/plans/public
  # Core-mode stub — returns empty when enterprise billing is not loaded
  def public_index
    render_success([])
  end
end

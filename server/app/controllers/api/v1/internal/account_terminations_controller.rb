# frozen_string_literal: true

# Internal API controller for worker service to manage account terminations
class Api::V1::Internal::AccountTerminationsController < Api::V1::Internal::InternalBaseController
  before_action :set_termination, only: [ :show, :update ]

  # GET /api/v1/internal/account_terminations
  def index
    terminations = Account::Termination.active
                                     .order(grace_period_ends_at: :asc)

    render_success(data: terminations.map { |t| termination_data(t) })
  end

  # GET /api/v1/internal/account_terminations/:id
  def show
    render_success(data: termination_data(@termination))
  end

  # PATCH/PUT /api/v1/internal/account_terminations/:id
  def update
    if @termination.update(termination_params)
      render_success(data: termination_data(@termination))
    else
      render_validation_error(@termination)
    end
  end

  private

  def set_termination
    @termination = Account::Termination.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account termination")
  end

  def termination_params
    params.permit(:status, :completed_at)
  end

  def termination_data(termination)
    {
      id: termination.id,
      account_id: termination.account_id,
      status: termination.status,
      reason: termination.reason,
      grace_period_ends_at: termination.grace_period_ends_at,
      completed_at: termination.completed_at,
      requested_at: termination.requested_at,
      created_at: termination.created_at,
      updated_at: termination.updated_at
    }
  end
end

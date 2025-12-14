# frozen_string_literal: true

# Internal API controller for worker service to manage data export requests
class Api::V1::Internal::DataExportRequestsController < Api::V1::Internal::InternalBaseController
  before_action :set_request, only: [ :show, :update ]

  # GET /api/v1/internal/data_export_requests/:id
  def show
    render_success(data: request_data(@request))
  end

  # POST /api/v1/internal/data_export_requests
  def create
    @request = DataExportRequest.new(request_params)

    if @request.save
      render_success(data: request_data(@request), status: :created)
    else
      render_validation_error(@request)
    end
  end

  # PATCH/PUT /api/v1/internal/data_export_requests/:id
  def update
    if @request.update(request_params)
      render_success(data: request_data(@request))
    else
      render_validation_error(@request)
    end
  end

  private

  def set_request
    @request = DataExportRequest.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Data export request")
  end

  def request_params
    params.permit(:user_id, :account_id, :status, :file_path, :file_url, :completed_at, :error_message, :metadata)
  end

  def request_data(request)
    {
      id: request.id,
      user_id: request.user_id,
      account_id: request.account_id,
      status: request.status,
      file_path: request.file_path,
      file_url: request.file_url,
      completed_at: request.completed_at,
      error_message: request.error_message,
      created_at: request.created_at,
      updated_at: request.updated_at
    }
  end
end

# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'oj'

# API Client for communicating with the main Rails backend
class ApiClient
  class ApiError < StandardError
    attr_reader :status, :response_body

    def initialize(message, status: nil, response_body: nil)
      super(message)
      @status = status
      @response_body = response_body
    end
  end

  def initialize(base_url: nil, worker_token: nil)
    @base_url = base_url || PowernodeWorker.application.config.backend_api_url
    @worker_token = worker_token || PowernodeWorker.application.config.worker_token
    @client = build_client
  end

  # Analytics and reporting endpoints
  def get_revenue_analytics(account_id: nil, start_date: nil, end_date: nil)
    params = {}
    params[:account_id] = account_id if account_id
    params[:start_date] = start_date if start_date
    params[:end_date] = end_date if end_date
    
    get('/api/v1/analytics/revenue', params)
  end

  def get_scheduled_reports_due
    get('/api/v1/reports/scheduled', { due: true })
  end

  def update_scheduled_report(report_id, attributes)
    put("/api/v1/reports/scheduled/#{report_id}", attributes)
  end

  def get_subscription_data(account_id: nil)
    params = {}
    params[:account_id] = account_id if account_id
    
    get('/api/v1/subscriptions', params)
  end

  def get_invoice_data(account_id: nil, status: nil)
    params = {}
    params[:account_id] = account_id if account_id
    params[:status] = status if status
    
    get('/api/v1/invoices', params)
  end

  def create_invoice(subscription_id, line_items)
    post('/api/v1/invoices', {
      subscription_id: subscription_id,
      line_items: line_items
    })
  end

  def process_payment(invoice_id, payment_method_id)
    post('/api/v1/payments', {
      invoice_id: invoice_id,
      payment_method_id: payment_method_id
    })
  end

  def update_subscription_status(subscription_id, status, metadata = {})
    put("/api/v1/subscriptions/#{subscription_id}", {
      status: status,
      metadata: metadata
    })
  end

  def get_webhook_events(status: 'pending', limit: 100)
    get('/api/v1/webhooks/events', { status: status, limit: limit })
  end

  def update_webhook_event(event_id, status, error_message = nil)
    put("/api/v1/webhooks/events/#{event_id}", {
      status: status,
      error_message: error_message
    })
  end

  def create_audit_log(user_id: nil, account_id:, action:, resource_type:, resource_id:, metadata: {})
    post('/api/v1/audit_logs', {
      user_id: user_id,
      account_id: account_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      source: 'background_job',
      metadata: metadata
    })
  end

  # Internal API endpoints for mailer data
  def get_user(user_id)
    get("/api/v1/internal/users/#{user_id}")
  end

  def get_account(account_id)
    get("/api/v1/internal/accounts/#{account_id}")
  end

  def get_invitation(invitation_id)
    get("/api/v1/internal/invitations/#{invitation_id}")
  end

  def generate_pdf_report(report_type, account_id: nil, start_date: nil, end_date: nil, user_id: nil)
    post('/api/v1/reports/generate', {
      reports: [{
        type: report_type,
        format: 'pdf'
      }],
      account_id: account_id,
      start_date: start_date,
      end_date: end_date,
      user_id: user_id
    })
  end

  def get(path, params = {})
    handle_response do
      @client.get(path, params)
    end
  end

  def post(path, body = {})
    handle_response do
      @client.post(path, body)
    end
  end

  def put(path, body = {})
    handle_response do
      @client.put(path, body)
    end
  end

  def delete(path)
    handle_response do
      @client.delete(path)
    end
  end

  private

  def build_client
    Faraday.new(url: @base_url) do |f|
      f.request :json
      f.request :retry, max: 3, interval: 0.5, backoff_factor: 2
      f.response :json, content_type: 'application/json', parser_options: { symbolize_names: true }
      
      f.headers['Authorization'] = "Bearer #{@worker_token}"
      f.headers['User-Agent'] = 'PowernodeWorkerAgent/1.0'
      f.headers['Accept'] = 'application/json'
      
      f.adapter Faraday.default_adapter
    end
  end

  def handle_response
    response = yield
    
    if response.success?
      response.body
    else
      error_message = "API request failed: #{response.status}"
      if response.body.is_a?(Hash) && response.body[:error]
        error_message += " - #{response.body[:error]}"
      end
      
      raise ApiError.new(error_message, status: response.status, response_body: response.body)
    end
  rescue Faraday::Error => e
    raise ApiError.new("Network error: #{e.message}")
  end
end
class ApiKeyUsage < ApplicationRecord
  # Associations
  belongs_to :api_key

  # Validations
  validates :endpoint, presence: true
  validates :http_method, presence: true, inclusion: { in: %w[GET POST PUT PATCH DELETE] }
  validates :status_code, presence: true, numericality: { in: 100..599 }
  validates :request_count, presence: true, numericality: { greater_than: 0 }

  # Note: metadata is a JSON column and doesn't need explicit serialization in Rails 8

  # Scopes
  scope :successful, -> { where(status_code: 200..299) }
  scope :client_errors, -> { where(status_code: 400..499) }
  scope :server_errors, -> { where(status_code: 500..599) }
  scope :for_endpoint, ->(endpoint) { where(endpoint: endpoint) }
  scope :for_method, ->(method) { where(http_method: method.upcase) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults
  before_validation :normalize_http_method

  # Instance methods
  def successful?
    (200..299).cover?(status_code)
  end

  def client_error?
    (400..499).cover?(status_code)
  end

  def server_error?
    (500..599).cover?(status_code)
  end

  def error?
    client_error? || server_error?
  end

  def status_category
    case status_code
    when 100..199 then 'informational'
    when 200..299 then 'success'
    when 300..399 then 'redirection'
    when 400..499 then 'client_error'
    when 500..599 then 'server_error'
    else 'unknown'
    end
  end

  # Class methods
  def self.aggregate_by_endpoint(time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    scope.group(:endpoint)
         .group(:http_method)
         .sum(:request_count)
  end

  def self.aggregate_by_status(time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    scope.group('FLOOR(status_code / 100) * 100')
         .sum(:request_count)
  end

  def self.top_endpoints(limit = 10, time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    scope.group(:endpoint)
         .order('sum_request_count DESC')
         .limit(limit)
         .sum(:request_count)
  end

  def self.usage_by_hour(date = Date.current)
    where(created_at: date.beginning_of_day..date.end_of_day)
      .group('EXTRACT(hour FROM created_at)')
      .sum(:request_count)
  end

  def self.error_rate(time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    total_requests = scope.sum(:request_count)
    return 0 if total_requests.zero?
    
    error_requests = scope.where('status_code >= 400').sum(:request_count)
    (error_requests.to_f / total_requests * 100).round(2)
  end

  private

  def set_defaults
    self.request_count ||= 1
    self.metadata ||= {}
  end

  def normalize_http_method
    self.http_method = http_method&.upcase
  end
end
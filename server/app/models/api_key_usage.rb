# frozen_string_literal: true

class ApiKeyUsage < ApplicationRecord
  # Associations
  belongs_to :api_key

  # THE MODEL AND ITS TABLE HAD DIVERGED (IMP-01a07d5a). Every reader here —
  # and in api_keys_controller.rb:284-285 — spoke of http_method / status_code
  # / metadata. The table has `method`, `response_status`, and no metadata
  # column at all, so `set_defaults` raised NoMethodError on `self.metadata`
  # before validation could even run: NO ApiKeyUsage row could ever be created.
  # ApiKey#record_usage! is the only writer, its only caller is the A2A
  # JSON-RPC endpoint's API-key authenticator, and that caller swallows
  # StandardError into nil — so API-key authentication on /api/v1/a2a had never
  # once succeeded, and the usage table has always been empty.
  #
  # ALIASED rather than renamed in either direction. Renaming the columns needs
  # a migration on a table whose indexes name them; renaming the readers churns
  # every consumer. The aliases bind the vocabulary the code already speaks to
  # the columns that actually exist, and `where`/validations resolve attribute
  # aliases, so scopes and error keys keep working unchanged.
  alias_attribute :http_method, :method
  alias_attribute :status_code, :response_status

  # Validations
  validates :endpoint, presence: true
  validates :http_method, presence: true, inclusion: { in: %w[GET POST PUT PATCH DELETE] }
  validates :status_code, presence: true, numericality: { in: 100..599 }
  validates :request_count, presence: true, numericality: { greater_than: 0 }

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
    when 100..199 then "informational"
    when 200..299 then "success"
    when 300..399 then "redirection"
    when 400..499 then "client_error"
    when 500..599 then "server_error"
    else "unknown"
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
    # Raw SQL, so it names the COLUMN and not the alias.
    scope.group("FLOOR(response_status / 100) * 100")
         .sum(:request_count)
  end

  def self.top_endpoints(limit = 10, time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    scope.group(:endpoint)
         .order("sum_request_count DESC")
         .limit(limit)
         .sum(:request_count)
  end

  def self.usage_by_hour(date = Date.current)
    where(created_at: date.beginning_of_day..date.end_of_day)
      .group("EXTRACT(hour FROM created_at)")
      .sum(:request_count)
  end

  def self.error_rate(time_range = nil)
    scope = time_range ? where(created_at: time_range) : all
    total_requests = scope.sum(:request_count)
    return 0 if total_requests.zero?

    error_requests = scope.where("response_status >= 400").sum(:request_count)
    (error_requests.to_f / total_requests * 100).round(2)
  end

  private

  def set_defaults
    self.request_count ||= 1
  end

  def normalize_http_method
    self.http_method = http_method&.upcase
  end
end

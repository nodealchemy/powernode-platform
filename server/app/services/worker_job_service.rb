# frozen_string_literal: true

require 'net/http'
require 'timeout'

# API client service for delegating async operations to the external worker service
# The Rails server contains NO worker functionality - all async ops handled by separate worker service
class WorkerJobService

  # Base URL for worker service API calls
  WORKER_API_BASE = ENV['WORKER_API_URL'] || 'http://localhost:3000/api/v1'

  class << self
    # Enqueue a notification email job
    def enqueue_notification_email(template_type, data = {})
      make_worker_request('POST', '/notifications/email', {
        template_type: template_type,
        data: data
      })
    end

    # Enqueue a billing job
    def enqueue_billing_job(job_type, data = {})
      make_worker_request('POST', '/billing/jobs', {
        job_type: job_type,
        data: data
      })
    end

    # Enqueue an analytics job
    def enqueue_analytics_job(job_type, data = {})
      make_worker_request('POST', '/analytics/jobs', {
        job_type: job_type,
        data: data
      })
    end

    # Enqueue a report generation job
    def enqueue_report_job(report_type, data = {})
      make_worker_request('POST', '/reports/generate', {
        report_type: report_type,
        data: data
      })
    end

    # Enqueue password reset email job
    def enqueue_password_reset_email(user_id)
      make_worker_request('POST', '/notifications/password_reset', {
        user_id: user_id
      })
    end

    # Enqueue email settings refresh job
    def enqueue_refresh_email_settings
      make_worker_request('POST', '/jobs', {
        job_class: 'RefreshEmailSettingsJob',
        args: [],
        options: {
          refresh_type: 'email_configuration',
          timestamp: Time.current.to_i
        }
      })
    end

    # Enqueue test email job
    def enqueue_test_email(email_address)
      make_worker_request('POST', '/jobs', {
        job_class: 'TestEmailJob',
        args: [email_address],
        options: {
          test_type: 'configuration_test',
          timestamp: Time.current.to_i
        }
      })
    end

    # Enqueue test worker job
    def enqueue_test_worker_job(worker_id, worker_name)
      make_worker_request('POST', '/jobs', {
        job_class: 'TestWorkerJob',
        args: [worker_id, worker_name],
        options: {
          test_type: 'worker_connectivity_test',
          worker_id: worker_id,
          timestamp: Time.current.to_i
        }
      })
    end

    private

    def make_worker_request(method, path, payload = {})

      uri = URI("#{WORKER_API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 10
      http.open_timeout = 5

      request = case method.upcase
                when 'GET'
                  Net::HTTP::Get.new(uri)
                when 'POST'
                  Net::HTTP::Post.new(uri)
                when 'PUT'
                  Net::HTTP::Put.new(uri)
                when 'DELETE'
                  Net::HTTP::Delete.new(uri)
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end

      # Set headers
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      
      # Add worker service authentication - generate JWT token
      service_token = generate_service_token
      request['Authorization'] = "Bearer #{service_token}" if service_token

      # Set body for requests that support it
      if %w[POST PUT PATCH].include?(method.upcase) && payload.present?
        request.body = payload.to_json
      end

      begin
        response = http.request(request)
        
        case response.code.to_i
        when 200..299
          Rails.logger.info "Worker job enqueued successfully: #{method} #{path}"
          JSON.parse(response.body) if response.body.present?
        when 400..499
          error_body = JSON.parse(response.body) rescue { error: response.body }
          Rails.logger.warn "Worker service client error (#{response.code}): #{error_body}"
          raise WorkerServiceError, "Client error: #{error_body['error'] || response.body}"
        when 500..599
          error_body = JSON.parse(response.body) rescue { error: response.body }
          Rails.logger.error "Worker service server error (#{response.code}): #{error_body}"
          raise WorkerServiceError, "Server error: #{error_body['error'] || response.body}"
        else
          Rails.logger.warn "Unexpected response from worker service (#{response.code}): #{response.body}"
          raise WorkerServiceError, "Unexpected response: #{response.code}"
        end
      rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
        Rails.logger.error "Worker service timeout: #{e.message}"
        raise WorkerServiceError, "Worker service timeout: #{e.message}"
      rescue Errno::ECONNREFUSED, SocketError => e
        Rails.logger.error "Worker service connection error: #{e.message}"
        raise WorkerServiceError, "Worker service unavailable: #{e.message}"
      rescue JSON::ParserError => e
        Rails.logger.error "Invalid JSON response from worker service: #{e.message}"
        raise WorkerServiceError, "Invalid response format from worker service"
      end
    end

    def generate_service_token
      return nil unless Rails.application.config.jwt_secret_key
      
      payload = {
        service: 'backend',
        type: 'service',
        iat: Time.current.to_i,
        exp: (Time.current + 1.hour).to_i
      }
      
      JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
    rescue StandardError => e
      Rails.logger.error "Failed to generate service token: #{e.message}"
      nil
    end
  end

  # Custom exception for worker service errors
  class WorkerServiceError < StandardError; end
end
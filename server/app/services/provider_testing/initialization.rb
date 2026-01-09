# frozen_string_literal: true

module ProviderTesting
  module Initialization
    extend ActiveSupport::Concern

    included do
      attr_reader :credential, :provider
    end

    def make_http_request(url, method: :get, headers: {}, body: nil, timeout: 10)
      require "net/http"
      require "uri"
      require "ostruct"

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = timeout
      http.open_timeout = timeout

      case method
      when :get
        request = Net::HTTP::Get.new(uri.request_uri)
      when :post
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = body if body
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      headers.each { |key, value| request[key] = value }

      response = http.request(request)

      Ai::ProviderTestService::ResponseWrapper.new(response)
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
      raise e
    rescue => e
      Ai::ProviderTestService::ResponseWrapper.new(nil, error: e.message)
    end

    def calculate_connection_quality(response_time_ms)
      return "failed" unless response_time_ms

      case response_time_ms
      when 0..500 then "excellent"
      when 501..1000 then "good"
      when 1001..2000 then "fair"
      else "poor"
      end
    end

    def calculate_stability_score(response_times)
      return 0.0 if response_times.empty?

      avg = response_times.sum / response_times.size.to_f
      variance = response_times.map { |t| (t - avg)**2 }.sum / response_times.size.to_f
      std_dev = Math.sqrt(variance)

      stability = avg > 0 ? 1.0 - (std_dev / avg).clamp(0.0, 1.0) : 0.0
      stability.round(2)
    end

    def error_result(error_type, message)
      { success: false, error_type: error_type, error_details: message }
    end

    def rate_response_time(response_time_ms)
      return "unknown" unless response_time_ms

      case response_time_ms
      when 0..500 then "excellent"
      when 501..1000 then "good"
      when 1001..2000 then "fair"
      else "poor"
      end
    end
  end
end

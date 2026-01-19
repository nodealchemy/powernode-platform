# frozen_string_literal: true

class Ai::ProviderTestService
  # Include extracted modules
  include ProviderTesting::Initialization
  include ProviderTesting::ConnectionTesting
  include ProviderTesting::HealthChecks
  include ProviderTesting::LoadTesting
  include ProviderTesting::ProviderAdapters
  include ProviderTesting::Reporting

  def initialize(credential)
    @credential = credential
    @provider = credential.provider
    @test_config = {
      timeout: 10,
      max_retries: 3,
      test_message: "Hello, this is a test message."
    }
    @test_results = {}
    @health_check_results = []
  end

  # Class methods
  class << self
    def test_all_credentials(account)
      credentials = account.ai_provider_credentials.includes(:provider)

      credentials.map do |credential|
        service = new(credential)
        result = service.test_connection

        {
          credential_id: credential.id,
          provider_name: credential.provider.name,
          success: result[:success],
          response_time_ms: result[:response_time_ms],
          error: result[:error_details]
        }
      end
    end

    def summarize_test_results(results)
      successful = results.count { |r| r[:success] }
      response_times = results.filter_map { |r| r[:response_time_ms] }

      sorted_by_time = results.select { |r| r[:response_time_ms] }.sort_by { |r| r[:response_time_ms] }

      {
        total_credentials: results.size,
        successful_tests: successful,
        failed_tests: results.size - successful,
        average_response_time: response_times.any? ? response_times.sum / response_times.size.to_f : 0,
        fastest_provider: sorted_by_time.first&.dig(:provider_name),
        slowest_provider: sorted_by_time.last&.dig(:provider_name)
      }
    end

    def health_check_all_providers
      Ai::Provider.active.map do |provider|
        {
          provider_id: provider.id,
          provider_name: provider.name,
          status: "active"
        }
      end
    end
  end

  # Helper class to wrap HTTP responses with success? method
  class ResponseWrapper
    attr_reader :body, :code, :message

    def initialize(response, error: nil)
      if response
        @body = response.body
        @code = response.code.to_i
        @message = response.message
        @success = response.is_a?(Net::HTTPSuccess)
      else
        @body = ""
        @code = 0
        @message = error || "Connection failed"
        @success = false
      end
    end

    def success?
      @success
    end
  end
end

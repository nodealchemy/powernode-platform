# frozen_string_literal: true

require_relative '../services/ollama_connectivity_tester'

# Runs the Ollama connectivity diagnostic suite and reports the result.
#
# Orchestrates the lifecycle (resolve test config, emit telemetry, persist /
# report results, handle fatal errors) and delegates the actual diagnostics
# (per-test HTTP/inference checks + status determination) to
# OllamaConnectivityTester. The tester calls back through this job's
# AiJobsConcern #make_http_request so circuit-breaker + external-API logging
# behaviour is preserved.
class OllamaConnectivityTestJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_testing', retry: 2

  def execute(test_config = {})
    @test_config = test_config.with_indifferent_access
    @results = {
      overall_status: 'testing',
      timestamp: Time.current.iso8601,
      tests: {}
    }

    begin
      log_info('AI operation started: ollama_connectivity_test', provider: 'ollama', test_config: @test_config)

      # Run comprehensive connectivity tests via the tester service
      outcome = ollama_tester.run
      @results[:tests] = outcome[:tests]

      # Determine overall status
      @results[:overall_status] = outcome[:overall_status]
      @results[:summary] = generate_test_summary

      # Report results to backend
      report_test_results

      log_info("Ollama connectivity test completed: #{@results[:overall_status]}")
      @results

    rescue StandardError => e
      handle_test_error(e)
      raise
    end
  end

  private

  # Diagnostic suite lives in the tester; the job stays a thin orchestrator.
  # `self` is passed as the HTTP requester so the tester reuses this job's
  # AiJobsConcern #make_http_request (circuit breaker + structured logging).
  def ollama_tester
    @ollama_tester ||= OllamaConnectivityTester.new(test_config: @test_config, http_requester: self)
  end

  def generate_test_summary
    passed_count = @results[:tests].count { |_, test| test[:status] == 'passed' }
    failed_count = @results[:tests].count { |_, test| test[:status] == 'failed' }
    warning_count = @results[:tests].count { |_, test| test[:status] == 'warning' }
    total_count = @results[:tests].size

    {
      total_tests: total_count,
      passed: passed_count,
      failed: failed_count,
      warnings: warning_count,
      success_rate: total_count > 0 ? ((passed_count.to_f / total_count) * 100).round(2) : 0
    }
  end

  def report_test_results
    # Send results to backend for storage and analysis
    backend_api_post("/api/v1/ai/testing/ollama_connectivity", {
      test_results: @results,
      test_config: @test_config
    })
  rescue StandardError => e
    log_warn("Failed to report test results to backend: #{e.message}")
  end

  def handle_test_error(error)
    log_error('AI operation failed: ollama_connectivity_test', error, provider: 'ollama', test_config: @test_config)

    @results[:overall_status] = 'failed'
    @results[:fatal_error] = {
      message: error.message,
      backtrace: error.backtrace&.first(5),
      occurred_at: Time.current.iso8601
    }

    # Try to report partial results
    report_test_results
  end
end

# frozen_string_literal: true

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
      log_ai_operation('ollama_connectivity_test', 'ollama', @test_config)

      # Run comprehensive connectivity tests
      test_basic_connection
      test_authentication
      test_model_listing
      test_model_availability
      test_basic_inference
      test_streaming_capability if @test_config[:test_streaming]
      test_performance_metrics

      # Determine overall status
      @results[:overall_status] = determine_overall_status
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

  def test_basic_connection
    test_name = 'basic_connection'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      base_url = @test_config[:base_url] || 'http://localhost:11434'

      # Test basic connectivity
      response = make_http_request(
        "#{base_url}/api/version",
        method: :get,
        timeout: 10
      )

      if response.code.to_i == 200
        version_data = JSON.parse(response.body) rescue {}
        @results[:tests][test_name] = {
          status: 'passed',
          response_code: response.code.to_i,
          version: version_data['version'],
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Connection failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_authentication
    test_name = 'authentication'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]

      headers = {}
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      # Test authenticated endpoint
      response = make_http_request(
        "#{base_url}/api/tags",
        method: :get,
        headers: headers,
        timeout: 15
      )

      if response.code.to_i == 200
        @results[:tests][test_name] = {
          status: 'passed',
          authentication_required: auth_token.present?,
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      elsif response.code.to_i == 401
        @results[:tests][test_name] = {
          status: 'failed',
          error: 'Authentication failed - invalid or missing credentials',
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Authentication test failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_model_listing
    test_name = 'model_listing'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]

      headers = {}
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      response = make_http_request(
        "#{base_url}/api/tags",
        method: :get,
        headers: headers,
        timeout: 15
      )

      if response.code.to_i == 200
        models_data = JSON.parse(response.body) rescue {}
        models = models_data['models'] || []

        @results[:tests][test_name] = {
          status: 'passed',
          model_count: models.size,
          available_models: models.map { |m| m['name'] },
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Model listing failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_model_availability
    test_name = 'model_availability'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      target_model = @test_config[:test_model] || 'llama2'
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]

      headers = {}
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      # Test if specific model is available
      response = make_http_request(
        "#{base_url}/api/show",
        method: :post,
        headers: headers.merge('Content-Type' => 'application/json'),
        body: { name: target_model }.to_json,
        timeout: 20
      )

      if response.code.to_i == 200
        model_info = JSON.parse(response.body) rescue {}
        @results[:tests][test_name] = {
          status: 'passed',
          model_name: target_model,
          model_info: {
            family: model_info['details']&.dig('family'),
            parameter_size: model_info['details']&.dig('parameter_size'),
            quantization_level: model_info['details']&.dig('quantization_level')
          },
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      elsif response.code.to_i == 404
        @results[:tests][test_name] = {
          status: 'failed',
          error: "Model '#{target_model}' not found on server",
          model_name: target_model,
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          model_name: target_model,
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Model availability test failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_basic_inference
    test_name = 'basic_inference'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      target_model = @test_config[:test_model] || 'llama2'
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]
      test_prompt = @test_config[:test_prompt] || 'Hello, can you respond with a simple greeting?'

      headers = { 'Content-Type' => 'application/json' }
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      start_time = Time.current

      response = make_http_request(
        "#{base_url}/api/chat",
        method: :post,
        headers: headers,
        body: {
          model: target_model,
          messages: [{ role: 'user', content: test_prompt }],
          stream: false
        }.to_json,
        timeout: 60
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        inference_data = JSON.parse(response.body) rescue {}
        response_content = inference_data.dig('message', 'content')

        @results[:tests][test_name] = {
          status: response_content.present? ? 'passed' : 'failed',
          model_name: target_model,
          prompt: test_prompt,
          response: response_content&.truncate(200),
          response_time_ms: response_time,
          eval_count: inference_data['eval_count'],
          eval_duration: inference_data['eval_duration'],
          tokens_per_second: calculate_tokens_per_second(inference_data),
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          model_name: target_model,
          response_time_ms: response_time,
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Inference test failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_streaming_capability
    test_name = 'streaming_capability'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      target_model = @test_config[:test_model] || 'llama2'
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]

      headers = { 'Content-Type' => 'application/json' }
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      start_time = Time.current

      response = make_http_request(
        "#{base_url}/api/chat",
        method: :post,
        headers: headers,
        body: {
          model: target_model,
          messages: [{ role: 'user', content: 'Count to 5' }],
          stream: true
        }.to_json,
        timeout: 30
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        # Basic streaming response validation
        chunks_received = response.body.split("\n").reject(&:empty?).size

        @results[:tests][test_name] = {
          status: chunks_received > 1 ? 'passed' : 'failed',
          model_name: target_model,
          chunks_received: chunks_received,
          response_time_ms: response_time,
          streaming_supported: chunks_received > 1,
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      else
        @results[:tests][test_name] = {
          status: 'failed',
          error: "HTTP #{response.code}: #{response.body}",
          response_code: response.code.to_i,
          completed_at: Time.current.iso8601
        }
      end

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Streaming test failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def test_performance_metrics
    test_name = 'performance_metrics'
    @results[:tests][test_name] = { status: 'running', started_at: Time.current.iso8601 }

    begin
      # Run multiple quick inference tests to get performance metrics
      target_model = @test_config[:test_model] || 'llama2'
      base_url = @test_config[:base_url] || 'http://localhost:11434'
      auth_token = @test_config[:auth_token]

      headers = { 'Content-Type' => 'application/json' }
      headers['Authorization'] = "Bearer #{auth_token}" if auth_token

      response_times = []
      token_rates = []

      3.times do |i|
        start_time = Time.current

        response = make_http_request(
          "#{base_url}/api/chat",
          method: :post,
          headers: headers,
          body: {
            model: target_model,
            messages: [{ role: 'user', content: "Say 'Test #{i + 1}'" }],
            stream: false
          }.to_json,
          timeout: 30
        )

        response_time = ((Time.current - start_time) * 1000).to_i
        response_times << response_time

        if response.code.to_i == 200
          data = JSON.parse(response.body) rescue {}
          tokens_per_second = calculate_tokens_per_second(data)
          token_rates << tokens_per_second if tokens_per_second > 0
        end

        sleep(1) # Brief pause between tests
      end

      avg_response_time = response_times.sum / response_times.size
      avg_token_rate = token_rates.any? ? (token_rates.sum / token_rates.size) : 0

      @results[:tests][test_name] = {
        status: response_times.all? { |t| t < 30000 } ? 'passed' : 'warning',
        avg_response_time_ms: avg_response_time,
        min_response_time_ms: response_times.min,
        max_response_time_ms: response_times.max,
        avg_tokens_per_second: avg_token_rate.round(2),
        test_count: response_times.size,
        completed_at: Time.current.iso8601
      }

    rescue StandardError => e
      @results[:tests][test_name] = {
        status: 'failed',
        error: "Performance test failed: #{e.message}",
        completed_at: Time.current.iso8601
      }
    end
  end

  def calculate_tokens_per_second(ollama_response)
    eval_count = ollama_response['eval_count']
    eval_duration = ollama_response['eval_duration'] # nanoseconds

    return 0 unless eval_count && eval_duration && eval_duration > 0

    # Convert nanoseconds to seconds and calculate tokens per second
    eval_seconds = eval_duration / 1_000_000_000.0
    eval_count / eval_seconds
  end

  def determine_overall_status
    test_statuses = @results[:tests].values.map { |test| test[:status] }

    if test_statuses.all? { |status| status == 'passed' }
      'passed'
    elsif test_statuses.any? { |status| status == 'failed' }
      'failed'
    elsif test_statuses.any? { |status| status == 'warning' }
      'warning'
    else
      'unknown'
    end
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
    log_ai_error('ollama_connectivity_test', 'ollama', error, @test_config)

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
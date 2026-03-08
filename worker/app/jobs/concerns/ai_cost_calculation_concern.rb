# frozen_string_literal: true

module AiCostCalculationConcern
  extend ActiveSupport::Concern

  private

  def calculate_generic_cost(provider, credentials, response)
    prompt_tokens = response[:prompt_tokens] || 0
    completion_tokens = response[:completion_tokens] || response[:output_tokens] || 0
    cached_tokens = response[:cached_tokens] || 0
    model_id = response[:model] || credentials.dig('configuration', 'model')
    provider_type = provider['provider_type']&.downcase

    if model_id && provider_type
      pricing_response = fetch_model_pricing(provider_type, model_id)
      if pricing_response
        input_per_1k = (pricing_response['input_per_1k'] || 0).to_f
        output_per_1k = (pricing_response['output_per_1k'] || 0).to_f
        cached_per_1k = (pricing_response['cached_input_per_1k'] || 0).to_f

        non_cached = [prompt_tokens - cached_tokens, 0].max
        input_cost = if cached_per_1k > 0 && cached_tokens > 0
                       (non_cached / 1000.0) * input_per_1k + (cached_tokens / 1000.0) * cached_per_1k
                     else
                       (prompt_tokens / 1000.0) * input_per_1k
                     end

        return input_cost + (completion_tokens / 1000.0) * output_per_1k
      end
    end

    0.0
  end

  def fetch_model_pricing(provider_type, model_id)
    response = api_client.get("/api/v1/ai/autonomy/pricing/lookup", {
      provider_type: provider_type,
      model_id: model_id
    })
    response['success'] ? response['data'] : nil
  rescue StandardError
    nil
  end

  def clean_ai_response(response)
    return response unless response.is_a?(String)

    # Remove <think>...</think> tags and their content
    cleaned = response.gsub(/<think>.*?<\/think>/m, '')

    # Trim excessive whitespace
    cleaned = cleaned.strip

    # Truncate if still too long (max 10KB for safety)
    max_length = 10_000
    if cleaned.length > max_length
      cleaned = cleaned[0...max_length] + "\n\n[Response truncated due to length]"
    end

    cleaned
  end

  def extract_output_data(ai_response)
    # Extract structured output data from AI response
    # Clean the response by removing thinking tags
    cleaned_response = clean_ai_response(ai_response[:response])

    output = {
      'content' => cleaned_response,
      'response' => cleaned_response,
      'model_used' => ai_response[:model],
      'tokens_used' => ai_response.dig(:metadata, :tokens_used) || 0,
      'response_time_ms' => ai_response.dig(:metadata, :response_time_ms) || 0,
      'cost_usd' => ai_response[:cost] || 0.0
    }

    # Try to extract structured data if response contains JSON
    begin
      if ai_response[:response] =~ /```json\s*(\{.*?\})\s*```/m
        json_content = $1
        parsed_json = JSON.parse(json_content)
        output['structured_data'] = parsed_json
      end
    rescue JSON::ParserError
      # Ignore JSON parsing errors
    end

    output
  end

  # Cost calculation methods
  def calculate_ollama_cost(_response_data)
    # Ollama is typically free/local, but we can track token usage
    0.0
  end

  def calculate_anthropic_cost(response_data, model)
    input_tokens = response_data.dig('usage', 'input_tokens') || 0
    output_tokens = response_data.dig('usage', 'output_tokens') || 0
    cached_tokens = response_data.dig('usage', 'cache_read_input_tokens') || 0

    pricing = resolve_pricing('anthropic', model)
    non_cached = [input_tokens - cached_tokens, 0].max

    input_cost = if pricing[:cached] > 0 && cached_tokens > 0
                   (non_cached / 1000.0) * pricing[:input] + (cached_tokens / 1000.0) * pricing[:cached]
                 else
                   (input_tokens / 1000.0) * pricing[:input]
                 end

    input_cost + (output_tokens / 1000.0) * pricing[:output]
  end

  def calculate_openai_cost(response_data, model)
    prompt_tokens = response_data.dig('usage', 'prompt_tokens') || 0
    completion_tokens = response_data.dig('usage', 'completion_tokens') || 0
    cached_tokens = response_data.dig('usage', 'cached_tokens') || 0

    pricing = resolve_pricing('openai', model)
    non_cached = [prompt_tokens - cached_tokens, 0].max

    input_cost = if pricing[:cached] > 0 && cached_tokens > 0
                   (non_cached / 1000.0) * pricing[:input] + (cached_tokens / 1000.0) * pricing[:cached]
                 else
                   (prompt_tokens / 1000.0) * pricing[:input]
                 end

    input_cost + (completion_tokens / 1000.0) * pricing[:output]
  end

  # Resolves pricing from database via the pricing lookup API
  def resolve_pricing(provider_type, model)
    db_pricing = fetch_model_pricing(provider_type, model)
    if db_pricing
      return {
        input: db_pricing['input_per_1k']&.to_f || 0,
        output: db_pricing['output_per_1k']&.to_f || 0,
        cached: db_pricing['cached_input_per_1k']&.to_f || 0
      }
    end

    { input: 0.0, output: 0.0, cached: 0.0 }
  end

  def calculate_provider_cost(provider, credentials, response, model = nil)
    calculate_generic_cost(provider, credentials, response)
  end
end

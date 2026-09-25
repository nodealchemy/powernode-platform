# frozen_string_literal: true

module AiCostCalculationConcern
  extend ActiveSupport::Concern

  private

  # Single source of truth for the cached-input-aware token cost: output priced
  # per 1K, input split into cached vs non-cached when a cached rate is set. All
  # provider cost methods delegate here so the formula can never drift between them.
  # Cache reads and writes are subsets of input_tokens; a rate the catalog does
  # not model (0) falls back to the input rate. Mirrors Ai::CostCalculationService.
  def token_cost(input_tokens:, output_tokens:, cached_tokens:, input_per_1k:, output_per_1k:, cached_per_1k:,
                 cache_creation_tokens: 0, cache_write_per_1k: 0)
    read_per_1k = cached_per_1k.positive? ? cached_per_1k : input_per_1k
    write_per_1k = cache_write_per_1k.positive? ? cache_write_per_1k : input_per_1k
    uncached = [ input_tokens - cached_tokens - cache_creation_tokens, 0 ].max
    input_cost = (uncached / 1000.0) * input_per_1k + (cached_tokens / 1000.0) * read_per_1k +
                 (cache_creation_tokens / 1000.0) * write_per_1k
    input_cost + (output_tokens / 1000.0) * output_per_1k
  end

  def calculate_generic_cost(provider, credentials, response)
    prompt_tokens = response[:prompt_tokens] || 0
    completion_tokens = response[:completion_tokens] || response[:output_tokens] || 0
    cached_tokens = response[:cached_tokens] || 0
    written_tokens = response[:cache_creation_tokens] || 0
    model_id = response[:model] || credentials.dig('configuration', 'model')
    provider_type = provider['provider_type']&.downcase

    if model_id && provider_type
      pricing_response = fetch_model_pricing(provider_type, model_id)
      if pricing_response
        input_per_1k = (pricing_response['input_per_1k'] || 0).to_f
        output_per_1k = (pricing_response['output_per_1k'] || 0).to_f
        cached_per_1k = (pricing_response['cached_input_per_1k'] || 0).to_f
        write_per_1k = (pricing_response['cache_write_per_1k'] || 0).to_f

        return token_cost(input_tokens: prompt_tokens, output_tokens: completion_tokens,
                          cached_tokens: cached_tokens, input_per_1k: input_per_1k,
                          output_per_1k: output_per_1k, cached_per_1k: cached_per_1k,
                          cache_creation_tokens: written_tokens, cache_write_per_1k: write_per_1k)
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

  # Raw Anthropic usage: input_tokens is only the uncached remainder, so the
  # total input adds cache reads and writes (the platform's prompt_tokens
  # contract, Ai::Llm::AnthropicMessages.usage).
  def calculate_anthropic_cost(response_data, model)
    usage = response_data['usage'] || {}
    cached_tokens = usage['cache_read_input_tokens'].to_i
    written_tokens = usage['cache_creation_input_tokens'].to_i
    input_tokens = usage['input_tokens'].to_i + cached_tokens + written_tokens
    output_tokens = usage['output_tokens'].to_i

    pricing = resolve_pricing('anthropic', model)
    token_cost(input_tokens: input_tokens, output_tokens: output_tokens, cached_tokens: cached_tokens,
               input_per_1k: pricing[:input], output_per_1k: pricing[:output], cached_per_1k: pricing[:cached],
               cache_creation_tokens: written_tokens, cache_write_per_1k: pricing[:cache_write].to_f)
  end

  def calculate_openai_cost(response_data, model)
    prompt_tokens = response_data.dig('usage', 'prompt_tokens') || 0
    completion_tokens = response_data.dig('usage', 'completion_tokens') || 0
    cached_tokens = response_data.dig('usage', 'cached_tokens') || 0

    pricing = resolve_pricing('openai', model)
    token_cost(input_tokens: prompt_tokens, output_tokens: completion_tokens, cached_tokens: cached_tokens,
               input_per_1k: pricing[:input], output_per_1k: pricing[:output], cached_per_1k: pricing[:cached])
  end

  # Resolves pricing from database via the pricing lookup API
  def resolve_pricing(provider_type, model)
    db_pricing = fetch_model_pricing(provider_type, model)
    if db_pricing
      return {
        input: db_pricing['input_per_1k']&.to_f || 0,
        output: db_pricing['output_per_1k']&.to_f || 0,
        cached: db_pricing['cached_input_per_1k']&.to_f || 0,
        cache_write: db_pricing['cache_write_per_1k']&.to_f || 0
      }
    end

    { input: 0.0, output: 0.0, cached: 0.0, cache_write: 0.0 }
  end

  def calculate_provider_cost(provider, credentials, response, model = nil)
    calculate_generic_cost(provider, credentials, response)
  end
end

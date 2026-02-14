# frozen_string_literal: true

module AiCostCalculationConcern
  extend ActiveSupport::Concern

  private

  def calculate_generic_cost(provider, credentials, response)
    # Check if provider has custom pricing configuration
    pricing = provider.dig('configuration', 'pricing') || credentials['pricing'] || {}

    return 0.0 if pricing.empty?

    tokens_used = response[:tokens_used] || 0
    prompt_tokens = response[:prompt_tokens] || 0
    completion_tokens = tokens_used - prompt_tokens

    # Calculate cost based on pricing configuration
    prompt_cost = (prompt_tokens / 1000.0) * (pricing['prompt_cost_per_1k'] || 0)
    completion_cost = (completion_tokens / 1000.0) * (pricing['completion_cost_per_1k'] || 0)

    prompt_cost + completion_cost
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

  def calculate_openai_cost(response_data, model)
    tokens = response_data.dig('usage', 'total_tokens') || 0

    # Simplified cost calculation (would need actual pricing per model)
    case model
    when /gpt-4/
      (tokens / 1000.0) * 0.03
    when /gpt-3.5/
      (tokens / 1000.0) * 0.002
    else
      (tokens / 1000.0) * 0.002
    end
  end

  def calculate_anthropic_cost(response_data, model)
    input_tokens = response_data.dig('usage', 'input_tokens') || 0
    output_tokens = response_data.dig('usage', 'output_tokens') || 0

    # Simplified cost calculation for Claude
    case model
    when /claude-3-opus/
      (input_tokens / 1000.0) * 0.015 + (output_tokens / 1000.0) * 0.075
    when /claude-3-sonnet/
      (input_tokens / 1000.0) * 0.003 + (output_tokens / 1000.0) * 0.015
    else
      (input_tokens / 1000.0) * 0.003 + (output_tokens / 1000.0) * 0.015
    end
  end
end

# frozen_string_literal: true

class AiProviderClientService
  include HTTParty

  attr_reader :provider, :credential, :credentials_data

  def initialize(ai_provider_credential)
    @credential = ai_provider_credential
    @provider = credential.ai_provider
    @credentials_data = credential.credentials
    @circuit_breaker = AiProviderCircuitBreakerService.new(@provider)
    setup_client_options
  end

  def generate_text(prompt, model: nil, **options)
    model_name = model || default_model_for_capability('text_generation')
    raise ArgumentError, 'No compatible model found' unless model_name

    @circuit_breaker.call do
      case provider.slug
      when 'openai'
        openai_generate_text(prompt, model_name, **options)
      when 'anthropic', 'claude-ai-anthropic'
        anthropic_generate_text(prompt, model_name, **options)
      when 'ollama', 'remote-ollama-server'
        ollama_generate_text(prompt, model_name, **options)
      else
        raise NotImplementedError, "Text generation not implemented for #{provider.name}"
      end
    end
  rescue AiProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Provider #{provider.name} is temporarily unavailable",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true
    }
  end

  def generate_image(prompt, model: nil, **options)
    model_name = model || default_model_for_capability('image_generation')
    raise ArgumentError, 'No compatible model found' unless model_name

    @circuit_breaker.call do
      case provider.slug
      when 'stability-ai'
        stability_generate_image(prompt, model_name, **options)
      when 'openai'
        openai_generate_image(prompt, model_name, **options)
      else
        raise NotImplementedError, "Image generation not implemented for #{provider.name}"
      end
    end
  rescue AiProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Provider #{provider.name} is temporarily unavailable",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true
    }
  end

  def execute_code(code, language: 'python', **options)
    model_name = default_model_for_capability('code_execution')
    raise ArgumentError, 'No compatible model found' unless model_name

    case provider.slug
    when 'replit'
      replit_execute_code(code, language, **options)
    else
      raise NotImplementedError, "Code execution not implemented for #{provider.name}"
    end
  end

  def stream_text(prompt, model: nil, **options, &block)
    model_name = model || default_model_for_capability('text_generation')
    raise ArgumentError, 'No compatible model found' unless model_name
    raise ArgumentError, 'Provider does not support streaming' unless provider.supports_streaming?

    case provider.slug
    when 'openai'
      openai_stream_text(prompt, model_name, **options, &block)
    when 'anthropic', 'claude-ai-anthropic'
      anthropic_stream_text(prompt, model_name, **options, &block)
    when 'ollama', 'remote-ollama-server'
      ollama_stream_text(prompt, model_name, **options, &block)
    else
      raise NotImplementedError, "Streaming not implemented for #{provider.name}"
    end
  end

  private

  def setup_client_options
    self.class.base_uri(provider.api_base_url)
    # Increased timeout for content generation tasks (blog writing, editing, etc.)
    # 120 seconds should be sufficient for generating 1000-1500 word articles
    self.class.default_timeout(120)
    
    # Set up common headers
    @headers = {
      'User-Agent' => 'Powernode-AI/1.0',
      'Content-Type' => 'application/json'
    }
    
    # Provider-specific authentication
    case provider.slug
    when 'openai'
      @headers['Authorization'] = "Bearer #{credentials_data['api_key']}"
      @headers['OpenAI-Organization'] = credentials_data['organization'] if credentials_data['organization']
    when 'anthropic', 'claude-ai-anthropic'
      @headers['x-api-key'] = credentials_data['api_key']
      @headers['anthropic-version'] = '2023-06-01'
    when 'stability-ai'
      @headers['Authorization'] = "Bearer #{credentials_data['api_key']}"
    when 'replit'
      @headers['Authorization'] = "Bearer #{credentials_data['api_key']}"
    end
  end

  def default_model_for_capability(capability)
    compatible_models = provider.supported_models.select do |model|
      provider.capabilities.include?(capability)
    end
    compatible_models.first&.dig('id')
  end

  # OpenAI implementations
  def openai_generate_text(prompt, model, **options)
    url = '/chat/completions'
    
    body = {
      model: model,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: options[:max_tokens] || 2000,
      temperature: options[:temperature] || 0.7
    }
    
    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def openai_stream_text(prompt, model, **options, &block)
    url = '/chat/completions'
    
    body = {
      model: model,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: options[:max_tokens] || 2000,
      temperature: options[:temperature] || 0.7,
      stream: true
    }
    
    # Streaming implementation would require special handling
    # This is a simplified version
    response = self.class.post(url, headers: @headers, body: body.to_json)
    result = handle_response(response)
    block.call(result) if block
    result
  end

  def openai_generate_image(prompt, model, **options)
    url = '/images/generations'
    
    body = {
      model: model,
      prompt: prompt,
      n: options[:n] || 1,
      size: options[:size] || '1024x1024'
    }
    
    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  # Anthropic implementations
  def anthropic_generate_text(prompt, model, **options)
    url = '/messages'

    body = {
      model: model,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: options[:max_tokens] || 2000
    }

    # Add system prompt if provided
    body[:system] = options[:system_prompt] if options[:system_prompt].present?

    # Add temperature if provided
    body[:temperature] = options[:temperature] if options[:temperature]

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def anthropic_stream_text(prompt, model, **options, &block)
    # Similar to OpenAI but with Anthropic's streaming format
    anthropic_generate_text(prompt, model, **options)
  end

  # Ollama implementations
  def ollama_generate_text(prompt, model, **options)
    url = '/api/generate'

    body = {
      model: model,
      prompt: prompt,
      stream: false
    }

    # Ollama uses different base URI
    base_url = credentials_data['base_url'] || 'http://localhost:11434'
    full_url = "#{base_url}#{url}"

    response = HTTParty.post(full_url, headers: @headers, body: body.to_json)

    # Handle Ollama-specific response format
    if response.code == 200
      data = JSON.parse(response.body)
      content = data['response'] || 'No response generated'

      {
        success: true,
        content: content,
        text: content, # For backward compatibility
        data: data,
        status_code: response.code,
        provider: provider.name,
        cost: 0, # Ollama is typically free/local
        metadata: {
          model: model,
          done: data['done'],
          total_duration: data['total_duration'],
          load_duration: data['load_duration'],
          prompt_eval_count: data['prompt_eval_count'],
          eval_count: data['eval_count']
        }
      }
    else
      handle_response(response)
    end
  rescue StandardError => e
    {
      success: false,
      error: "Ollama request failed: #{e.message}",
      status_code: nil,
      provider: provider.name
    }
  end

  def ollama_stream_text(prompt, model, **options, &block)
    # Ollama streaming implementation
    ollama_generate_text(prompt, model, **options)
  end

  # Stability AI implementations
  def stability_generate_image(prompt, model, **options)
    url = "/generation/#{model}/text-to-image"
    
    body = {
      text_prompts: [{ text: prompt }],
      cfg_scale: options[:cfg_scale] || 7,
      height: options[:height] || 1024,
      width: options[:width] || 1024,
      samples: options[:samples] || 1,
      steps: options[:steps] || 30
    }
    
    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  # Replit implementations
  def replit_execute_code(code, language, **options)
    url = '/repls'
    
    body = {
      title: "Code Execution - #{Time.current.to_i}",
      language: language,
      files: {
        'main.py' => code  # Simplified - would need language-specific files
      },
      is_private: true
    }
    
    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def handle_response(response)
    case response.code
    when 200, 201
      {
        success: true,
        data: response.parsed_response,
        status_code: response.code,
        provider: provider.name
      }
    when 401
      {
        success: false,
        error: 'Authentication failed - check API credentials',
        status_code: response.code,
        provider: provider.name
      }
    when 429
      {
        success: false,
        error: 'Rate limit exceeded - please try again later',
        status_code: response.code,
        provider: provider.name
      }
    when 500..599
      {
        success: false,
        error: 'Provider service error - please try again',
        status_code: response.code,
        provider: provider.name
      }
    else
      {
        success: false,
        error: response.parsed_response&.dig('error') || 'Unknown error occurred',
        status_code: response.code,
        provider: provider.name
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Request failed: #{e.message}",
      status_code: nil,
      provider: provider.name
    }
  end

  # Batch completion for multiple prompts - optimizes API calls
  def batch_completion(prompts, model: nil, **options)
    model_name = model || default_model_for_capability('text_generation')
    raise ArgumentError, 'No compatible model found' unless model_name
    raise ArgumentError, 'Prompts must be an array' unless prompts.is_a?(Array)
    return { success: true, results: [] } if prompts.empty?

    batch_size = options[:batch_size] || 5
    results = []
    
    # Process in batches to avoid overwhelming the provider
    prompts.each_slice(batch_size) do |batch_prompts|
      batch_results = process_batch_prompts(batch_prompts, model_name, **options)
      results.concat(batch_results)
    end

    {
      success: true,
      results: results,
      total_processed: prompts.size,
      batches_processed: (prompts.size.to_f / batch_size).ceil
    }
  rescue StandardError => e
    Rails.logger.error "Batch completion failed: #{e.message}"
    {
      success: false,
      error: "Batch completion failed: #{e.message}",
      results: results, # Return partial results if any
      total_processed: results.size
    }
  end

  private

  def process_batch_prompts(prompts, model_name, **options)
    case provider.slug
    when 'openai'
      process_openai_batch(prompts, model_name, **options)
    when 'anthropic', 'claude-ai-anthropic'
      process_anthropic_batch(prompts, model_name, **options)
    else
      # Fallback: process each prompt individually
      prompts.map do |prompt|
        result = generate_text(prompt, model: model_name, **options)
        {
          prompt: prompt,
          result: result[:success] ? result[:text] : nil,
          success: result[:success],
          error: result[:error],
          cost: result[:cost] || 0
        }
      end
    end
  end

  def process_openai_batch(prompts, model_name, **options)
    # OpenAI doesn't have native batch API for chat completions yet
    # Process individually with rate limiting
    prompts.map.with_index do |prompt, index|
      # Add small delay between requests to avoid rate limits
      sleep(0.1) if index > 0
      
      result = openai_generate_text(prompt, model_name, **options)
      {
        prompt: prompt,
        result: result[:success] ? result[:text] : nil,
        success: result[:success],
        error: result[:error],
        cost: result[:cost] || 0
      }
    end
  end

  def process_anthropic_batch(prompts, model_name, **options)
    # Anthropic also processes individually for now
    prompts.map.with_index do |prompt, index|
      sleep(0.1) if index > 0
      
      result = anthropic_generate_text(prompt, model_name, **options)
      {
        prompt: prompt,
        result: result[:success] ? result[:text] : nil,
        success: result[:success],
        error: result[:error],
        cost: result[:cost] || 0
      }
    end
  end
end
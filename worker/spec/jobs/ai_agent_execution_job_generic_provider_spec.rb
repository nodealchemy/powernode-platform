# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentExecutionJob, 'generic AI provider' do
  let(:execution_id) { SecureRandom.uuid }
  let(:provider_id) { SecureRandom.uuid }
  let(:credentials_id) { SecureRandom.uuid }

  let(:job) { described_class.new }

  let(:generic_provider) do
    {
      'id' => provider_id,
      'name' => 'Custom AI Provider',
      'provider_type' => 'custom',
      'api_endpoint' => 'https://api.custom-ai.example.com/v1/chat',
      'configuration' => {
        'auth_type' => 'api_key',
        'api_key_header' => 'X-API-Key',
        'api_key_prefix' => nil,
        'request_format' => 'openai',
        'response_format' => 'openai',
        'default_model' => 'custom-model-v1',
        'max_tokens' => 4096,
        'temperature' => 0.7,
        'pricing' => {
          'prompt_cost_per_1k' => 0.002,
          'completion_cost_per_1k' => 0.004
        }
      }
    }
  end

  let(:credentials) do
    {
      'id' => credentials_id,
      'api_key' => 'test_api_key_123',
      'model' => 'custom-model-v1'
    }
  end

  let(:prompt) { 'Explain the benefits of cloud computing' }
  let(:context) { [{ role: 'system', content: 'You are a helpful assistant.' }] }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)
  end

  describe '#build_generic_auth_headers' do
    context 'with api_key auth type' do
      it 'builds header with custom header name' do
        provider = generic_provider.deep_dup
        provider['configuration']['api_key_header'] = 'X-Custom-Key'
        provider['configuration']['api_key_prefix'] = ''  # Empty string = no prefix

        headers = job.send(:build_generic_auth_headers, provider, credentials)

        expect(headers['X-Custom-Key']).to eq('test_api_key_123')
      end

      it 'builds header with Bearer prefix' do
        provider = generic_provider.deep_dup
        provider['configuration']['auth_type'] = 'api_key'
        provider['configuration']['api_key_header'] = 'Authorization'
        provider['configuration']['api_key_prefix'] = 'Bearer'

        headers = job.send(:build_generic_auth_headers, provider, credentials)

        expect(headers['Authorization']).to eq('Bearer test_api_key_123')
      end
    end

    context 'with basic auth' do
      let(:basic_credentials) do
        {
          'username' => 'user123',
          'password' => 'pass456'
        }
      end

      it 'builds Basic authorization header' do
        provider = generic_provider.deep_dup
        provider['configuration']['auth_type'] = 'basic'

        headers = job.send(:build_generic_auth_headers, provider, basic_credentials)

        expected = "Basic #{Base64.strict_encode64('user123:pass456')}"
        expect(headers['Authorization']).to eq(expected)
      end
    end

    context 'with custom_header auth' do
      it 'uses custom header name and value' do
        provider = generic_provider.deep_dup
        provider['configuration']['auth_type'] = 'custom_header'
        provider['configuration']['custom_header_name'] = 'X-Service-Token'

        headers = job.send(:build_generic_auth_headers, provider, credentials)

        expect(headers['X-Service-Token']).to eq('test_api_key_123')
      end
    end

    context 'with custom headers in config' do
      it 'merges additional custom headers' do
        provider = generic_provider.deep_dup
        provider['configuration']['custom_headers'] = {
          'X-Request-ID' => '12345',
          'X-Client-Version' => '2.0'
        }

        headers = job.send(:build_generic_auth_headers, provider, credentials)

        expect(headers['X-Request-ID']).to eq('12345')
        expect(headers['X-Client-Version']).to eq('2.0')
      end
    end
  end

  describe '#build_generic_request_body' do
    let(:agent_execution) do
      { 'ai_agent' => { 'configuration' => { 'model' => 'agent-model' } } }
    end

    before do
      job.instance_variable_set(:@agent_execution, agent_execution)
    end

    context 'with OpenAI format' do
      it 'builds OpenAI-compatible request' do
        provider = generic_provider.deep_dup
        provider['configuration']['request_format'] = 'openai'

        body = job.send(:build_generic_request_body, provider, credentials, prompt, context)

        expect(body[:model]).to be_present
        expect(body[:messages]).to be_an(Array)
        expect(body[:messages].last[:content]).to eq(prompt)
        expect(body[:max_tokens]).to eq(4096)
      end
    end

    context 'with Anthropic format' do
      it 'builds Anthropic-compatible request' do
        provider = generic_provider.deep_dup
        provider['configuration']['request_format'] = 'anthropic'

        body = job.send(:build_generic_request_body, provider, credentials, prompt, context)

        expect(body[:model]).to be_present
        expect(body[:system]).to eq('You are a helpful assistant.')
        expect(body[:messages]).to be_an(Array)
        expect(body[:max_tokens]).to eq(4096)
      end
    end

    context 'with Ollama format' do
      it 'builds Ollama-compatible request' do
        provider = generic_provider.deep_dup
        provider['configuration']['request_format'] = 'ollama'

        body = job.send(:build_generic_request_body, provider, credentials, prompt, context)

        expect(body[:model]).to be_present
        expect(body[:messages]).to be_an(Array)
        expect(body[:stream]).to eq(false)
      end
    end

    context 'with simple text format' do
      it 'builds simple text completion request' do
        provider = generic_provider.deep_dup
        provider['configuration']['request_format'] = 'simple'

        body = job.send(:build_generic_request_body, provider, credentials, prompt, context)

        expect(body[:prompt]).to eq(prompt)
        expect(body[:model]).to be_present
      end
    end

    context 'with custom template format' do
      it 'renders custom template with variables' do
        provider = generic_provider.deep_dup
        provider['configuration']['request_format'] = 'custom'
        provider['configuration']['request_template'] = {
          'input' => {
            'text' => '{{prompt}}',
            'model_name' => '{{model}}'
          }
        }

        body = job.send(:build_generic_request_body, provider, credentials, prompt, context)

        expect(body['input']['text']).to eq(prompt)
      end
    end
  end

  describe '#extract_generic_response' do
    context 'with OpenAI format' do
      it 'extracts content from OpenAI response' do
        response = {
          'choices' => [{ 'message' => { 'content' => 'AI response' } }],
          'usage' => { 'total_tokens' => 100, 'prompt_tokens' => 20 }
        }

        result = job.send(:extract_generic_response, generic_provider, response)

        expect(result[:content]).to eq('AI response')
        expect(result[:tokens_used]).to eq(100)
        expect(result[:prompt_tokens]).to eq(20)
      end
    end

    context 'with Anthropic format' do
      it 'extracts content from Anthropic response' do
        provider = generic_provider.deep_dup
        provider['configuration']['response_format'] = 'anthropic'

        response = {
          'content' => [{ 'text' => 'Claude response' }],
          'usage' => { 'input_tokens' => 30, 'output_tokens' => 70 }
        }

        result = job.send(:extract_generic_response, provider, response)

        expect(result[:content]).to eq('Claude response')
        expect(result[:tokens_used]).to eq(70)
        expect(result[:prompt_tokens]).to eq(30)
      end
    end

    context 'with custom response path' do
      it 'extracts using custom path' do
        provider = generic_provider.deep_dup
        provider['configuration']['response_format'] = 'custom'
        provider['configuration']['response_content_path'] = 'data.result.text'
        provider['configuration']['response_tokens_path'] = 'meta.tokens'

        response = {
          'data' => { 'result' => { 'text' => 'Custom response' } },
          'meta' => { 'tokens' => 50 }
        }

        result = job.send(:extract_generic_response, provider, response)

        expect(result[:content]).to eq('Custom response')
        expect(result[:tokens_used]).to eq(50)
      end
    end

    context 'with unknown format' do
      it 'tries common response paths' do
        provider = generic_provider.deep_dup
        provider['configuration']['response_format'] = 'unknown'

        response = { 'response' => 'Fallback content' }

        result = job.send(:extract_generic_response, provider, response)

        expect(result[:content]).to eq('Fallback content')
      end
    end
  end

  describe '#dig_path' do
    it 'navigates nested hashes' do
      data = { 'a' => { 'b' => { 'c' => 'value' } } }
      expect(job.send(:dig_path, data, 'a.b.c')).to eq('value')
    end

    it 'handles array indices' do
      data = { 'items' => [{ 'name' => 'first' }, { 'name' => 'second' }] }
      expect(job.send(:dig_path, data, 'items.1.name')).to eq('second')
    end

    it 'returns nil for missing paths' do
      data = { 'a' => 'b' }
      expect(job.send(:dig_path, data, 'x.y.z')).to be_nil
    end
  end

  describe '#calculate_generic_cost' do
    it 'calculates cost based on pricing config' do
      response = { tokens_used: 1000, prompt_tokens: 400 }

      cost = job.send(:calculate_generic_cost, generic_provider, credentials, response)

      # 400 prompt tokens * 0.002/1k + 600 completion tokens * 0.004/1k
      expected = (400 / 1000.0) * 0.002 + (600 / 1000.0) * 0.004
      expect(cost).to eq(expected)
    end

    it 'returns 0 when no pricing configured' do
      provider = generic_provider.deep_dup
      provider['configuration'].delete('pricing')

      response = { tokens_used: 1000, prompt_tokens: 400 }

      cost = job.send(:calculate_generic_cost, provider, credentials, response)

      expect(cost).to eq(0.0)
    end
  end

  describe '#deep_render_template' do
    it 'renders string templates' do
      template = 'Hello {{name}}'
      variables = { 'name' => 'World' }

      result = job.send(:deep_render_template, template, variables)

      expect(result).to eq('Hello World')
    end

    it 'renders nested hash templates' do
      template = {
        'outer' => {
          'inner' => '{{value}}'
        }
      }
      variables = { 'value' => 'test' }

      result = job.send(:deep_render_template, template, variables)

      expect(result['outer']['inner']).to eq('test')
    end

    it 'renders array templates' do
      template = ['{{a}}', '{{b}}']
      variables = { 'a' => '1', 'b' => '2' }

      result = job.send(:deep_render_template, template, variables)

      expect(result).to eq(['1', '2'])
    end
  end
end

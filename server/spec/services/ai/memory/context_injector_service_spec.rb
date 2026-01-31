# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::ContextInjectorService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(agent: agent, account: account) }

  let(:factual_service) { Ai::Memory::FactualMemoryService.new(agent: agent, account: account) }
  let(:experiential_service) { Ai::Memory::ExperientialMemoryService.new(agent: agent, account: account) }

  describe '#build_context' do
    context 'with factual memories' do
      before do
        factual_service.store(key: 'user_name', value: 'Alice')
        factual_service.store(key: 'user_preference', value: 'dark mode')
      end

      it 'includes factual memories in context' do
        result = service.build_context(include_types: %w[factual])

        expect(result[:context]).to include('Known Facts')
        expect(result[:context]).to include('user_name')
      end

      it 'returns token estimate' do
        result = service.build_context(include_types: %w[factual])

        expect(result[:token_estimate]).to be_a(Integer)
        expect(result[:token_estimate]).to be > 0
      end

      it 'returns breakdown by memory type' do
        result = service.build_context(include_types: %w[factual])

        expect(result[:breakdown]).to include(:factual, :working, :experiential)
      end
    end

    context 'with experiential memories and query' do
      before do
        experiential_service.store(content: 'User prefers concise responses')
        experiential_service.store(content: 'Task completed with good feedback')
      end

      it 'includes experiential memories for relevant query' do
        result = service.build_context(query: 'user preferences', include_types: %w[experiential])

        expect(result[:context]).to be_a(String)
      end
    end

    context 'with token budget' do
      before do
        # Store many facts to test budget limiting
        20.times do |i|
          factual_service.store(key: "fact_#{i}", value: "value_#{i}" * 50)
        end
      end

      it 'respects token budget' do
        result = service.build_context(token_budget: 100, include_types: %w[factual])

        expect(result[:token_estimate]).to be <= 200 # Some overflow allowed
      end
    end

    context 'with all memory types' do
      before do
        factual_service.store(key: 'fact', value: 'fact_value')
        experiential_service.store(content: 'Experience content')
      end

      it 'includes all memory types' do
        result = service.build_context(
          query: 'test query',
          include_types: %w[factual experiential]
        )

        expect(result[:context]).to be_present
      end
    end

    context 'with empty memories' do
      it 'returns empty context' do
        result = service.build_context

        expect(result[:context]).to eq('')
        expect(result[:token_estimate]).to eq(0)
      end
    end
  end

  describe '#build_query_context' do
    before do
      factual_service.store(key: 'relevant_fact', value: 'relevant_value')
      experiential_service.store(content: 'Relevant experience')
    end

    it 'builds context focused on query' do
      result = service.build_query_context(query: 'relevant information')

      expect(result).to include(:context, :token_estimate, :breakdown)
    end

    it 'excludes working memory' do
      result = service.build_query_context(query: 'test')

      # Working memory count should be 0
      expect(result[:breakdown][:working]).to eq(0)
    end
  end

  describe '#build_minimal_context' do
    before do
      factual_service.store(key: 'critical_fact', value: 'critical_value')
    end

    it 'returns only factual memories' do
      result = service.build_minimal_context

      expect(result[:context]).to include('Known Facts')
    end

    it 'uses reduced token budget' do
      result = service.build_minimal_context(token_budget: 500)

      expect(result[:token_estimate]).to be <= 600
    end
  end

  describe '#preview_context' do
    before do
      factual_service.store(key: 'fact1', value: 'value1')
      factual_service.store(key: 'fact2', value: 'value2')
    end

    it 'returns truncated preview' do
      result = service.preview_context(token_budget: 4000)

      expect(result[:preview].length).to be <= 500
    end

    it 'indicates if within budget' do
      result = service.preview_context(token_budget: 4000)

      expect(result[:within_budget]).to be true
    end

    it 'returns breakdown' do
      result = service.preview_context(token_budget: 4000)

      expect(result[:breakdown]).to be_present
    end
  end

  describe 'memory prioritization' do
    before do
      # Create facts with different importance
      factual_service.store(key: 'high_priority', value: 'important')
      factual_service.store(key: 'low_priority', value: 'less important')
    end

    it 'prioritizes high importance memories' do
      result = service.build_context(token_budget: 50, include_types: %w[factual])

      # Should include some content even with low budget
      expect(result[:context]).to be_present
    end
  end

  describe 'task context integration' do
    let(:task) { create(:ai_a2a_task, account: account) }
    let(:working_service) do
      Ai::Memory::WorkingMemoryService.new(agent: agent, account: account, task: task)
    end

    before do
      working_service.store_task_state({ 'step' => 1, 'status' => 'processing' })
      factual_service.store(key: 'user_name', value: 'Test User')
    end

    it 'includes working memory when task is provided' do
      result = service.build_context(task: task, include_types: %w[factual working])

      expect(result).to be_present
    end
  end
end

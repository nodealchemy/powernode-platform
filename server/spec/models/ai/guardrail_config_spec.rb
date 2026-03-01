# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GuardrailConfig, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent').with_foreign_key('ai_agent_id').optional }
  end

  describe 'validations' do
    subject { build(:ai_guardrail_config) }

    it { should validate_presence_of(:name) }

    describe 'name uniqueness' do
      let!(:existing_config) { create(:ai_guardrail_config) }

      it 'validates uniqueness of name within account scope' do
        duplicate = build(:ai_guardrail_config,
                          name: existing_config.name,
                          account: existing_config.account)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        different_account = create(:account)
        config = build(:ai_guardrail_config,
                       name: existing_config.name,
                       account: different_account)
        expect(config).to be_valid
      end
    end

    describe 'toxicity_threshold' do
      it { should validate_numericality_of(:toxicity_threshold).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1).allow_nil }

      it 'rejects values greater than 1' do
        config = build(:ai_guardrail_config, toxicity_threshold: 1.5)
        expect(config).not_to be_valid
        expect(config.errors[:toxicity_threshold]).to be_present
      end

      it 'rejects negative values' do
        config = build(:ai_guardrail_config, toxicity_threshold: -0.1)
        expect(config).not_to be_valid
      end

      it 'allows nil' do
        config = build(:ai_guardrail_config, toxicity_threshold: nil)
        expect(config).to be_valid
      end

      it 'allows boundary value 0' do
        config = build(:ai_guardrail_config, toxicity_threshold: 0)
        expect(config).to be_valid
      end

      it 'allows boundary value 1' do
        config = build(:ai_guardrail_config, toxicity_threshold: 1)
        expect(config).to be_valid
      end
    end

    describe 'pii_sensitivity' do
      it { should validate_numericality_of(:pii_sensitivity).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1).allow_nil }

      it 'rejects values greater than 1' do
        config = build(:ai_guardrail_config, pii_sensitivity: 1.01)
        expect(config).not_to be_valid
      end

      it 'allows nil' do
        config = build(:ai_guardrail_config, pii_sensitivity: nil)
        expect(config).to be_valid
      end
    end

    describe 'max_input_tokens' do
      it { should validate_numericality_of(:max_input_tokens).is_greater_than(0).allow_nil }

      it 'rejects zero' do
        config = build(:ai_guardrail_config, max_input_tokens: 0)
        expect(config).not_to be_valid
      end

      it 'rejects negative values' do
        config = build(:ai_guardrail_config, max_input_tokens: -100)
        expect(config).not_to be_valid
      end

      it 'allows nil' do
        config = build(:ai_guardrail_config, max_input_tokens: nil)
        expect(config).to be_valid
      end

      it 'allows positive values' do
        config = build(:ai_guardrail_config, max_input_tokens: 50_000)
        expect(config).to be_valid
      end
    end

    describe 'max_output_tokens' do
      it { should validate_numericality_of(:max_output_tokens).is_greater_than(0).allow_nil }

      it 'rejects zero' do
        config = build(:ai_guardrail_config, max_output_tokens: 0)
        expect(config).not_to be_valid
      end

      it 'rejects negative values' do
        config = build(:ai_guardrail_config, max_output_tokens: -1)
        expect(config).not_to be_valid
      end

      it 'allows nil' do
        config = build(:ai_guardrail_config, max_output_tokens: nil)
        expect(config).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }
    let!(:active_config) { create(:ai_guardrail_config, account: account, is_active: true) }
    let!(:inactive_config) { create(:ai_guardrail_config, :inactive, account: account) }
    let!(:agent_config) { create(:ai_guardrail_config, account: account, agent: agent) }
    let!(:global_config) { create(:ai_guardrail_config, account: account, agent: nil, name: 'Global Config') }

    describe '.active' do
      it 'returns only active configs' do
        results = Ai::GuardrailConfig.active
        expect(results).to include(active_config)
        expect(results).not_to include(inactive_config)
      end
    end

    describe '.for_agent' do
      it 'returns configs for the specified agent' do
        results = Ai::GuardrailConfig.for_agent(agent.id)
        expect(results).to include(agent_config)
        expect(results).not_to include(global_config)
      end

      it 'returns empty when agent has no config' do
        other_agent = create(:ai_agent, account: account)
        results = Ai::GuardrailConfig.for_agent(other_agent.id)
        expect(results).to be_empty
      end
    end

    describe '.global' do
      it 'returns configs without an agent association' do
        results = Ai::GuardrailConfig.global
        expect(results).to include(global_config)
        expect(results).not_to include(agent_config)
      end
    end

    describe 'scope chaining' do
      it 'chains active and global scopes' do
        results = Ai::GuardrailConfig.active.global
        expect(results).to include(global_config)
        expect(results).not_to include(inactive_config)
        expect(results).not_to include(agent_config)
      end

      it 'chains active and for_agent scopes' do
        results = Ai::GuardrailConfig.active.for_agent(agent.id)
        expect(results).to include(agent_config)
      end
    end
  end

  describe '#record_check!' do
    let(:config) { create(:ai_guardrail_config, total_checks: 0, total_blocks: 0) }

    it 'increments total_checks' do
      expect { config.record_check!(blocked: false) }.to change { config.reload.total_checks }.by(1)
    end

    it 'does not increment total_blocks when not blocked' do
      expect { config.record_check!(blocked: false) }.not_to change { config.reload.total_blocks }
    end

    it 'increments both total_checks and total_blocks when blocked' do
      config.record_check!(blocked: true)
      config.reload
      expect(config.total_checks).to eq(1)
      expect(config.total_blocks).to eq(1)
    end

    it 'accumulates counts over multiple calls' do
      3.times { config.record_check!(blocked: false) }
      2.times { config.record_check!(blocked: true) }
      config.reload
      expect(config.total_checks).to eq(5)
      expect(config.total_blocks).to eq(2)
    end
  end

  describe '#block_rate' do
    it 'returns 0 when no checks have been performed' do
      config = build(:ai_guardrail_config, total_checks: 0, total_blocks: 0)
      expect(config.block_rate).to eq(0)
    end

    it 'calculates correct block percentage' do
      config = build(:ai_guardrail_config, total_checks: 100, total_blocks: 25)
      expect(config.block_rate).to eq(25.0)
    end

    it 'rounds to one decimal place' do
      config = build(:ai_guardrail_config, total_checks: 3, total_blocks: 1)
      expect(config.block_rate).to eq(33.3)
    end

    it 'returns 100 when all checks are blocked' do
      config = build(:ai_guardrail_config, total_checks: 50, total_blocks: 50)
      expect(config.block_rate).to eq(100.0)
    end

    it 'handles single check correctly' do
      config = build(:ai_guardrail_config, total_checks: 1, total_blocks: 0)
      expect(config.block_rate).to eq(0.0)
    end
  end

  describe '#effective_config' do
    it 'returns a hash with all configuration keys' do
      config = build(:ai_guardrail_config,
                     input_rails: [{ "type" => "token_limit" }],
                     output_rails: [{ "type" => "toxicity" }],
                     retrieval_rails: [{ "type" => "relevance_check" }],
                     max_input_tokens: 50_000,
                     max_output_tokens: 25_000,
                     toxicity_threshold: 0.8,
                     pii_sensitivity: 0.9,
                     block_on_failure: true,
                     configuration: {})

      result = config.effective_config

      expect(result[:input_rails]).to eq([{ "type" => "token_limit" }])
      expect(result[:output_rails]).to eq([{ "type" => "toxicity" }])
      expect(result[:retrieval_rails]).to eq([{ "type" => "relevance_check" }])
      expect(result[:max_input_tokens]).to eq(50_000)
      expect(result[:max_output_tokens]).to eq(25_000)
      expect(result[:toxicity_threshold]).to eq(0.8)
      expect(result[:pii_sensitivity]).to eq(0.9)
      expect(result[:block_on_failure]).to be true
    end

    it 'merges additional configuration keys' do
      config = build(:ai_guardrail_config,
                     configuration: { "custom_setting" => "value", "debug_mode" => true })

      result = config.effective_config

      expect(result[:custom_setting]).to eq("value")
      expect(result[:debug_mode]).to be true
    end

    it 'returns empty arrays for unset rails' do
      config = build(:ai_guardrail_config)
      result = config.effective_config

      expect(result[:input_rails]).to eq([])
      expect(result[:output_rails]).to eq([])
      expect(result[:retrieval_rails]).to eq([])
    end

    it 'symbolizes configuration keys when merging' do
      config = build(:ai_guardrail_config,
                     configuration: { "string_key" => 42 })

      result = config.effective_config
      expect(result[:string_key]).to eq(42)
    end
  end

  describe 'factory traits' do
    it 'creates a valid default config' do
      config = create(:ai_guardrail_config)
      expect(config).to be_valid
      expect(config).to be_persisted
    end

    it 'creates an inactive config with :inactive trait' do
      config = create(:ai_guardrail_config, :inactive)
      expect(config.is_active).to be false
    end

    it 'creates a config with agent using :with_agent trait' do
      config = create(:ai_guardrail_config, :with_agent)
      expect(config.agent).to be_present
    end

    it 'creates a blocking config with :block_on_failure trait' do
      config = create(:ai_guardrail_config, :block_on_failure)
      expect(config.block_on_failure).to be true
    end

    it 'creates a config with high block rate using :high_block_rate trait' do
      config = create(:ai_guardrail_config, :high_block_rate)
      expect(config.total_checks).to eq(1000)
      expect(config.total_blocks).to eq(250)
    end
  end
end

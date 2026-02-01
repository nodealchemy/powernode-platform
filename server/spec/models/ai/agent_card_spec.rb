# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentCard, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent').optional }
  end

  describe 'validations' do
    subject { build(:ai_agent_card) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_inclusion_of(:visibility).in_array(%w[private internal public]) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive deprecated]) }

    context 'name uniqueness within account' do
      let!(:existing_card) { create(:ai_agent_card) }

      it 'validates uniqueness of name within account scope' do
        duplicate_card = build(:ai_agent_card,
                               name: existing_card.name,
                               account: existing_card.account)

        expect(duplicate_card).not_to be_valid
        expect(duplicate_card.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        different_account = create(:account)
        card_with_same_name = build(:ai_agent_card,
                                    name: existing_card.name,
                                    account: different_account)

        expect(card_with_same_name).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:public_card) { create(:ai_agent_card, :public, :active, published_at: Time.current) }
    let!(:internal_card) { create(:ai_agent_card, :internal, :active, published_at: Time.current) }
    let!(:private_card) { create(:ai_agent_card, :active, published_at: Time.current) }
    let!(:inactive_card) { create(:ai_agent_card, :inactive) }
    let!(:deprecated_card) { create(:ai_agent_card, :deprecated) }

    describe '.published' do
      it 'returns only published cards' do
        published = Ai::AgentCard.published
        expect(published).to include(public_card, internal_card, private_card)
        expect(published).not_to include(inactive_card)
      end
    end

    describe '.visible_to_account' do
      it 'returns public cards for any account' do
        other_account = create(:account)
        visible = Ai::AgentCard.visible_to_account(other_account.id)
        expect(visible).to include(public_card)
      end

      it 'returns internal cards for same organization' do
        visible = Ai::AgentCard.visible_to_account(internal_card.account_id)
        expect(visible).to include(internal_card)
      end

      it 'returns private cards only for owner account' do
        visible = Ai::AgentCard.visible_to_account(private_card.account_id)
        expect(visible).to include(private_card)
      end
    end

    describe '.with_capability' do
      let!(:summarize_card) do
        create(:ai_agent_card, :active, published_at: Time.current, capabilities: {
          'skills' => ['summarize']
        })
      end

      it 'returns cards with matching skill' do
        result = Ai::AgentCard.with_capability('summarize')
        expect(result).to include(summarize_card)
      end
    end
  end

  describe '#to_a2a_json' do
    let(:agent_card) { create(:ai_agent_card, :active, :with_multiple_skills, published_at: Time.current) }

    it 'returns A2A-compliant JSON structure' do
      json = agent_card.to_a2a_json

      expect(json[:name]).to eq(agent_card.name)
      expect(json[:description]).to eq(agent_card.description)
      expect(json[:version]).to eq(agent_card.card_version)
      expect(json[:skills]).to be_an(Array)
      expect(json[:skills].length).to eq(3)
    end

    it 'includes authentication info when present' do
      json = agent_card.to_a2a_json
      expect(json[:authentication]).to be_present
    end
  end

  describe '#publish!' do
    let(:agent_card) { create(:ai_agent_card, :inactive) }

    it 'changes status to active and sets published_at' do
      agent_card.publish!
      agent_card.reload
      expect(agent_card.status).to eq('active')
      expect(agent_card.published_at).to be_present
    end
  end

  describe '#deprecate!' do
    let(:agent_card) { create(:ai_agent_card, :active, published_at: Time.current) }

    it 'changes status to deprecated' do
      agent_card.deprecate!
      expect(agent_card.reload.status).to eq('deprecated')
    end
  end

  describe '#skills_list' do
    let(:agent_card) { create(:ai_agent_card, :with_multiple_skills) }

    it 'returns array of skills from capabilities' do
      expect(agent_card.skills_list).to be_an(Array)
      expect(agent_card.skills_list.length).to eq(3)
      expect(agent_card.skills_list.first).to include('id', 'name')
    end
  end

  describe '.find_agents_for_task' do
    let(:account) { create(:account) }

    before do
      create(:ai_agent_card, account: account, status: 'active', capabilities: {
        'skills' => ['summarize']
      })
      create(:ai_agent_card, account: account, status: 'active', capabilities: {
        'skills' => ['translate']
      })
    end

    it 'returns agents matching task description' do
      results = Ai::AgentCard.find_agents_for_task('summarize this document', account_id: account.id)
      expect(results).not_to be_empty
    end
  end
end

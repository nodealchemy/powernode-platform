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
    it { should validate_inclusion_of(:status).in_array(%w[draft published deprecated disabled]) }

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
    let!(:public_card) { create(:ai_agent_card, :public, :published) }
    let!(:internal_card) { create(:ai_agent_card, :internal, :published) }
    let!(:private_card) { create(:ai_agent_card, :published) }
    let!(:draft_card) { create(:ai_agent_card) }
    let!(:deprecated_card) { create(:ai_agent_card, :deprecated) }

    describe '.published' do
      it 'returns only published cards' do
        published = Ai::AgentCard.published
        expect(published).to include(public_card, internal_card, private_card)
        expect(published).not_to include(draft_card, deprecated_card)
      end
    end

    describe '.visible_to' do
      it 'returns public cards for any account' do
        other_account = create(:account)
        visible = Ai::AgentCard.visible_to(other_account)
        expect(visible).to include(public_card)
      end

      it 'returns internal cards for same organization' do
        # Internal visibility would check organization membership
        visible = Ai::AgentCard.visible_to(internal_card.account)
        expect(visible).to include(internal_card)
      end

      it 'returns private cards only for owner account' do
        visible = Ai::AgentCard.visible_to(private_card.account)
        expect(visible).to include(private_card)
      end
    end

    describe '.with_capability' do
      let!(:summarize_card) do
        create(:ai_agent_card, :published, capabilities: {
          'skills' => [{ 'id' => 'summarize', 'name' => 'Summarize' }]
        })
      end

      it 'returns cards with matching skill' do
        result = Ai::AgentCard.with_capability('summarize')
        expect(result).to include(summarize_card)
      end
    end
  end

  describe '#to_a2a_json' do
    let(:agent_card) { create(:ai_agent_card, :published, :with_multiple_skills) }

    it 'returns A2A-compliant JSON structure' do
      json = agent_card.to_a2a_json

      expect(json).to include(
        'name' => agent_card.name,
        'description' => agent_card.description,
        'version' => agent_card.protocol_version
      )
      expect(json['skills']).to be_an(Array)
      expect(json['skills'].length).to eq(3)
    end

    it 'includes authentication info when present' do
      json = agent_card.to_a2a_json
      expect(json['authentication']).to be_present
    end
  end

  describe '#publish!' do
    let(:agent_card) { create(:ai_agent_card, status: 'draft') }

    it 'changes status to published' do
      agent_card.publish!
      expect(agent_card.reload.status).to eq('published')
    end
  end

  describe '#deprecate!' do
    let(:agent_card) { create(:ai_agent_card, :published) }

    it 'changes status to deprecated' do
      agent_card.deprecate!
      expect(agent_card.reload.status).to eq('deprecated')
    end
  end

  describe '#skills' do
    let(:agent_card) { create(:ai_agent_card, :with_multiple_skills) }

    it 'returns array of skills from capabilities' do
      expect(agent_card.skills).to be_an(Array)
      expect(agent_card.skills.length).to eq(3)
      expect(agent_card.skills.first).to include('id', 'name')
    end
  end

  describe '.find_agents_for_task' do
    before do
      create(:ai_agent_card, :published, capabilities: {
        'skills' => [
          { 'id' => 'summarize', 'name' => 'Summarize', 'description' => 'Summarize text documents' }
        ]
      })
      create(:ai_agent_card, :published, capabilities: {
        'skills' => [
          { 'id' => 'translate', 'name' => 'Translate', 'description' => 'Translate between languages' }
        ]
      })
    end

    it 'returns agents matching task description' do
      results = Ai::AgentCard.find_agents_for_task('summarize this document')
      expect(results).not_to be_empty
    end
  end
end

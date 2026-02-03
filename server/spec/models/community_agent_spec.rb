# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommunityAgent, type: :model do
  describe 'associations' do
    it { should belong_to(:owner_account).class_name('Account') }
    it { should belong_to(:agent).class_name('Ai::Agent') }
    it { should belong_to(:agent_card).class_name('Ai::AgentCard').optional }
    it { should belong_to(:published_by).class_name('User').optional }
    it { should belong_to(:verified_by).class_name('User').optional }
    it { should have_many(:ratings).class_name('CommunityAgentRating').dependent(:destroy) }
    it { should have_many(:reports).class_name('CommunityAgentReport').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:community_agent) }

    it { should validate_presence_of(:name) }
    # Note: slug is auto-generated from name, so shoulda-matchers can't easily test its validation
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:visibility) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:protocol_version) }
    it { should validate_inclusion_of(:visibility).in_array(CommunityAgent::VISIBILITIES) }
    it { should validate_inclusion_of(:status).in_array(CommunityAgent::STATUSES) }
  end

  describe 'scopes' do
    let!(:public_agent) { create(:community_agent, :public, :active) }
    let!(:unlisted_agent) { create(:community_agent, :unlisted, :active) }
    let!(:suspended_agent) { create(:community_agent, :public, :suspended) }
    let!(:verified_agent) { create(:community_agent, :public, :active, :verified) }
    let!(:federated_agent) { create(:community_agent, :public, :active, :federated) }

    describe '.public_visible' do
      it 'returns only public active agents' do
        expect(CommunityAgent.public_visible).to include(public_agent)
        expect(CommunityAgent.public_visible).not_to include(unlisted_agent)
      end
    end

    describe '.discoverable' do
      it 'returns public and unlisted active agents' do
        expect(CommunityAgent.discoverable).to include(public_agent, unlisted_agent)
        expect(CommunityAgent.discoverable).not_to include(suspended_agent)
      end
    end

    describe '.verified' do
      it 'returns only verified agents' do
        expect(CommunityAgent.verified).to include(verified_agent)
        expect(CommunityAgent.verified).not_to include(public_agent)
      end
    end

    describe '.federated' do
      it 'returns only federated agents' do
        expect(CommunityAgent.federated).to include(federated_agent)
        expect(CommunityAgent.federated).not_to include(public_agent)
      end
    end
  end

  describe '#activate!' do
    let(:agent) { create(:community_agent, :suspended) }

    it 'changes status to active' do
      agent.activate!
      expect(agent.reload.status).to eq('active')
      expect(agent.published_at).to be_present
    end
  end

  describe '#suspend!' do
    let(:agent) { create(:community_agent, :active) }

    it 'changes status to suspended' do
      agent.suspend!(reason: 'Policy violation')
      expect(agent.reload.status).to eq('suspended')
    end
  end

  describe '#deprecate!' do
    let(:agent) { create(:community_agent, :active) }

    it 'changes status to deprecated' do
      agent.deprecate!
      expect(agent.reload.status).to eq('deprecated')
    end
  end

  describe '#verify!' do
    let(:agent) { create(:community_agent, verified: false) }
    let(:user) { create(:user) }

    it 'marks agent as verified' do
      agent.verify!(user)
      expect(agent.reload.verified).to be true
      expect(agent.verified_at).to be_present
      expect(agent.verified_by).to eq(user)
    end
  end

  describe '#record_task!' do
    let(:agent) { create(:community_agent, task_count: 0) }

    it 'increments task count on success' do
      expect { agent.record_task!(success: true) }.to change { agent.task_count }.by(1)
    end

    it 'increments success count on success' do
      expect { agent.record_task!(success: true) }.to change { agent.success_count }.by(1)
    end
  end

  describe '#refresh_rating!' do
    let(:agent) { create(:community_agent, :with_ratings) }

    it 'updates average rating from ratings' do
      agent.refresh_rating!
      expect(agent.avg_rating).to be > 0
      expect(agent.rating_count).to eq(agent.ratings.count)
    end
  end

  describe '.top_rated' do
    let!(:high_rated) { create(:community_agent, :highly_rated) }
    let!(:low_rated) { create(:community_agent, avg_rating: 2.0, rating_count: 10) }

    it 'returns agents ordered by rating' do
      top = CommunityAgent.top_rated
      expect(top.first).to eq(high_rated)
    end
  end

  describe '.popular' do
    let!(:popular) { create(:community_agent, :popular) }
    let!(:unpopular) { create(:community_agent, task_count: 5) }

    it 'returns agents ordered by task count' do
      top = CommunityAgent.popular
      expect(top.first).to eq(popular)
    end
  end

  describe '#success_rate' do
    let(:agent) { create(:community_agent, task_count: 10, success_count: 8) }

    it 'calculates success rate percentage' do
      expect(agent.success_rate).to eq(80.0)
    end

    it 'returns 0 for agents with no tasks' do
      new_agent = create(:community_agent, task_count: 0)
      expect(new_agent.success_rate).to eq(0)
    end
  end
end

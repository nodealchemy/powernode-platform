# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FederationPartner, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:created_by).class_name('User').optional }
    it { should belong_to(:approved_by).class_name('User').optional }
    it { should have_many(:a2a_tasks).class_name('Ai::A2aTask') }
  end

  describe 'validations' do
    subject { build(:federation_partner) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:organization_id) }
    it { should validate_presence_of(:endpoint_url) }
    it { should validate_presence_of(:status) }
    it { should validate_uniqueness_of(:organization_id) }
    it { should validate_inclusion_of(:status).in_array(FederationPartner::STATUSES) }
    it 'validates trust_level is within 1..5' do
      partner = build(:federation_partner, trust_level: 0)
      expect(partner).not_to be_valid
      partner.trust_level = 6
      expect(partner).not_to be_valid
      partner.trust_level = 3
      expect(partner).to be_valid
    end
    it { should validate_numericality_of(:max_requests_per_hour).is_greater_than(0) }

    context 'endpoint_url format' do
      it 'validates URL format' do
        partner = build(:federation_partner, endpoint_url: 'not-a-url')
        expect(partner).not_to be_valid
      end

      it 'accepts valid HTTPS URL' do
        partner = build(:federation_partner, endpoint_url: 'https://partner.example.com/a2a')
        expect(partner).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:pending_partner) { create(:federation_partner, :pending) }
    let!(:active_partner) { create(:federation_partner, :active) }
    let!(:suspended_partner) { create(:federation_partner, :suspended) }

    describe '.active' do
      it 'returns only active partners' do
        expect(FederationPartner.active).to include(active_partner)
        expect(FederationPartner.active).not_to include(pending_partner, suspended_partner)
      end
    end

    describe '.pending' do
      it 'returns only pending partners' do
        expect(FederationPartner.pending).to include(pending_partner)
      end
    end
  end

  describe '#approve!' do
    let(:partner) { create(:federation_partner, :pending) }
    let(:user) { create(:user) }

    it 'changes status to active' do
      partner.approve!(user)
      expect(partner.reload.status).to eq('active')
      expect(partner.approved_at).to be_present
      expect(partner.approved_by).to eq(user)
    end
  end

  describe '#suspend!' do
    let(:partner) { create(:federation_partner, :active) }

    it 'changes status to suspended' do
      partner.suspend!(reason: 'Policy violation')
      expect(partner.reload.status).to eq('suspended')
    end
  end

  describe '#reactivate!' do
    let(:partner) { create(:federation_partner, :suspended) }

    it 'changes status to active' do
      partner.reactivate!
      expect(partner.reload.status).to eq('active')
    end
  end

  describe '#revoke!' do
    let(:partner) { create(:federation_partner, :active) }

    it 'changes status to revoked' do
      partner.revoke!
      expect(partner.reload.status).to eq('revoked')
    end
  end

  describe '#valid_token?' do
    let(:partner) { create(:federation_partner) }

    it 'returns false for invalid token' do
      expect(partner.valid_token?('wrong_token')).to be false
    end
  end

  describe '#regenerate_token!' do
    let(:partner) { create(:federation_partner) }

    it 'generates new token' do
      old_hash = partner.federation_token_hash
      new_token = partner.regenerate_token!

      expect(new_token).to be_present
      expect(partner.federation_token_hash).not_to eq(old_hash)
    end
  end

  describe '#increase_trust!' do
    let(:partner) { create(:federation_partner, trust_level: 3) }

    it 'increases trust level' do
      partner.increase_trust!
      expect(partner.reload.trust_level).to eq(4)
    end

    it 'does not exceed max level' do
      partner.update!(trust_level: 5)
      partner.increase_trust!
      expect(partner.reload.trust_level).to eq(5)
    end
  end

  describe '#decrease_trust!' do
    let(:partner) { create(:federation_partner, trust_level: 3) }

    it 'decreases trust level' do
      partner.decrease_trust!
      expect(partner.reload.trust_level).to eq(2)
    end

    it 'does not go below min level' do
      partner.update!(trust_level: 1)
      partner.decrease_trust!
      expect(partner.reload.trust_level).to eq(1)
    end
  end

  describe '#rate_limited?' do
    let(:partner) { create(:federation_partner, max_requests_per_hour: 10) }

    it 'returns false when under limit' do
      expect(partner.rate_limited?).to be false
    end

    it 'returns true when at limit' do
      10.times { partner.increment_request_count! }
      expect(partner.rate_limited?).to be true
    end
  end

  # IMP-e0cb1dbbff7e — sync_agent had NEVER executed: it assigned two columns
  # that did not exist and never set two required associations, so every call
  # raised before writing. Operator decision 2026-08-06 was to complete the
  # data model rather than retire the path. These cover both halves — that it
  # runs at all, and that a partner cannot inherit local trust by re-pointing
  # an agent it already had verified.
  describe '#sync_agent' do
    let(:partner) { create(:federation_partner) }
    let(:admin)   { create(:user, account: partner.account) }
    let(:payload) do
      { 'id' => 'remote-1', 'name' => 'Summarizer',
        'description' => 'summarizes things',
        'endpoint_url' => 'https://old.example/agent',
        'capabilities' => { 'summarize' => true } }
    end

    def sync(extra = {})
      partner.send(:sync_agent, payload.merge(extra))
    end

    it 'creates a federated agent with no local Ai::Agent, owned by this account' do
      result = sync
      expect(result[:success]).to be true

      agent = CommunityAgent.find(result[:community_agent_id])
      expect(agent.federated).to be true
      expect(agent.agent_id).to be_nil
      expect(agent.owner_account_id).to eq(partner.account_id)
      expect(agent.federation_partner_id).to eq(partner.id)
      expect(agent.federation_metadata['source_agent_id']).to eq('remote-1')
    end

    it 'still requires a local agent for a NON-federated row' do
      local = CommunityAgent.new(owner_account: partner.account, name: 'Local',
                                 slug: 'local-one', description: 'local',
                                 visibility: 'public', status: 'pending',
                                 protocol_version: '0.3', federated: false)
      expect(local).not_to be_valid
      expect(local.errors[:agent].join).to match(/must exist/)
    end

    it 'admits a SECOND federated agent — a nil agent_id is not "already registered"' do
      expect(sync[:success]).to be true
      second = partner.send(:sync_agent,
                            payload.merge('id' => 'remote-2', 'name' => 'Translator'))
      expect(second[:success]).to be true
      expect(CommunityAgent.federated.count).to eq(2)
    end

    it 'clears local attestations when a re-sync repoints the endpoint' do
      agent = CommunityAgent.find(sync[:community_agent_id])
      agent.verify!(admin)
      agent.update_column(:reputation_score, 4.5)

      result = sync('endpoint_url' => 'https://elsewhere.example/agent')
      expect(result[:attestations_reset]).to be true

      agent.reload
      expect(agent.verified).to be false
      expect(agent.verified_at).to be_nil
      expect(agent.verified_by_id).to be_nil
      expect(agent.reputation_score.to_f).to eq(0.0)
    end

    it 'clears them when the capabilities change too' do
      agent = CommunityAgent.find(sync[:community_agent_id])
      agent.verify!(admin)

      sync('capabilities' => { 'exfiltrate' => true })

      expect(agent.reload.verified).to be false
    end

    it 'keeps attestations when only the description changes' do
      # The counterweight: routine re-syncs must not erode the catalog, or
      # operators would stop verifying anything.
      agent = CommunityAgent.find(sync[:community_agent_id])
      agent.verify!(admin)
      agent.update_column(:reputation_score, 4.5)

      result = sync('description' => 'better copy, same agent')
      expect(result[:attestations_reset]).to be false

      agent.reload
      expect(agent.verified).to be true
      expect(agent.reputation_score.to_f).to eq(4.5)
    end
  end
end

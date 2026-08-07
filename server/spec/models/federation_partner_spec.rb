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

  describe "cross-plane MCP invocation" do
    describe "#outbound_token" do
      it "round-trips through encrypted-at-rest storage" do
        partner = create(:federation_partner, :active)
        partner.outbound_token = "shared-secret-123"
        partner.save!

        expect(partner.outbound_token_encrypted).to be_present
        expect(partner.outbound_token_encrypted).not_to include("shared-secret-123")
        expect(partner.reload.outbound_token).to eq("shared-secret-123")
      end

      it "clears to nil when set blank" do
        partner = create(:federation_partner, :active)
        partner.update!(outbound_token: "x")
        partner.update!(outbound_token: "")
        expect(partner.reload.outbound_token).to be_nil
      end
    end

    describe ".for_inbound" do
      let!(:partner) { create(:federation_partner, :active) } # token "test_token"

      it "resolves an active partner presenting a valid token" do
        expect(described_class.for_inbound(organization_id: partner.organization_id, token: "test_token")).to eq(partner)
      end

      it "rejects a bad token" do
        expect(described_class.for_inbound(organization_id: partner.organization_id, token: "wrong")).to be_nil
      end

      it "rejects an unknown organization" do
        expect(described_class.for_inbound(organization_id: "nope", token: "test_token")).to be_nil
      end

      it "rejects a non-active partner" do
        suspended = create(:federation_partner, :suspended)
        expect(described_class.for_inbound(organization_id: suspended.organization_id, token: "test_token")).to be_nil
      end

      it "rejects a rate-limited partner" do
        allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(true)
        expect(described_class.for_inbound(organization_id: partner.organization_id, token: "test_token")).to be_nil
      end

      it "rejects blank inputs" do
        expect(described_class.for_inbound(organization_id: nil, token: "x")).to be_nil
        expect(described_class.for_inbound(organization_id: "x", token: nil)).to be_nil
      end
    end

    describe "#invoke_remote_tool" do
      let(:partner) do
        p = create(:federation_partner, :active, endpoint_url: "https://peer.example.com")
        p.outbound_token = "outbound-secret"
        p.update!(tls_config: { "presented_organization_id" => "my-org" })
        p
      end

      # Endpoint resolves to a public address on the happy paths (SSRF guard).
      before { allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ]) }

      it "refuses to call an endpoint that resolves to a private/loopback address (SSRF guard)" do
        allow(Resolv).to receive(:getaddresses).and_return([ "127.0.0.1" ])
        result = partner.invoke_remote_tool(tool: "x")
        expect(result[:success]).to be false
        expect(result[:error]).to match(/non-public endpoint host/)
        expect(a_request(:post, %r{peer.example.com})).not_to have_been_made
      end

      it "POSTs a JSON-RPC tools/call with the outbound bearer + self identity and returns the result" do
        stub_request(:post, "https://peer.example.com/api/v1/mcp/message")
          .to_return(status: 200, body: { jsonrpc: "2.0", id: "1", result: { "templates" => [] } }.to_json)

        result = partner.invoke_remote_tool(tool: "system_list_templates", arguments: { "q" => "x" })

        expect(result[:success]).to be true
        expect(result[:result]).to eq({ "templates" => [] })
        expect(
          a_request(:post, "https://peer.example.com/api/v1/mcp/message").with do |req|
            body = JSON.parse(req.body)
            req.headers["Authorization"] == "Bearer outbound-secret" &&
              req.headers["X-Federation-Organization"] == "my-org" &&
              body["method"] == "tools/call" &&
              body.dig("params", "name") == "system_list_templates"
          end
        ).to have_been_made
      end

      it "surfaces a remote JSON-RPC error" do
        stub_request(:post, "https://peer.example.com/api/v1/mcp/message")
          .to_return(status: 200, body: { jsonrpc: "2.0", id: "1", error: { code: -32000, message: "nope" } }.to_json)

        result = partner.invoke_remote_tool(tool: "x")
        expect(result[:success]).to be false
        expect(result[:error]).to eq("nope")
      end

      it "refuses when the partner is not active" do
        partner.update!(status: "suspended")
        expect(partner.invoke_remote_tool(tool: "x")[:success]).to be false
      end

      it "refuses when no outbound token is configured" do
        partner.update!(outbound_token_encrypted: nil)
        expect(partner.invoke_remote_tool(tool: "x")[:error]).to match(/outbound federation token/)
      end

      it "refuses when no presented_organization_id is configured" do
        partner.update!(tls_config: {})
        expect(partner.invoke_remote_tool(tool: "x")[:error]).to match(/presented_organization_id/)
      end
    end

    describe "allowed_capabilities validation" do
      it "rejects over-broad wildcard grants" do
        [ "*", "**", "platform.*", "platform.**" ].each do |cap|
          partner = build(:federation_partner, :active, allowed_capabilities: [ cap ])
          expect(partner).not_to be_valid, "expected #{cap.inspect} to be rejected"
          expect(partner.errors[:allowed_capabilities].join).to match(/over-broad/)
        end
      end

      it "allows specific tool-prefix patterns and discovery tags" do
        partner = build(:federation_partner, :active,
                        allowed_capabilities: [ "platform.system_list_*", "platform.health", "agent-discovery" ])
        expect(partner).to be_valid
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Growth analytics (G2): CrossPostService fans one piece of content out to N
# connected providers' publish (side-effecting) endpoints. It dispatches
# EVERY target through Ai::Tools::DataSourceTool#execute — the SAME choke
# point (guarded_fetch/propose_write) x-com's captures_published_post write
# already goes through (see published_post_recorder_spec.rb and
# data_source_tool_spec.rb's "write endpoint gate" block) — so an agent
# lacking ai.data_sources.manage must get a proposal per target, NEVER a
# silent live write.
RSpec.describe Ai::Growth::CrossPostService, type: :service do
  let(:account) { create(:account) }

  let!(:provider_a) { create(:ai_data_source, account: account, slug: "provider-a", name: "Provider A") }
  let!(:provider_a_endpoint) do
    create(:ai_data_source_endpoint, data_source: provider_a, slug: "create-post",
           name: "Create post", http_method: "POST", cache_ttl_seconds: 0,
           metadata: { "side_effecting" => true })
  end

  let!(:provider_b) { create(:ai_data_source, account: account, slug: "provider-b", name: "Provider B") }
  let!(:provider_b_endpoint) do
    create(:ai_data_source_endpoint, data_source: provider_b, slug: "create-status",
           name: "Create status", http_method: "POST", cache_ttl_seconds: 0,
           metadata: { "side_effecting" => true })
  end

  let(:targets) do
    [ { data_source_id: "provider-a", params: {} }, { data_source_id: "provider-b", params: {} } ]
  end

  def fake_envelope
    { success: true, data: [ { "id" => "1" } ], provenance: {}, status: "success",
      duration_ms: 1, bytes: 0, error: nil }
  end

  # ---------------------------------------------------------------------
  # No agent context (a direct/human-authorized call — mirrors BaseTool's
  # own "no agent context => already authorized upstream" convention):
  # dispatches every target directly.
  # ---------------------------------------------------------------------
  context "with no agent context" do
    let(:service) { described_class.new(account: account) }

    it "dispatches every target directly through QueryService" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = service.publish(content: "hello everyone", targets: targets)

      expect(Ai::DataSources::QueryService).to have_received(:new).twice
      expect(result[:target_count]).to eq(2)
      expect(result[:published_count]).to eq(2)
      expect(result[:proposed_count]).to eq(0)
      expect(result[:results]).to all(include(published: true, requires_approval: false))
    end
  end

  # ---------------------------------------------------------------------
  # Agent context: the write-endpoint gate applies per target (mirrors
  # data_source_tool_spec.rb's "write endpoint gate" describe block).
  # ---------------------------------------------------------------------
  context "with an agent lacking ai.data_sources.manage" do
    let!(:unprivileged_user) { create(:user, account: account, permissions: [ "ai.data_sources.query" ]) }
    let(:agent) { create(:ai_agent, account: account, creator: unprivileged_user) }
    let(:service) { described_class.new(account: account, agent: agent, user: unprivileged_user) }

    it "never dispatches QueryService and files a proposal per target instead" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      result = nil
      expect do
        result = service.publish(content: "hello everyone", targets: targets)
      end.to change(Ai::AgentProposal, :count).by(2)

      expect(result[:published_count]).to eq(0)
      expect(result[:proposed_count]).to eq(2)
      expect(result[:results]).to all(include(requires_approval: true, published: false))
      expect(result[:results].map { |r| r[:proposal_id] }).to all(be_present)
    end
  end

  context "with an agent holding ai.data_sources.manage" do
    let!(:privileged_user) { create(:user, account: account, permissions: [ "ai.data_sources.query", "ai.data_sources.manage" ]) }
    let(:agent) { create(:ai_agent, account: account, creator: privileged_user) }
    let(:service) { described_class.new(account: account, agent: agent, user: privileged_user) }

    it "dispatches every target directly, with no proposal" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = nil
      expect { result = service.publish(content: "hello everyone", targets: targets) }
        .not_to change(Ai::AgentProposal, :count)

      expect(result[:published_count]).to eq(2)
      expect(result[:proposed_count]).to eq(0)
    end
  end

  # ---------------------------------------------------------------------
  # validation / edge cases
  # ---------------------------------------------------------------------
  describe "validation" do
    let(:service) { described_class.new(account: account) }

    it "raises when content is blank" do
      expect { service.publish(content: "", targets: targets) }.to raise_error(ArgumentError, /content/)
    end

    it "raises when targets is empty" do
      expect { service.publish(content: "hi", targets: []) }.to raise_error(ArgumentError, /targets/)
    end

    it "raises when the target count exceeds the configured max" do
      account.update!(settings: { "growth_analytics" => { "cross_post_max_targets" => 1 } })

      expect { service.publish(content: "hi", targets: targets) }.to raise_error(ArgumentError, /too many targets/)
    end

    it "reports a per-target failure for an unknown data source, without aborting the batch" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = service.publish(content: "hi", targets: [ { data_source_id: "ghost" }, targets.first ])

      expect(result[:failed_count]).to eq(1)
      expect(result[:published_count]).to eq(1)
      expect(result[:results].first).to include(published: false, error: a_string_matching(/not found/))
    end

    it "reports a per-target failure when the source has no side-effecting publish endpoint" do
      read_only_source = create(:ai_data_source, account: account, slug: "read-only")
      create(:ai_data_source_endpoint, data_source: read_only_source, slug: "list", http_method: "GET")

      result = service.publish(content: "hi", targets: [ { data_source_id: "read-only" } ])

      expect(result[:results].first).to include(published: false, error: a_string_matching(/no publish/))
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Specs for the MCP DataSourceTool — the data-source capability exposed over MCP
# with per-action authorization:
#   * read actions   require ai.data_sources.read
#   * data_source_query requires ai.data_sources.query
#   * mutations (create/update/delete) require the matching grant (or .manage),
#     and FALL BACK TO A PROPOSAL (no mutation) when the acting agent's account
#     lacks the permission.
#
# Authorization note: DataSourceTool#permission? FAILS OPEN when there is no
# agent context (direct API/worker invocation is already gated upstream). So the
# read/query/health/etc. happy paths instantiate the tool WITHOUT an agent, while
# the permission-gate and proposal-fallback specs pass an agent so the account's
# permission graph is actually consulted.
RSpec.describe Ai::Tools::DataSourceTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # No-agent tool: permission? fails open, exercising the action bodies directly.
  let(:tool) { described_class.new(account: account, user: user) }

  let!(:data_source) do
    create(:ai_data_source, account: account, slug: "open-meteo", source_type: "open_meteo")
  end
  let!(:endpoint) do
    create(:ai_data_source_endpoint, data_source: data_source, slug: "forecast")
  end

  describe ".definition" do
    it "returns a valid multi-action tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("data_source_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :data_source_id, :endpoint_id, :params)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".action_definitions" do
    it "exposes all sixteen data-source actions" do
      keys = described_class.action_definitions.keys
      expect(keys).to contain_exactly(
        "data_source_list", "data_source_get", "data_source_describe",
        "data_source_query", "data_source_health", "data_source_validate_config",
        "data_source_create", "data_source_update", "data_source_delete",
        "data_source_discover", "data_source_provenance", "data_source_impact",
        "data_source_schema_history", "data_source_quality",
        "data_source_contract", "data_source_introspect"
      )
    end
  end

  describe ".permitted?" do
    it "requires the read permission for tool visibility" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.data_sources.read")
    end
  end

  # ------------------------------------------------------------------------
  # read actions
  # ------------------------------------------------------------------------

  describe "#execute data_source_list" do
    it "lists data sources for the account with health + credential counts" do
      result = tool.execute(params: { action: "data_source_list" })

      expect(result[:success]).to be true
      expect(result[:data][:count]).to eq(1)
      item = result[:data][:items].first
      expect(item).to include(:id, :name, :slug, :source_type, :health_status, :credential_count)
      expect(item[:slug]).to eq("open-meteo")
    end

    it "filters by source_type" do
      create(:ai_data_source, account: account, source_type: "fred")

      result = tool.execute(params: { action: "data_source_list", source_type: "fred" })

      expect(result[:data][:count]).to eq(1)
      expect(result[:data][:items].first[:source_type]).to eq("fred")
    end

    it "filters by is_active" do
      create(:ai_data_source, :inactive, account: account)

      result = tool.execute(params: { action: "data_source_list", is_active: true })

      expect(result[:data][:count]).to eq(1)
      expect(result[:data][:items].first[:is_active]).to be true
    end

    it "does not return data sources from other accounts" do
      create(:ai_data_source, account: create(:account))

      result = tool.execute(params: { action: "data_source_list" })

      expect(result[:data][:count]).to eq(1)
    end
  end

  describe "#execute data_source_get" do
    it "returns a single data source with detail fields" do
      result = tool.execute(params: { action: "data_source_get", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      ds = result[:data][:data_source]
      expect(ds[:slug]).to eq("open-meteo")
      expect(ds).to include(:api_base_url, :configuration, :rate_limits, :quota, :endpoint_count)
      expect(ds[:endpoint_count]).to eq(1)
    end

    it "resolves by UUID as well as slug" do
      result = tool.execute(params: { action: "data_source_get", data_source_id: data_source.id })

      expect(result[:success]).to be true
      expect(result[:data][:data_source][:id]).to eq(data_source.id)
    end

    it "returns an error when the source is missing" do
      result = tool.execute(params: { action: "data_source_get", data_source_id: "nope" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "returns an error when data_source_id is blank" do
      result = tool.execute(params: { action: "data_source_get", data_source_id: "" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/required/i)
    end
  end

  describe "#execute data_source_describe" do
    it "describes a data source's endpoints" do
      result = tool.execute(params: { action: "data_source_describe", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      expect(result[:data][:count]).to eq(1)
      ep = result[:data][:endpoints].first
      expect(ep).to include(:id, :name, :slug, :http_method, :path_template, :response_format)
      expect(result[:data][:data_source]).to include(:protocol, :auth_scheme)
    end

    it "can limit to a single endpoint" do
      create(:ai_data_source_endpoint, data_source: data_source, slug: "history")

      result = tool.execute(params: {
        action: "data_source_describe", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:data][:count]).to eq(1)
      expect(result[:data][:endpoints].first[:slug]).to eq("forecast")
    end
  end

  describe "#execute data_source_health" do
    it "reports quota, cache metrics, and circuit-breaker state" do
      result = tool.execute(params: { action: "data_source_health", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      expect(result[:data]).to include(:quota_summary, :cache_metrics, :circuit_breaker)
      expect(result[:data][:data_source]).to include(:health_status)
    end
  end

  describe "#execute data_source_validate_config" do
    it "reports a valid config for a public https source with a known scheme" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)

      result = tool.execute(params: { action: "data_source_validate_config", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      expect(result[:data][:valid]).to be true
      expect(result[:data][:errors]).to be_empty
      # No endpoints would warn, but this source has one.
      expect(result[:data][:warnings]).not_to include("No endpoints configured")
    end

    it "flags an SSRF-blocked base URL as invalid" do
      blocked = create(:ai_data_source, account: account, slug: "loopback",
                       api_base_url: "http://127.0.0.1/internal")
      create(:ai_data_source_endpoint, data_source: blocked)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError, "loopback blocked")

      result = tool.execute(params: { action: "data_source_validate_config", data_source_id: "loopback" })

      expect(result[:data][:valid]).to be false
      expect(result[:data][:errors].join).to match(/egress policy/i)
    end

    it "flags an unknown auth scheme as invalid" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      bad = create(:ai_data_source, account: account, slug: "weird-auth", auth_scheme: "totally_made_up")
      create(:ai_data_source_endpoint, data_source: bad)

      result = tool.execute(params: { action: "data_source_validate_config", data_source_id: "weird-auth" })

      expect(result[:data][:valid]).to be false
      expect(result[:data][:errors].join).to match(/auth_scheme/i)
    end

    it "warns when an active auth-requiring source has no usable credential" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      needs_auth = create(:ai_data_source, :requires_auth, account: account, slug: "needs-key")
      create(:ai_data_source_endpoint, data_source: needs_auth)

      result = tool.execute(params: { action: "data_source_validate_config", data_source_id: "needs-key" })

      expect(result[:data][:warnings]).to include(a_string_matching(/no usable credential/i))
    end
  end

  # ------------------------------------------------------------------------
  # query action — delegates to QueryService and returns the FetchEnvelope
  # ------------------------------------------------------------------------

  describe "#execute data_source_query" do
    let(:envelope) do
      {
        success: true,
        data: [{ "city" => "NYC", "temp" => "72" }],
        provenance: { slug: "open-meteo", endpoint_id: endpoint.id, from_cache: false },
        status: "success",
        duration_ms: 5,
        bytes: 42,
        error: nil
      }
    end

    it "runs QueryService and returns its FetchEnvelope verbatim" do
      fake = instance_double(Ai::DataSources::QueryService, call: envelope)
      expect(Ai::DataSources::QueryService).to receive(:new).with(
        hash_including(data_source: data_source, endpoint: endpoint, user: user)
      ).and_return(fake)

      result = tool.execute(params: {
        action: "data_source_query", data_source_id: "open-meteo",
        endpoint_id: "forecast", params: { "latitude" => 40.7 }
      })

      expect(result).to eq(envelope)
      expect(result[:success]).to be true
      expect(result[:data]).to eq([{ "city" => "NYC", "temp" => "72" }])
      expect(result[:provenance]).to include(:slug, :endpoint_id)
    end

    it "requires both data_source_id and endpoint_id" do
      result = tool.execute(params: { action: "data_source_query", data_source_id: "open-meteo" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/endpoint_id is required/i)
    end

    it "surfaces a not-found error for an unknown endpoint" do
      result = tool.execute(params: {
        action: "data_source_query", data_source_id: "open-meteo", endpoint_id: "ghost"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end
  end

  # ------------------------------------------------------------------------
  # query permission gate (agent context => permission? is consulted)
  # ------------------------------------------------------------------------

  describe "query permission gate" do
    # Isolated account whose ONLY users have no permissions, so permission? truly
    # reflects the absence of ai.data_sources.query. (The default member role —
    # which the agent factory's creator would otherwise get — already carries
    # ai.data_sources.query, which would mask a real gate.)
    let(:locked_account) { create(:account) }
    let(:no_perm_user) { create(:user, account: locked_account, permissions: []) }
    let(:locked_agent) { create(:ai_agent, account: locked_account, creator: no_perm_user) }
    let!(:locked_source) { create(:ai_data_source, account: locked_account, slug: "locked-src") }
    let!(:locked_endpoint) { create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep") }

    it "denies data_source_query when no user in the account holds ai.data_sources.query" do
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      result = agent_tool.execute(params: {
        action: "data_source_query", data_source_id: "locked-src", endpoint_id: "ep"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.query/)
    end

    it "allows data_source_query when a user in the account holds the query grant" do
      create(:user, account: locked_account, permissions: ["ai.data_sources.query"])
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      fake = instance_double(Ai::DataSources::QueryService,
                             call: { success: true, data: [], provenance: {}, status: "success",
                                     duration_ms: 1, bytes: 0, error: nil })
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = agent_tool.execute(params: {
        action: "data_source_query", data_source_id: "locked-src", endpoint_id: "ep"
      })

      expect(result[:success]).to be true
    end
  end

  # ------------------------------------------------------------------------
  # mutations — happy path (authorized) vs proposal fallback (unauthorized)
  # ------------------------------------------------------------------------

  describe "#execute mutations when authorized (no agent => fail-open)" do
    it "creates a data source" do
      result = tool.execute(params: {
        action: "data_source_create", name: "FRED", source_type: "fred",
        api_base_url: "https://api.stlouisfed.org"
      })

      expect(result[:success]).to be true
      expect(result[:data][:data_source][:name]).to eq("FRED")
      expect(Ai::DataSource.where(account: account, name: "FRED")).to exist
    end

    it "returns a validation error on create with an invalid source_type" do
      result = tool.execute(params: {
        action: "data_source_create", name: "Bad", source_type: "not_a_real_type"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end

    it "updates a data source" do
      result = tool.execute(params: {
        action: "data_source_update", data_source_id: "open-meteo", name: "Open-Meteo v2"
      })

      expect(result[:success]).to be true
      expect(data_source.reload.name).to eq("Open-Meteo v2")
    end

    it "deletes a data source" do
      result = tool.execute(params: { action: "data_source_delete", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      expect(result[:data][:message]).to match(/deleted/i)
      expect(Ai::DataSource.exists?(data_source.id)).to be false
    end
  end

  describe "mutation authorized via ai.data_sources.manage (agent context)" do
    let(:agent) { create(:ai_agent, account: account) }

    before { create(:user, account: account, permissions: ["ai.data_sources.manage"]) }

    it "performs the create instead of filing a proposal" do
      agent_tool = described_class.new(account: account, agent: agent, user: user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_create", name: "Managed", source_type: "custom"
        })
      end.to change(Ai::DataSource, :count).by(1)
        .and change(Ai::AgentProposal, :count).by(0)

      expect(result[:success]).to be true
      expect(result).not_to include(:requires_approval)
      expect(result[:data][:data_source][:name]).to eq("Managed")
    end
  end

  describe "mutation PROPOSAL fallback when the account lacks the grant" do
    let(:agent) { create(:ai_agent, account: account) }

    before do
      # A user exists in the account but WITHOUT any data-source mutation grant,
      # so DataSourceTool#permission? evaluates to false and the tool proposes.
      create(:user, account: account, permissions: ["ai.data_sources.read"])
    end

    it "files a proposal for create and does NOT create the data source" do
      agent_tool = described_class.new(account: account, agent: agent, user: user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_create", name: "Proposed Source", source_type: "custom"
        })
      end.to change(Ai::AgentProposal, :count).by(1)
        .and change(Ai::DataSource, :count).by(0)

      expect(result[:success]).to be true
      expect(result[:requires_approval]).to be true
      expect(result[:proposal_id]).to be_present
      expect(result[:status]).to eq("pending_review")
      expect(result[:message]).to match(/ai\.data_sources\.create required/)
      expect(result[:proposed_changes]).to include(action: "create")

      proposal = Ai::AgentProposal.order(:created_at).last
      expect(proposal.proposal_type).to eq("configuration")
      expect(proposal.agent).to eq(agent)
      expect(proposal.account).to eq(account)
    end

    it "files a proposal for update and does NOT mutate the data source" do
      agent_tool = described_class.new(account: account, agent: agent, user: user)
      original_name = data_source.name

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_update", data_source_id: "open-meteo", name: "Should Not Apply"
        })
      end.to change(Ai::AgentProposal, :count).by(1)

      expect(result[:requires_approval]).to be true
      expect(result[:proposed_changes]).to include(action: "update", data_source_id: "open-meteo")
      expect(data_source.reload.name).to eq(original_name)
    end

    it "files a proposal for delete and does NOT destroy the data source" do
      agent_tool = described_class.new(account: account, agent: agent, user: user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_delete", data_source_id: "open-meteo"
        })
      end.to change(Ai::AgentProposal, :count).by(1)

      expect(result[:requires_approval]).to be true
      expect(result[:proposed_changes]).to include(action: "delete", data_source_id: "open-meteo")
      expect(Ai::DataSource.exists?(data_source.id)).to be true
    end
  end

  # ------------------------------------------------------------------------
  # data_source_discover — semantic discovery (Phase 2a)
  # ------------------------------------------------------------------------

  describe "#execute data_source_discover" do
    # A deterministic ranking the stubbed service returns: data_source first
    # (higher blended score), then a second source.
    let!(:other_source) do
      create(:ai_data_source, account: account, slug: "fred", source_type: "fred", name: "FRED")
    end

    let(:ranking) do
      [
        {
          data_source: data_source,
          score: 0.88,
          signals: { semantic: 0.9, effectiveness: 0.8, health: 1.0, recency: 0.6 }
        },
        {
          data_source: other_source,
          score: 0.41,
          signals: { semantic: 0.4, effectiveness: 0.5, health: 0.0, recency: 0.5 }
        }
      ]
    end

    def stub_discovery(result)
      fake = instance_double(Ai::DataSources::SemanticDiscoveryService, discover: result)
      allow(Ai::DataSources::SemanticDiscoveryService).to receive(:new).and_return(fake)
      fake
    end

    it "returns the ranked sources with score, signals, and effectiveness_score" do
      stub_discovery(ranking)

      result = tool.execute(params: { action: "data_source_discover", query: "weather forecast" })

      expect(result[:success]).to be true
      expect(result[:data][:query]).to eq("weather forecast")
      expect(result[:data][:count]).to eq(2)

      first = result[:data][:results].first
      expect(first).to include(:id, :slug, :source_type, :score, :signals, :effectiveness_score)
      expect(first[:slug]).to eq("open-meteo")
      expect(first[:score]).to eq(0.88)
      expect(first[:signals]).to eq(semantic: 0.9, effectiveness: 0.8, health: 1.0, recency: 0.6)
    end

    it "passes the query, agent, clamped limit, and rerank flag into the service" do
      fake = instance_double(Ai::DataSources::SemanticDiscoveryService, discover: [])
      expect(Ai::DataSources::SemanticDiscoveryService).to receive(:new).with(account).and_return(fake)
      expect(fake).to receive(:discover).with(
        query: "equities",
        agent: nil,        # no-agent tool
        limit: 50,         # 999 clamped to the 50 max
        rerank: true       # "true" cast to boolean
      ).and_return([])

      result = tool.execute(params: {
        action: "data_source_discover", query: "equities", limit: 999, rerank: "true"
      })

      expect(result[:success]).to be true
      expect(result[:data][:count]).to eq(0)
    end

    it "errors when query is blank" do
      result = tool.execute(params: { action: "data_source_discover", query: "" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/query is required/i)
    end

    it "denies discover (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      expect(Ai::DataSources::SemanticDiscoveryService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: { action: "data_source_discover", query: "weather" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_provenance — audit a recorded fetch (Phase 2a)
  #
  # The ai_data_source_queries row IS the per-request audit log, written
  # ALREADY-REDACTED by QueryService. The tool surfaces only those redacted
  # provenance columns — never raw request material.
  # ------------------------------------------------------------------------

  describe "#execute data_source_provenance" do
    # A recorded query whose redacted_url is pre-redacted, with a raw secret
    # deliberately stashed in columns the provenance serializer does NOT read
    # (principal/purpose/params_hash) to prove nothing un-redacted leaks.
    let(:raw_secret) { "sk-live-SUPERSECRET-abc123" }
    let!(:recorded_query) do
      Ai::DataSourceQuery.create!(
        account_id: account.id,
        ai_data_source_id: data_source.id,
        ai_data_source_endpoint_id: endpoint.id,
        correlation_id: "corr-xyz",
        status: "success",
        http_status: 200,
        duration_ms: 12,
        bytes_in: 256,
        rows_returned: 3,
        response_sha256: "a" * 64,
        redacted_url: "https://api.open-meteo.com/v1/forecast?apikey=%5BREDACTED%5D",
        schema_valid: true,
        cached: false,
        served_stage: "fresh",
        redaction_applied: true,
        estimated_cost_usd: 0.0,
        actual_cost_usd: 0.0,
        # Un-exposed columns carrying the raw secret — must never surface.
        principal: raw_secret,
        purpose: "fetch with #{raw_secret}",
        params_hash: raw_secret,
        metadata: { "audit_chain" => "chain-anchor-1", "anomalies" => [] }
      )
    end

    it "returns the redacted provenance record by query_id" do
      result = tool.execute(params: {
        action: "data_source_provenance", query_id: recorded_query.id
      })

      expect(result[:success]).to be true
      prov = result[:data][:provenance]
      expect(prov[:query_id]).to eq(recorded_query.id)
      expect(prov[:correlation_id]).to eq("corr-xyz")
      expect(prov[:source]).to include(id: data_source.id, slug: "open-meteo")
      expect(prov[:endpoint]).to include(id: endpoint.id, slug: "forecast")
      expect(prov[:status]).to eq("success")
      expect(prov[:response_sha256]).to eq("a" * 64)
      expect(prov[:redacted_url]).to eq("https://api.open-meteo.com/v1/forecast?apikey=%5BREDACTED%5D")
      expect(prov[:schema_valid]).to be true
      expect(prov[:served_stage]).to eq("fresh")
      expect(prov[:redaction_applied]).to be true
      expect(prov[:audit_chain]).to eq("chain-anchor-1")
    end

    it "exposes ONLY redacted columns and never leaks the raw secret" do
      result = tool.execute(params: {
        action: "data_source_provenance", query_id: recorded_query.id
      })

      prov = result[:data][:provenance]
      # The serialized provenance, in any form, must not contain raw material.
      expect(prov.to_s).not_to include(raw_secret)
      expect(prov.to_json).not_to include(raw_secret)
      # The un-exposed columns are absent from the provenance contract entirely.
      expect(prov).not_to have_key(:principal)
      expect(prov).not_to have_key(:purpose)
      expect(prov).not_to have_key(:params_hash)
      # The only URL surfaced is the redacted one.
      expect(prov[:redacted_url]).to include("%5BREDACTED%5D")
    end

    it "resolves by correlation_id when no query_id is given" do
      result = tool.execute(params: {
        action: "data_source_provenance", correlation_id: "corr-xyz"
      })

      expect(result[:success]).to be true
      expect(result[:data][:provenance][:query_id]).to eq(recorded_query.id)
    end

    it "falls back to the latest query for a data source" do
      result = tool.execute(params: {
        action: "data_source_provenance", data_source_id: "open-meteo"
      })

      expect(result[:success]).to be true
      expect(result[:data][:provenance][:query_id]).to eq(recorded_query.id)
    end

    it "does not surface a recorded query from another account" do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account, slug: "other-src")
      foreign_query = Ai::DataSourceQuery.create!(
        account_id: other_account.id, ai_data_source_id: other_source.id,
        status: "success", correlation_id: "foreign-corr"
      )

      result = tool.execute(params: {
        action: "data_source_provenance", query_id: foreign_query.id
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/no matching data source query/i)
    end

    it "denies provenance (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_provenance", correlation_id: "corr-xyz"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_impact — usage + trust summary (Phase 2a)
  # ------------------------------------------------------------------------

  describe "#execute data_source_impact" do
    let(:agent_a) { create(:ai_agent, account: account) }
    let(:agent_b) { create(:ai_agent, account: account) }

    before do
      # Two distinct requesting agents across a mix of outcomes.
      Ai::DataSourceQuery.create!(account_id: account.id, ai_data_source_id: data_source.id,
                                  status: "success", requesting_agent_id: agent_a.id, cached: false)
      Ai::DataSourceQuery.create!(account_id: account.id, ai_data_source_id: data_source.id,
                                  status: "success", requesting_agent_id: agent_b.id, cached: true)
      Ai::DataSourceQuery.create!(account_id: account.id, ai_data_source_id: data_source.id,
                                  status: "error", requesting_agent_id: agent_a.id, cached: false)
      data_source.update_columns(effectiveness_score: 0.73, last_used_at: Time.current, health_status: "healthy")
    end

    it "returns the usage summary shape" do
      result = tool.execute(params: { action: "data_source_impact", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:data_source]).to include(id: data_source.id, slug: "open-meteo")
      expect(data[:distinct_requesting_agents]).to eq(2)
      expect(data[:query_counts]).to eq(total: 3, successful: 2, failed: 1, cached: 1)
      expect(data[:effectiveness_score]).to eq(0.73)
      expect(data[:health_status]).to eq("healthy")
      expect(data[:last_used_at]).to be_present
      expect(data[:trust_signals]).to include(
        :effectiveness_score, :usage_count, :usage_success_rate, :healthy
      )
    end

    it "errors when data_source_id is blank" do
      result = tool.execute(params: { action: "data_source_impact", data_source_id: "" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/required/i)
    end

    it "denies impact (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-impact")

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_impact", data_source_id: "locked-impact"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_schema_history — recorded schema versions (Phase 2b, read)
  # ------------------------------------------------------------------------

  describe "#execute data_source_schema_history" do
    before do
      Ai::DataSources::SchemaDriftService.new(account).record_version!(
        endpoint, { "type" => "array", "items" => { "type" => "object", "properties" => { "city" => { "type" => "string" } } } }
      )
      Ai::DataSources::SchemaDriftService.new(account).record_version!(
        endpoint, { "type" => "array", "items" => { "type" => "object", "properties" => { "city" => { "type" => "string" }, "temp" => { "type" => "number" } } } }
      )
    end

    it "returns the ordered version history with the latest diff" do
      result = tool.execute(params: {
        action: "data_source_schema_history", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:count]).to eq(2)
      expect(data[:versions].map { |v| v[:version] }).to eq([1, 2])
      expect(data[:versions].last[:classification]).to eq("additive")
      expect(data[:endpoint]).to include(id: endpoint.id, slug: "forecast")
      expect(data[:latest_diff]).to include("added_fields")
    end

    it "denies schema_history (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      locked_endpoint = create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_schema_history", data_source_id: "locked-src", endpoint_id: "ep"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_quality — latest quality outcome + expectations (read)
  # ------------------------------------------------------------------------

  describe "#execute data_source_quality" do
    let!(:expectation) do
      create(:ai_data_source_expectation, endpoint: endpoint, name: "non_empty",
                                          rule_type: "min_records", severity: "warn", config: { "min" => 1 })
    end
    let!(:recorded_query) do
      Ai::DataSourceQuery.create!(
        account_id: account.id, ai_data_source_id: data_source.id,
        ai_data_source_endpoint_id: endpoint.id, status: "success",
        quality_score: 0.9, quality_passed: true, quarantined: false, schema_drift: "none"
      )
    end

    it "returns the latest quality summary and configured expectations" do
      result = tool.execute(params: {
        action: "data_source_quality", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:latest_quality]).to include(query_id: recorded_query.id, quality_passed: true)
      expect(data[:expectation_count]).to eq(1)
      expect(data[:expectations].first).to include(name: "non_empty", rule_type: "min_records")
      expect(data[:endpoint]).to include(quality_checks_enabled: false, quarantine_on_failure: false)
    end

    it "returns a nil latest_quality when the endpoint has no recorded query" do
      fresh = create(:ai_data_source_endpoint, data_source: data_source, slug: "no-q")

      result = tool.execute(params: {
        action: "data_source_quality", data_source_id: "open-meteo", endpoint_id: "no-q"
      })

      expect(result[:success]).to be true
      expect(result[:data][:latest_quality]).to be_nil
    end

    it "denies quality (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_quality", data_source_id: "locked-src", endpoint_id: "ep"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_contract — aggregate verdict (read). Delegates to QueryService
  # + ContractService; the QueryService fetch is stubbed (no network).
  # ------------------------------------------------------------------------

  describe "#execute data_source_contract" do
    let(:envelope) do
      {
        success: true,
        data: [{ "city" => "NYC" }],
        provenance: { schema_valid: true, quality_passed: true, cache_age_seconds: 0 },
        status: "success", duration_ms: 3, bytes: 10, error: nil
      }
    end

    before do
      fake = instance_double(Ai::DataSources::QueryService, call: envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)
    end

    it "runs the governed fetch and returns the aggregate contract verdict" do
      result = tool.execute(params: {
        action: "data_source_contract", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:contract]).to include(met: true, schema_valid: true, quality_passed: true)
      expect(data[:contract][:violations]).to eq([])
      expect(data[:fetch_status]).to eq("success")
      expect(data[:fetch_success]).to be true
    end

    it "denies contract (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_contract", data_source_id: "locked-src", endpoint_id: "ep"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_introspect — OpenAPI import (manage-gated, incl. dry_run)
  # ------------------------------------------------------------------------

  describe "#execute data_source_introspect" do
    let(:spec) do
      {
        "openapi" => "3.0.0",
        "paths" => {
          "/forecast" => {
            "get" => {
              "operationId" => "get_forecast",
              "responses" => {
                "200" => { "content" => { "application/json" => { "schema" => { "type" => "object" } } } }
              }
            }
          }
        }
      }
    end

    it "imports endpoints from an inline spec (no-agent => fail-open)" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_introspect", data_source_id: "open-meteo", spec: spec
        })
      end.to change { data_source.endpoints.count }.by(1)

      expect(result[:success]).to be true
      expect(result[:data][:dry_run]).to be false
      expect(result[:data][:created_count]).to eq(1)
      expect(result[:data][:created].first).to include(slug: "get_forecast", http_method: "GET")
    end

    it "previews without persisting on dry_run" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_introspect", data_source_id: "open-meteo", spec: spec, dry_run: true
        })
      end.not_to change { data_source.endpoints.count }

      expect(result[:success]).to be true
      expect(result[:data][:dry_run]).to be true
      expect(result[:data][:created]).to eq([])
      expect(result[:data][:preview_count]).to eq(1)
    end

    it "errors when spec is blank" do
      result = tool.execute(params: {
        action: "data_source_introspect", data_source_id: "open-meteo"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/spec is required/i)
    end

    it "is gated by ai.data_sources.manage — a manage-less account is denied even for dry_run" do
      locked_account = create(:account)
      # A user with the read grant (but NOT manage) so the gate reflects the
      # absence of manage rather than the absence of any permission.
      create(:user, account: locked_account, permissions: ["ai.data_sources.read"])
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      expect(Ai::DataSources::OpenApiImportService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_introspect", data_source_id: "locked-src", spec: spec, dry_run: true
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.manage/)
    end

    it "allows introspect when a user in the account holds ai.data_sources.manage" do
      manage_account = create(:account)
      create(:user, account: manage_account, permissions: ["ai.data_sources.manage"])
      no_perm_user = create(:user, account: manage_account, permissions: [])
      manage_agent = create(:ai_agent, account: manage_account, creator: no_perm_user)
      manage_source = create(:ai_data_source, account: manage_account, slug: "manage-src")

      agent_tool = described_class.new(account: manage_account, agent: manage_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_introspect", data_source_id: "manage-src", spec: spec, dry_run: true
      })

      expect(result[:success]).to be true
      expect(result[:data][:dry_run]).to be true
    end
  end

  # ------------------------------------------------------------------------
  # misc
  # ------------------------------------------------------------------------

  describe "#execute with an unknown action" do
    it "returns an error" do
      result = tool.execute(params: { action: "data_source_obliterate" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Unknown action/)
    end
  end

  describe "parameter validation" do
    it "raises ArgumentError when action is missing" do
      expect { tool.execute(params: {}) }
        .to raise_error(ArgumentError, /Missing required parameters: action/)
    end
  end
end

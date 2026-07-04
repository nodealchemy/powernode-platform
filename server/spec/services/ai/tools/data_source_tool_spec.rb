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
    it "exposes all twenty-nine data-source actions" do
      keys = described_class.action_definitions.keys
      expect(keys).to contain_exactly(
        "data_source_list", "data_source_get", "data_source_describe",
        "data_source_query", "data_source_health", "data_source_validate_config",
        "data_source_create", "data_source_update", "data_source_delete",
        "data_source_discover", "data_source_provenance", "data_source_impact",
        "data_source_schema_history", "data_source_quality",
        "data_source_contract", "data_source_introspect",
        "data_source_subscribe", "data_source_unsubscribe",
        "data_source_invalidate_cache",
        # Phase 4b-3b onboarding portability
        "data_source_export", "data_source_import", "data_source_list_templates",
        "data_source_install_template", "data_source_config_versions",
        "data_source_rollback_config",
        # Phase 4b-3c multi-source coordination + RAG ingestion bridge
        "data_source_reconcile", "data_source_failover_query",
        "data_source_replay", "data_source_ingest_to_kb"
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
  # write endpoint gate (agent context => WRITE_ENDPOINT_PERMISSION consulted)
  # ------------------------------------------------------------------------
  #
  # A write/side-effecting endpoint (http_method not GET/HEAD, or an explicit
  # metadata["side_effecting"] opt-in — mirrors the X.com template's "Create
  # post" endpoint: POST /2/tweets, cache_ttl_seconds: 0) additionally requires
  # ai.data_sources.manage on top of ai.data_sources.query. Lacking it routes
  # data_source_query (and the other single-endpoint-execution actions) to the
  # same Ai::ProposalService fallback used by data-source-level mutations — the
  # live call never dispatches. An AGENT must not be able to silently publish.
  describe "write endpoint gate" do
    let!(:write_source) { create(:ai_data_source, account: account, slug: "x-com", name: "X.com") }
    let!(:write_endpoint) do
      create(:ai_data_source_endpoint, data_source: write_source, slug: "create-post",
             name: "Create post", http_method: "POST", cache_ttl_seconds: 0,
             metadata: { "side_effecting" => true })
    end
    let!(:read_endpoint) do
      create(:ai_data_source_endpoint, data_source: write_source, slug: "get-me", http_method: "GET")
    end

    context "agent lacking ai.data_sources.manage" do
      let(:agent) { create(:ai_agent, account: account) }

      before { create(:user, account: account, permissions: ["ai.data_sources.query"]) }

      it "files a proposal for data_source_query against the write endpoint and never dispatches QueryService" do
        agent_tool = described_class.new(account: account, agent: agent, user: user)
        expect(Ai::DataSources::QueryService).not_to receive(:new)

        result = nil
        expect do
          result = agent_tool.execute(params: {
            action: "data_source_query", data_source_id: "x-com",
            endpoint_id: "create-post", params: { "text" => "hello world" }
          })
        end.to change(Ai::AgentProposal, :count).by(1)

        expect(result[:success]).to be true
        expect(result[:requires_approval]).to be true
        expect(result[:proposal_id]).to be_present
        expect(result[:message]).to match(/ai\.data_sources\.manage required/)
        expect(result[:proposed_changes]).to include(action: "execute_endpoint", endpoint_id: write_endpoint.id)

        proposal = Ai::AgentProposal.order(:created_at).last
        expect(proposal.proposal_type).to eq("configuration")
        expect(proposal.agent).to eq(agent)
      end

      it "still executes a GET endpoint normally — read behavior unaffected" do
        agent_tool = described_class.new(account: account, agent: agent, user: user)
        fake = instance_double(Ai::DataSources::QueryService,
                                call: { success: true, data: [], provenance: {}, status: "success",
                                        duration_ms: 1, bytes: 0, error: nil })
        expect(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

        result = agent_tool.execute(params: {
          action: "data_source_query", data_source_id: "x-com", endpoint_id: "get-me"
        })

        expect(result[:success]).to be true
        expect(Ai::AgentProposal.count).to eq(0)
      end

      it "blocks the write endpoint via data_source_contract too, without dispatching" do
        agent_tool = described_class.new(account: account, agent: agent, user: user)
        expect(Ai::DataSources::QueryService).not_to receive(:new)

        result = agent_tool.execute(params: {
          action: "data_source_contract", data_source_id: "x-com", endpoint_id: "create-post"
        })

        expect(result[:requires_approval]).to be true
      end

      it "refuses the whole failover call up front when any target is an unauthorized write endpoint" do
        agent_tool = described_class.new(account: account, agent: agent, user: user)
        expect(Ai::DataSources::FailoverService).not_to receive(:new)

        result = agent_tool.execute(params: {
          action: "data_source_failover_query",
          targets: [{ data_source_id: "x-com", endpoint_id: "create-post" }]
        })

        expect(result[:requires_approval]).to be true
      end
    end

    context "agent holding ai.data_sources.manage" do
      let(:agent) { create(:ai_agent, account: account) }

      before { create(:user, account: account, permissions: ["ai.data_sources.manage"]) }

      it "dispatches data_source_query against the write endpoint instead of filing a proposal" do
        agent_tool = described_class.new(account: account, agent: agent, user: user)
        fake = instance_double(Ai::DataSources::QueryService,
                                call: { success: true, data: [{ "id" => "123" }], provenance: {},
                                        status: "success", duration_ms: 1, bytes: 0, error: nil })
        expect(Ai::DataSources::QueryService).to receive(:new).with(
          hash_including(data_source: write_source, endpoint: write_endpoint)
        ).and_return(fake)

        result = nil
        expect do
          result = agent_tool.execute(params: {
            action: "data_source_query", data_source_id: "x-com",
            endpoint_id: "create-post", params: { "text" => "hello world" }
          })
        end.not_to change(Ai::AgentProposal, :count)

        expect(result[:success]).to be true
        expect(result).not_to include(:requires_approval)
      end
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

    it "returns a validation error on create with a malformed source_type" do
      # Phase 4 made source_type free-form (any lowercase token), so the rejection
      # case is now a FORMAT violation (uppercase/spaces), not an out-of-enum value.
      result = tool.execute(params: {
        action: "data_source_create", name: "Bad", source_type: "Not A Real Type!"
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

  # ------------------------------------------------------------------------
  # cache invalidation (operational write — ai.data_sources.update / .manage)
  # ------------------------------------------------------------------------

  describe "#execute data_source_invalidate_cache" do
    it "invalidates by surrogate tag and reports the action + permission used" do
      allow(Ai::DataSources::ResponseCacheService).to receive(:invalidate_by_tag).with("slug:forecast").and_return(3)

      result = tool.execute(params: { action: "data_source_invalidate_cache", tag: "slug:forecast" })

      expect(result[:success]).to be true
      expect(result[:data][:action]).to eq("data_source_invalidate_cache")
      expect(result[:data][:scope]).to eq("tag")
      expect(result[:data][:tag]).to eq("slug:forecast")
      expect(result[:data][:invalidated]).to eq(3)
      expect(result[:data][:permission_used]).to eq("ai.data_sources.update")
    end

    it "invalidates a single endpoint scope when given data_source_id + endpoint_id" do
      expect(Ai::DataSources::ResponseCacheService).to receive(:invalidate)
        .with(hash_including(data_source: data_source)).and_return(2)

      result = tool.execute(params: {
        action: "data_source_invalidate_cache", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be true
      expect(result[:data][:scope]).to eq("endpoint")
      expect(result[:data][:endpoint][:slug]).to eq("forecast")
      expect(result[:data][:invalidated]).to eq(2)
    end

    it "invalidates the whole source when only data_source_id is given" do
      expect(Ai::DataSources::ResponseCacheService).to receive(:invalidate)
        .with(data_source: data_source, endpoint: nil).and_return(5)

      result = tool.execute(params: { action: "data_source_invalidate_cache", data_source_id: "open-meteo" })

      expect(result[:success]).to be true
      expect(result[:data][:scope]).to eq("data_source")
      expect(result[:data][:invalidated]).to eq(5)
    end

    it "raises a not-found for an unknown source (scoped, no tag)" do
      result = tool.execute(params: { action: "data_source_invalidate_cache", data_source_id: "nope" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Data source not found/)
    end
  end

  describe "data_source_invalidate_cache permission gate (agent context)" do
    # Locked account whose users carry no data-source mutation grant, so
    # permission? truly reflects the absence of update / manage.
    let(:locked_account) { create(:account) }
    let(:no_perm_user) { create(:user, account: locked_account, permissions: []) }
    let(:locked_agent) { create(:ai_agent, account: locked_account, creator: no_perm_user) }
    let!(:locked_source) { create(:ai_data_source, account: locked_account, slug: "locked-cache-src") }

    it "denies when no user in the account holds ai.data_sources.update or .manage" do
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      result = agent_tool.execute(params: {
        action: "data_source_invalidate_cache", data_source_id: "locked-cache-src"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.update/)
    end

    it "allows when a user in the account holds ai.data_sources.update" do
      create(:user, account: locked_account, permissions: ["ai.data_sources.update"])
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      allow(Ai::DataSources::ResponseCacheService).to receive(:invalidate).and_return(0)

      result = agent_tool.execute(params: {
        action: "data_source_invalidate_cache", data_source_id: "locked-cache-src"
      })

      expect(result[:success]).to be true
      expect(result[:data][:permission_used]).to eq("ai.data_sources.update")
    end

    it "allows (via .manage) and reports manage as the permission used when only manage is held" do
      create(:user, account: locked_account, permissions: ["ai.data_sources.manage"])
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      allow(Ai::DataSources::ResponseCacheService).to receive(:invalidate_by_tag).and_return(1)

      result = agent_tool.execute(params: {
        action: "data_source_invalidate_cache", tag: "ds:#{locked_source.id}"
      })

      expect(result[:success]).to be true
      expect(result[:data][:permission_used]).to eq("ai.data_sources.manage")
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
  # data_source_subscribe — create/update a pull-based subscription (Phase 3).
  # Stream-gated (ai.data_sources.stream); idempotent on the (source, endpoint)
  # pair via find_or_initialize. No outbound fetch — the monitor loop is server-
  # side and out of scope here.
  # ------------------------------------------------------------------------

  describe "#execute data_source_subscribe" do
    it "creates a subscription and returns the summary (no-agent => fail-open)" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_subscribe", data_source_id: "open-meteo",
          endpoint_id: "forecast", poll_frequency: "5min"
        })
      end.to change { data_source.subscriptions.count }.by(1)

      expect(result[:success]).to be true
      expect(result[:data][:message]).to eq("Subscription created")
      sub = result[:data][:subscription]
      expect(sub).to include(
        :id, :data_source_id, :endpoint_id, :poll_frequency, :status,
        :params, :next_poll_at, :last_polled_at, :last_checksum,
        :consecutive_failures, :agent_id
      )
      expect(sub[:data_source_id]).to eq(data_source.id)
      expect(sub[:endpoint_id]).to eq(endpoint.id)
      expect(sub[:poll_frequency]).to eq("5min")
      expect(sub[:status]).to eq("active")
      expect(sub[:next_poll_at]).to be_present
    end

    it "defaults the cadence to hourly when poll_frequency is omitted" do
      result = tool.execute(params: {
        action: "data_source_subscribe", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be true
      expect(result[:data][:subscription][:poll_frequency]).to eq("hourly")
    end

    it "persists per-poll params" do
      result = tool.execute(params: {
        action: "data_source_subscribe", data_source_id: "open-meteo", endpoint_id: "forecast",
        poll_frequency: "hourly", params: { "latitude" => 40.7 }
      })

      expect(result[:success]).to be true
      expect(result[:data][:subscription][:params]).to eq("latitude" => 40.7)
    end

    it "is idempotent on the (source, endpoint) pair — a second subscribe updates, not duplicates" do
      first = tool.execute(params: {
        action: "data_source_subscribe", data_source_id: "open-meteo",
        endpoint_id: "forecast", poll_frequency: "hourly"
      })
      created_id = first[:data][:subscription][:id]

      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_subscribe", data_source_id: "open-meteo",
          endpoint_id: "forecast", poll_frequency: "daily"
        })
      end.not_to change { data_source.subscriptions.count }

      expect(result[:success]).to be true
      expect(result[:data][:message]).to eq("Subscription updated")
      expect(result[:data][:subscription][:id]).to eq(created_id)
      expect(result[:data][:subscription][:poll_frequency]).to eq("daily")
    end

    it "errors on an invalid poll_frequency without creating a subscription" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_subscribe", data_source_id: "open-meteo",
          endpoint_id: "forecast", poll_frequency: "every_blue_moon"
        })
      end.not_to change { data_source.subscriptions.count }

      expect(result[:success]).to be false
      expect(result[:error]).to match(/poll_frequency/i)
    end

    it "surfaces a not-found error for an unknown endpoint" do
      result = tool.execute(params: {
        action: "data_source_subscribe", data_source_id: "open-meteo", endpoint_id: "ghost"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_unsubscribe — remove a subscription (Phase 3, stream-gated)
  # ------------------------------------------------------------------------

  describe "#execute data_source_unsubscribe" do
    let!(:subscription) do
      data_source.subscriptions.create!(endpoint: endpoint, poll_frequency: "hourly", status: "active")
    end

    it "removes a subscription by subscription_id (account-scoped)" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_unsubscribe", subscription_id: subscription.id
        })
      end.to change { Ai::DataSourceSubscription.count }.by(-1)

      expect(result[:success]).to be true
      expect(result[:data][:message]).to match(/deleted/i)
      expect(result[:data][:subscription_id]).to eq(subscription.id)
    end

    it "removes every subscription matching a (data_source, endpoint) pair" do
      result = nil
      expect do
        result = tool.execute(params: {
          action: "data_source_unsubscribe", data_source_id: "open-meteo", endpoint_id: "forecast"
        })
      end.to change { Ai::DataSourceSubscription.count }.by(-1)

      expect(result[:success]).to be true
      expect(result[:data][:removed_count]).to eq(1)
      expect(result[:data][:data_source_id]).to eq(data_source.id)
      expect(result[:data][:endpoint_id]).to eq(endpoint.id)
    end

    it "errors when neither subscription_id nor a (source, endpoint) pair is given" do
      result = tool.execute(params: { action: "data_source_unsubscribe" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/subscription_id.*data_source_id.*endpoint_id/i)
    end

    it "surfaces a not-found error for an unknown subscription_id" do
      result = tool.execute(params: {
        action: "data_source_unsubscribe", subscription_id: SecureRandom.uuid
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "does not remove a subscription from another account by id" do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account, slug: "other-src")
      other_ep = create(:ai_data_source_endpoint, data_source: other_source, slug: "ep")
      foreign = other_source.subscriptions.create!(endpoint: other_ep, poll_frequency: "hourly", status: "active")

      result = tool.execute(params: {
        action: "data_source_unsubscribe", subscription_id: foreign.id
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
      expect(Ai::DataSourceSubscription.exists?(foreign.id)).to be true
    end
  end

  # ------------------------------------------------------------------------
  # stream permission gate (agent context => permission? is consulted). The
  # subscribe/unsubscribe actions are gated by ai.data_sources.stream — distinct
  # from the read grant that gates tool visibility.
  # ------------------------------------------------------------------------

  describe "stream permission gate" do
    # Isolated account whose only user holds NO permissions, so permission?
    # genuinely reflects the absence of ai.data_sources.stream.
    let(:locked_account) { create(:account) }
    let(:no_perm_user) { create(:user, account: locked_account, permissions: []) }
    let(:locked_agent) { create(:ai_agent, account: locked_account, creator: no_perm_user) }
    let!(:locked_source) { create(:ai_data_source, account: locked_account, slug: "locked-src") }
    let!(:locked_endpoint) { create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep") }

    it "denies data_source_subscribe when no user in the account holds ai.data_sources.stream" do
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_subscribe", data_source_id: "locked-src",
          endpoint_id: "ep", poll_frequency: "hourly"
        })
      end.not_to change { Ai::DataSourceSubscription.count }

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.stream/)
    end

    it "denies data_source_unsubscribe when the account lacks ai.data_sources.stream" do
      existing = locked_source.subscriptions.create!(
        endpoint: locked_endpoint, poll_frequency: "hourly", status: "active"
      )
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_unsubscribe", subscription_id: existing.id
        })
      end.not_to change { Ai::DataSourceSubscription.count }

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.stream/)
      expect(Ai::DataSourceSubscription.exists?(existing.id)).to be true
    end

    it "allows data_source_subscribe when a user in the account holds the stream grant" do
      create(:user, account: locked_account, permissions: ["ai.data_sources.stream"])
      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)

      result = agent_tool.execute(params: {
        action: "data_source_subscribe", data_source_id: "locked-src",
        endpoint_id: "ep", poll_frequency: "hourly"
      })

      expect(result[:success]).to be true
      expect(result[:data][:subscription][:endpoint_id]).to eq(locked_endpoint.id)
    end
  end

  # ========================================================================
  # Phase 4b-3c — multi-source coordination + RAG ingestion bridge
  #
  # Four new actions, each a thin router that wires params -> the underlying
  # service -> the service's result:
  #   * data_source_reconcile      (query)  -> QueryService (per target) + ReconciliationService
  #   * data_source_failover_query (query)  -> FailoverService
  #   * data_source_replay         (read)   -> ReplayService
  #   * data_source_ingest_to_kb   (manage) -> QueryService + RagIngestionService (proposal fallback)
  #
  # The collaborators are stubbed (instance_double) so these specs assert the
  # routing/permission wiring only — never hitting network, embeddings, or the
  # full governed fetch pipeline.
  # ------------------------------------------------------------------------

  # ------------------------------------------------------------------------
  # data_source_reconcile — deterministic multi-source merge (query-gated).
  # Governed-fetch every target via QueryService, then collapse by exact key
  # via ReconciliationService. Both collaborators are stubbed.
  # ------------------------------------------------------------------------

  describe "#execute data_source_reconcile" do
    let!(:other_source) do
      create(:ai_data_source, account: account, slug: "fred", source_type: "fred", name: "FRED")
    end
    let!(:other_endpoint) { create(:ai_data_source_endpoint, data_source: other_source, slug: "series") }

    let(:envelope_a) do
      { success: true, data: [{ "k" => "1", "v" => "a" }], provenance: {},
        status: "success", duration_ms: 2, bytes: 10, error: nil }
    end
    let(:envelope_b) do
      { success: true, data: [{ "k" => "1", "v" => "b" }, { "k" => "2", "v" => "c" }],
        provenance: {}, status: "success", duration_ms: 3, bytes: 20, error: nil }
    end
    let(:merged) { [{ "k" => "1", "v" => "b" }, { "k" => "2", "v" => "c" }] }

    let(:targets) do
      [
        { "data_source_id" => "open-meteo", "endpoint_id" => "forecast" },
        { "data_source_id" => "fred", "endpoint_id" => "series" }
      ]
    end

    it "fetches every target then merges by key via ReconciliationService" do
      # One governed fetch per target (order preserved); stub QueryService to
      # return a distinct envelope for each call.
      fetch = instance_double(Ai::DataSources::QueryService)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fetch)
      allow(fetch).to receive(:call).and_return(envelope_a, envelope_b)

      recon = instance_double(Ai::DataSources::ReconciliationService, reconcile: merged)
      expect(Ai::DataSources::ReconciliationService).to receive(:new)
        .with(key: "k", strategy: "first_wins").and_return(recon)
      # The successful envelopes' data arrays are handed to reconcile in order.
      expect(recon).to receive(:reconcile)
        .with([envelope_a[:data], envelope_b[:data]]).and_return(merged)

      result = tool.execute(params: {
        action: "data_source_reconcile", targets: targets, key: "k", strategy: "first_wins"
      })

      expect(result[:success]).to be true
      expect(result[:data][:key]).to eq("k")
      expect(result[:data][:strategy]).to eq("first_wins")
      expect(result[:data][:reconciled]).to eq(merged)
      expect(result[:data][:reconciled_count]).to eq(2)
      expect(result[:data][:source_count]).to eq(2)
      expect(result[:data][:succeeded_count]).to eq(2)
      expect(result[:data][:sources].map { |s| s[:endpoint_slug] }).to contain_exactly("forecast", "series")
    end

    it "defaults the strategy to last_wins when omitted" do
      fetch = instance_double(Ai::DataSources::QueryService, call: envelope_a)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fetch)
      expect(Ai::DataSources::ReconciliationService).to receive(:new)
        .with(key: "k", strategy: Ai::DataSources::ReconciliationService::DEFAULT_STRATEGY)
        .and_return(instance_double(Ai::DataSources::ReconciliationService, reconcile: []))

      result = tool.execute(params: {
        action: "data_source_reconcile",
        targets: [{ "data_source_id" => "open-meteo", "endpoint_id" => "forecast" }],
        key: "k"
      })

      expect(result[:success]).to be true
      expect(result[:data][:strategy]).to eq(Ai::DataSources::ReconciliationService::DEFAULT_STRATEGY)
    end

    it "records a per-source status (only successful envelopes feed the merge)" do
      fetch = instance_double(Ai::DataSources::QueryService)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fetch)
      failure = { success: false, data: [], provenance: {}, status: "error",
                  duration_ms: 1, bytes: 0, error: "upstream down" }
      allow(fetch).to receive(:call).and_return(envelope_a, failure)

      recon = instance_double(Ai::DataSources::ReconciliationService, reconcile: envelope_a[:data])
      # Only the successful envelope's records are passed to reconcile.
      expect(Ai::DataSources::ReconciliationService).to receive(:new).and_return(recon)
      expect(recon).to receive(:reconcile).with([envelope_a[:data]]).and_return(envelope_a[:data])

      result = tool.execute(params: {
        action: "data_source_reconcile", targets: targets, key: "k"
      })

      expect(result[:success]).to be true
      expect(result[:data][:source_count]).to eq(2)
      expect(result[:data][:succeeded_count]).to eq(1)
      statuses = result[:data][:sources]
      expect(statuses.find { |s| s[:endpoint_slug] == "series" }).to include(success: false, error: "upstream down")
    end

    it "errors when key is blank" do
      result = tool.execute(params: { action: "data_source_reconcile", targets: targets, key: "" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/key is required/i)
    end

    it "errors when targets is empty/malformed" do
      result = tool.execute(params: { action: "data_source_reconcile", targets: [], key: "k" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/targets is required/i)
    end

    it "denies reconcile when no user in the account holds ai.data_sources.query" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")
      expect(Ai::DataSources::QueryService).not_to receive(:new)
      expect(Ai::DataSources::ReconciliationService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_reconcile", key: "k",
        targets: [{ "data_source_id" => "locked-src", "endpoint_id" => "ep" }]
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.query/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_failover_query — ordered failover (query-gated). Resolves the
  # ordered targets to model pairs and hands them to FailoverService, returning
  # its FetchEnvelope verbatim.
  # ------------------------------------------------------------------------

  describe "#execute data_source_failover_query" do
    let!(:backup_source) do
      create(:ai_data_source, account: account, slug: "fred", source_type: "fred", name: "FRED")
    end
    let!(:backup_endpoint) { create(:ai_data_source_endpoint, data_source: backup_source, slug: "series") }

    let(:targets) do
      [
        { "data_source_id" => "open-meteo", "endpoint_id" => "forecast" },
        { "data_source_id" => "fred", "endpoint_id" => "series" }
      ]
    end
    let(:envelope) do
      {
        success: true,
        data: [{ "city" => "NYC" }],
        provenance: { slug: "open-meteo", failover_used: false, failover_attempts: 1, failover_source: "open-meteo" },
        status: "success", duration_ms: 4, bytes: 12, error: nil
      }
    end

    it "resolves ordered target pairs and returns FailoverService's envelope verbatim" do
      fake = instance_double(Ai::DataSources::FailoverService, query: envelope)
      expect(Ai::DataSources::FailoverService).to receive(:new)
        .with(hash_including(account: account, agent: nil, user: user)).and_return(fake)
      # Pairs preserve order (primary first) and resolve to the model records.
      expect(fake).to receive(:query).with(
        [
          { data_source: data_source, endpoint: endpoint },
          { data_source: backup_source, endpoint: backup_endpoint }
        ],
        params: { "series_id" => "GDP" }
      ).and_return(envelope)

      result = tool.execute(params: {
        action: "data_source_failover_query", targets: targets, params: { "series_id" => "GDP" }
      })

      expect(result).to eq(envelope)
      expect(result[:success]).to be true
      expect(result[:provenance]).to include(:failover_used, :failover_attempts, :failover_source)
    end

    it "errors when targets is empty/malformed" do
      result = tool.execute(params: { action: "data_source_failover_query", targets: [] })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/targets is required/i)
    end

    it "surfaces a not-found error for an unknown target endpoint" do
      result = tool.execute(params: {
        action: "data_source_failover_query",
        targets: [{ "data_source_id" => "open-meteo", "endpoint_id" => "ghost" }]
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "denies failover_query when no user in the account holds ai.data_sources.query" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-src")
      create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")
      expect(Ai::DataSources::FailoverService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: {
        action: "data_source_failover_query",
        targets: [{ "data_source_id" => "locked-src", "endpoint_id" => "ep" }]
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.query/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_replay — forensic, side-effect-free replay (READ-gated).
  # Routes a query_id/correlation_id ref (+ optional params) into
  # ReplayService#replay and returns its envelope verbatim. No network.
  # ------------------------------------------------------------------------

  describe "#execute data_source_replay" do
    let(:replayed) do
      {
        success: true,
        data: [{ "city" => "NYC", "temp" => "72" }],
        provenance: { replayed: true, from_cache: true, slug: "open-meteo" },
        status: "success", duration_ms: 0, bytes: 0, error: nil
      }
    end

    it "routes a query_id into ReplayService#replay and returns its envelope verbatim" do
      fake = instance_double(Ai::DataSources::ReplayService, replay: replayed)
      expect(Ai::DataSources::ReplayService).to receive(:new)
        .with(hash_including(account: account, agent: nil)).and_return(fake)
      expect(fake).to receive(:replay).with("q-123", params: nil).and_return(replayed)

      result = tool.execute(params: { action: "data_source_replay", query_id: "q-123" })

      expect(result).to eq(replayed)
      expect(result[:success]).to be true
      expect(result[:provenance]).to include(replayed: true)
    end

    it "passes the correlation_id ref and original params through to re-mask the cached body" do
      fake = instance_double(Ai::DataSources::ReplayService)
      allow(Ai::DataSources::ReplayService).to receive(:new).and_return(fake)
      expect(fake).to receive(:replay)
        .with("corr-xyz", params: { "latitude" => 40.7 }).and_return(replayed)

      result = tool.execute(params: {
        action: "data_source_replay", correlation_id: "corr-xyz", params: { "latitude" => 40.7 }
      })

      expect(result[:success]).to be true
    end

    it "prefers query_id over correlation_id when both are supplied" do
      fake = instance_double(Ai::DataSources::ReplayService)
      allow(Ai::DataSources::ReplayService).to receive(:new).and_return(fake)
      expect(fake).to receive(:replay).with("q-123", params: nil).and_return(replayed)

      result = tool.execute(params: {
        action: "data_source_replay", query_id: "q-123", correlation_id: "corr-xyz"
      })

      expect(result[:success]).to be true
    end

    it "errors when neither query_id nor correlation_id is given" do
      expect(Ai::DataSources::ReplayService).not_to receive(:new)

      result = tool.execute(params: { action: "data_source_replay" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/query_id or correlation_id/i)
    end

    it "denies replay (a read action) when the agent's account lacks ai.data_sources.read" do
      locked_account = create(:account)
      no_perm_user = create(:user, account: locked_account, permissions: [])
      locked_agent = create(:ai_agent, account: locked_account, creator: no_perm_user)
      expect(Ai::DataSources::ReplayService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: no_perm_user)
      result = agent_tool.execute(params: { action: "data_source_replay", query_id: "q-123" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Permission denied: ai\.data_sources\.read/)
    end
  end

  # ------------------------------------------------------------------------
  # data_source_ingest_to_kb — RAG ingestion bridge (MANAGE-gated, proposal
  # fallback). Governed-fetch the source+endpoint via QueryService, then pipe
  # the records into a knowledge base via RagIngestionService#ingest. Both
  # collaborators are stubbed.
  # ------------------------------------------------------------------------

  describe "#execute data_source_ingest_to_kb" do
    let!(:knowledge_base) { create(:ai_knowledge_base, account: account) }
    let(:envelope) do
      {
        success: true,
        data: [{ "id" => "1", "title" => "Doc A" }, { "id" => "2", "title" => "Doc B" }],
        provenance: {}, status: "success", duration_ms: 6, bytes: 30, error: nil
      }
    end
    let(:tally) do
      { ingested: 2, updated: 0, skipped: 0, capped: 0, errors: 0, knowledge_base_id: nil }
    end

    it "fetches the source then routes records + KB into RagIngestionService#ingest (no-agent => fail-open)" do
      fetch = instance_double(Ai::DataSources::QueryService, call: envelope)
      expect(Ai::DataSources::QueryService).to receive(:new).with(
        hash_including(data_source: data_source, endpoint: endpoint, user: user)
      ).and_return(fetch)

      ingestor = instance_double(Ai::DataSources::RagIngestionService)
      expect(Ai::DataSources::RagIngestionService).to receive(:new)
        .with(hash_including(account: account, user: user)).and_return(ingestor)
      expect(ingestor).to receive(:ingest).with(
        hash_including(
          data_source: data_source,
          endpoint: endpoint,
          knowledge_base: knowledge_base.id,
          records: envelope[:data],
          key: "id"
        )
      ).and_return(tally.merge(knowledge_base_id: knowledge_base.id))

      result = tool.execute(params: {
        action: "data_source_ingest_to_kb", data_source_id: "open-meteo",
        endpoint_id: "forecast", knowledge_base_id: knowledge_base.id, key: "id"
      })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:data_source]).to include(id: data_source.id, slug: "open-meteo")
      expect(data[:endpoint]).to include(id: endpoint.id, slug: "forecast")
      expect(data[:knowledge_base_id]).to eq(knowledge_base.id)
      expect(data[:fetch_status]).to eq("success")
      expect(data[:fetch_success]).to be true
      expect(data[:ingest]).to include(ingested: 2, knowledge_base_id: knowledge_base.id)
    end

    it "passes a nil key through when none is supplied" do
      fetch = instance_double(Ai::DataSources::QueryService, call: envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fetch)
      ingestor = instance_double(Ai::DataSources::RagIngestionService)
      allow(Ai::DataSources::RagIngestionService).to receive(:new).and_return(ingestor)
      expect(ingestor).to receive(:ingest).with(hash_including(key: nil)).and_return(tally)

      result = tool.execute(params: {
        action: "data_source_ingest_to_kb", data_source_id: "open-meteo",
        endpoint_id: "forecast", knowledge_base_id: knowledge_base.id
      })

      expect(result[:success]).to be true
    end

    it "errors when knowledge_base_id is blank" do
      expect(Ai::DataSources::RagIngestionService).not_to receive(:new)

      result = tool.execute(params: {
        action: "data_source_ingest_to_kb", data_source_id: "open-meteo", endpoint_id: "forecast"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/knowledge_base_id is required/i)
    end

    it "surfaces a not-found error for an unknown endpoint" do
      expect(Ai::DataSources::RagIngestionService).not_to receive(:new)

      result = tool.execute(params: {
        action: "data_source_ingest_to_kb", data_source_id: "open-meteo",
        endpoint_id: "ghost", knowledge_base_id: knowledge_base.id
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end

    it "performs the ingest instead of filing a proposal when authorized via ai.data_sources.manage" do
      manage_account = create(:account)
      create(:user, account: manage_account, permissions: ["ai.data_sources.manage"])
      no_perm_user = create(:user, account: manage_account, permissions: [])
      manage_agent = create(:ai_agent, account: manage_account, creator: no_perm_user)
      manage_source = create(:ai_data_source, account: manage_account, slug: "manage-src")
      manage_endpoint = create(:ai_data_source_endpoint, data_source: manage_source, slug: "ep")
      manage_kb = create(:ai_knowledge_base, account: manage_account)

      fetch = instance_double(Ai::DataSources::QueryService, call: envelope)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fetch)
      ingestor = instance_double(Ai::DataSources::RagIngestionService,
                                 ingest: tally.merge(knowledge_base_id: manage_kb.id))
      allow(Ai::DataSources::RagIngestionService).to receive(:new).and_return(ingestor)

      agent_tool = described_class.new(account: manage_account, agent: manage_agent, user: no_perm_user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_ingest_to_kb", data_source_id: "manage-src",
          endpoint_id: "ep", knowledge_base_id: manage_kb.id
        })
      end.not_to change(Ai::AgentProposal, :count)

      expect(result[:success]).to be true
      expect(result).not_to include(:requires_approval)
      expect(result[:data][:ingest]).to include(ingested: 2)
    end

    it "files a proposal (and does NOT ingest) when the account lacks ai.data_sources.manage" do
      locked_account = create(:account)
      # A user with the read grant but NOT manage, so mutation_permitted? is false
      # and the tool proposes rather than ingesting.
      create(:user, account: locked_account, permissions: ["ai.data_sources.read"])
      locked_agent = create(:ai_agent, account: locked_account, creator: user)
      locked_source = create(:ai_data_source, account: locked_account, slug: "locked-ingest")
      create(:ai_data_source_endpoint, data_source: locked_source, slug: "ep")
      locked_kb = create(:ai_knowledge_base, account: locked_account)
      expect(Ai::DataSources::QueryService).not_to receive(:new)
      expect(Ai::DataSources::RagIngestionService).not_to receive(:new)

      agent_tool = described_class.new(account: locked_account, agent: locked_agent, user: user)

      result = nil
      expect do
        result = agent_tool.execute(params: {
          action: "data_source_ingest_to_kb", data_source_id: "locked-ingest",
          endpoint_id: "ep", knowledge_base_id: locked_kb.id, key: "id"
        })
      end.to change(Ai::AgentProposal, :count).by(1)

      expect(result[:success]).to be true
      expect(result[:requires_approval]).to be true
      expect(result[:proposal_id]).to be_present
      expect(result[:status]).to eq("pending_review")
      expect(result[:message]).to match(/ai\.data_sources\.manage required/)
      expect(result[:proposed_changes]).to include(
        action: "ingest_to_kb", data_source_id: "locked-ingest",
        endpoint_id: "ep", knowledge_base_id: locked_kb.id, key: "id"
      )

      proposal = Ai::AgentProposal.order(:created_at).last
      expect(proposal.proposal_type).to eq("configuration")
      expect(proposal.agent).to eq(locked_agent)
      expect(proposal.account).to eq(locked_account)
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

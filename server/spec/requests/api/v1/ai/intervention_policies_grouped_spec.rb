# frozen_string_literal: true

require "rails_helper"

# The grouped view and bulk save behind core's InterventionPoliciesPanel.
#
# The panel builds its sections from the server's grouping of the account's
# rows, not from a list of categories written into the component: a hardcoded
# copy of a server-owned set drifts the day a policy is seeded (IMP-0874acd5b50c
# found one that omitted 28 of 119 categories). So:
#
#   GET   /api/v1/ai/intervention_policies/grouped  -> { policies: { by_domain } }
#   PATCH /api/v1/ai/intervention_policies/bulk     -> { updates: [...] }
#
# Domains come from Ai::ClaudeExport::PolicyDomains, where an extension
# REGISTERS its prefix table (first match wins). A row no registered domain
# claims lands in "other"; the heuristic that seam falls back to for routing is
# NOT used here, because an invented domain would be a section no extension
# presents. Every row carries `agent_bucket`, so a client groups by agent
# without re-deriving the rule.
#
# Categories and domains here are core's own (dev.*, ralph.*, approval), under
# domain keys no extension registers, so the examples hold with or without any
# extension loaded.
RSpec.describe "Api::V1::Ai::InterventionPolicies grouped view and bulk save", type: :request do
  let(:account)  { create(:account) }
  let(:operator) { user_with_permissions("ai.intervention_policies.manage", account: account) }
  let(:no_perms) { user_with_permissions(account: account) }
  let(:agent)    { create(:ai_agent, account: account, name: "Spec Reconciler") }

  around do |example|
    saved = Ai::ClaudeExport::PolicyDomains.registered.map { |(d, p)| [ d, p.dup ] }
    Ai::ClaudeExport::PolicyDomains.register("spec_dev", %w[dev.])
    Ai::ClaudeExport::PolicyDomains.register("spec_ralph", %w[ralph.])
    example.run
  ensure
    Ai::ClaudeExport::PolicyDomains.reset!
    saved.each { |(d, p)| Ai::ClaudeExport::PolicyDomains.register(d, p) }
  end

  def headers(user = operator)
    auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  def policy!(category, scope: "global", agent: nil, **attrs)
    Ai::InterventionPolicy.create!(
      { account: account, action_category: category, scope: scope, ai_agent_id: agent&.id,
        policy: "notify_and_proceed", priority: 5, is_active: true }.merge(attrs)
    )
  end

  def grouped
    get "/api/v1/ai/intervention_policies/grouped", headers: headers
    expect(response).to have_http_status(:ok)
    json_response_data["policies"]["by_domain"]
  end

  describe "GET grouped" do
    it "returns 401 without auth and 403 without the permission" do
      get "/api/v1/ai/intervention_policies/grouped"
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/ai/intervention_policies/grouped", headers: headers(no_perms)
      expect(response).to have_http_status(:forbidden)
    end

    it "files each row under the first registered domain its category matches, else other" do
      dev_row   = policy!("dev.task_requeue")
      ralph_row = policy!("ralph.repository_write")
      core_row  = policy!("approval")

      by_domain = grouped
      ids = by_domain.transform_values { |rows| rows.map { |r| r["id"] } }

      expect(ids["spec_dev"]).to eq([ dev_row.id ])
      expect(ids["spec_ralph"]).to eq([ ralph_row.id ])
      expect(ids["other"]).to include(core_row.id)
    end

    it "ships every registered domain, empty or not, in registration order, with other last" do
      keys = grouped.keys

      expect(keys.last).to eq("other")
      expect(keys).to include("spec_dev", "spec_ralph")
      expect(keys.index("spec_dev")).to be < keys.index("spec_ralph")
    end

    it "returns every account row, not a page of them" do
      60.times { |i| policy!("dev.task_requeue", scope: "agent", agent: create(:ai_agent, account: account, name: "A#{i}")) }

      expect(grouped.values.flatten.size).to eq(60)
    end

    it "returns no other account's rows" do
      Ai::InterventionPolicy.create!(account: create(:account), action_category: "dev.task_requeue",
                                     scope: "global", policy: "block", priority: 1)

      expect(grouped.values.flatten).to be_empty
    end

    it "names the owning agent as the bucket for an agent-scoped row and Manual Operations otherwise" do
      agent_row  = policy!("dev.task_requeue", scope: "agent", agent: agent)
      global_row = policy!("dev.multi_file_change")
      # An agent id on a non-agent scope: nothing ties the two together, and the
      # row is bucketed by SCOPE, not by the name it happens to carry.
      stray_row  = policy!("ralph.repository_write", scope: "action_type", agent: agent)

      rows = grouped.values.flatten.index_by { |r| r["id"] }

      expect(rows[agent_row.id]).to include("agent_bucket" => "Spec Reconciler", "scope" => "agent",
                                            "agent_id" => agent.id, "agent_name" => "Spec Reconciler")
      expect(rows[global_row.id]["agent_bucket"]).to eq("Manual Operations")
      expect(rows[stray_row.id]).to include("agent_bucket" => "Manual Operations", "agent_name" => "Spec Reconciler")
    end

    it "ships the account's active approval chains" do
      chain = create(:ai_approval_chain, account: account)
      create(:ai_approval_chain, account: account, status: "disabled")

      get "/api/v1/ai/intervention_policies/grouped", headers: headers

      expect(json_response_data["chains"].map { |c| c["id"] }).to eq([ chain.id ])
    end
  end

  # The panel's "All policies" list reads the index. It used to default to 50
  # rows with total_count counting the page, so an account with more rows saw a
  # silently truncated list that claimed to be complete.
  describe "GET index" do
    before do
      60.times { |i| policy!("dev.task_requeue", scope: "agent", agent: create(:ai_agent, account: account, name: "L#{i}")) }
    end

    it "returns every account row by default, with a total that counts them all" do
      get "/api/v1/ai/intervention_policies", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response_data["policies"].size).to eq(60)
      expect(json_response_data["total_count"]).to eq(60)
    end

    it "ignores a limit that is not positive rather than handing it to the database" do
      %w[-1 0 abc].each do |limit|
        get "/api/v1/ai/intervention_policies", params: { limit: limit }, headers: auth_headers_for(operator)

        expect(response).to have_http_status(:ok)
        expect(json_response_data["policies"].size).to eq(60)
      end
    end

    it "pages only when asked, and still reports the true total" do
      get "/api/v1/ai/intervention_policies", params: { limit: 10 }, headers: auth_headers_for(operator)

      expect(json_response_data["policies"].size).to eq(10)
      expect(json_response_data["total_count"]).to eq(60)
    end
  end

  describe "PATCH bulk" do
    def bulk(updates, hdrs = headers)
      patch "/api/v1/ai/intervention_policies/bulk", params: { updates: updates }.to_json, headers: hdrs
    end

    it "returns 403 without the permission and 400 without an updates array" do
      bulk([ { action_category: "dev.task_requeue", policy: "block" } ], headers(no_perms))
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/ai/intervention_policies/bulk", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "upserts the addressed row and reports the count" do
      row = policy!("dev.task_requeue", scope: "agent", agent: agent, policy: "require_approval")

      bulk([ { action_category: "dev.task_requeue", policy: "block", scope: "agent", agent_id: agent.id } ])

      expect(response).to have_http_status(:ok)
      expect(json_response_data["changed"]).to eq(1)
      expect(row.reload.policy).to eq("block")
      expect(Ai::InterventionPolicy.where(account: account).count).to eq(1)
    end

    # The registry is the gate: a category nothing registers is a control for an
    # action nothing can execute. The batch keeps going, so the EFFECT is checked
    # per entry: the unknown one wrote nothing, its live sibling persisted.
    it "rejects an unregistered category without writing it, and still writes its sibling" do
      bulk([ { action_category: "dev.spec_never_registered", policy: "auto_approve" },
             { action_category: "dev.task_requeue", policy: "auto_approve" } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(Array(json_response.dig("details", "errors")).join(" "))
        .to include("unknown category dev.spec_never_registered")
      expect(Ai::InterventionPolicy.where(account: account, action_category: "dev.spec_never_registered")).to be_empty
      expect(Ai::InterventionPolicy.where(account: account, action_category: "dev.task_requeue")).to exist
    end

    it "rejects an invalid verb" do
      bulk([ { action_category: "dev.task_requeue", policy: "yolo" } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(Ai::InterventionPolicy.where(account: account)).to be_empty
    end

    # IMP-bef43160636f: an ABSENT key means "leave it alone". A control edits the
    # verb only, so every other operator-meaningful column must survive a save.
    context "with keys the payload omits" do
      let!(:chain) { create(:ai_approval_chain, account: account) }
      let!(:tuned) do
        policy!("dev.task_requeue", scope: "agent", agent: agent, policy: "require_approval",
                                    priority: 42, is_active: false, preferred_channels: %w[slack],
                                    conditions: { "trust_tier_minimum" => "trusted" }, approval_chain_id: chain.id)
      end

      it "changes the verb and nothing else on the row" do
        before_attrs = tuned.attributes.except("updated_at")

        bulk([ { action_category: "dev.task_requeue", policy: "block", scope: "agent", agent_id: agent.id } ])
        expect(response).to have_http_status(:ok)

        after_attrs = tuned.reload.attributes.except("updated_at")
        moved = before_attrs.reject { |col, was| after_attrs[col] == was }.keys
        expect(moved).to eq([ "policy" ])
        expect(tuned.approval_chain_id).to eq(chain.id)
        expect(tuned.priority).to eq(42)
      end

      it "still writes them when present, and a present nil chain unassigns it" do
        bulk([ { action_category: "dev.task_requeue", policy: "block", scope: "agent", agent_id: agent.id,
                 priority: 7, is_active: true, preferred_channels: %w[email], approval_chain_id: nil } ])
        expect(response).to have_http_status(:ok)

        tuned.reload
        expect([ tuned.priority, tuned.is_active, tuned.preferred_channels, tuned.approval_chain_id ])
          .to eq([ 7, true, %w[email], nil ])
      end

      it "applies the defaults to a row it creates" do
        bulk([ { action_category: "dev.multi_file_change", policy: "block", scope: "agent", agent_id: agent.id } ])
        expect(response).to have_http_status(:ok)

        created = Ai::InterventionPolicy.find_by!(account: account, action_category: "dev.multi_file_change",
                                                  scope: "agent", ai_agent_id: agent.id)
        expect([ created.priority, created.is_active, created.preferred_channels, created.approval_chain_id ])
          .to eq([ 10, true, %w[notification], nil ])
      end
    end

    # IMP-03134d9452d2: a write that could lift the person-session mark needs a
    # person's own session. Refused per entry; nothing is written for it.
    context "with the person-session mark" do
      let(:mark) { Ai::Approvals::HumanSessionPolicy::CONDITION_KEY }

      def impersonation_headers
        admin = create(:user, :admin, account: account)
        session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: operator)
        payload = { type: "impersonation", session_id: session.id, sub: operator.id, account_id: operator.account_id,
                    version: Security::JwtService::CURRENT_TOKEN_VERSION }
        { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
      end

      it "refuses an impersonation session's entry that unmarks, writing nothing for it" do
        bulk([ { action_category: "dev.task_requeue", scope: "global", policy: "require_approval",
                 conditions: { mark => false } } ], impersonation_headers)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("own session")
        expect(Ai::InterventionPolicy.where(account: account)).to be_empty
      end

      it "refuses an impersonation session changing a marked row, and leaves it as it was" do
        row = policy!("dev.task_requeue", policy: "require_approval", conditions: { mark => true })

        bulk([ { action_category: "dev.task_requeue", scope: "global", policy: "auto_approve" } ],
             impersonation_headers)

        expect(response).to have_http_status(:unprocessable_content)
        expect(row.reload.policy).to eq("require_approval")
      end

      it "still writes an impersonation session's entry whose row carries no mark" do
        bulk([ { action_category: "dev.task_requeue", scope: "global", policy: "notify_and_proceed" } ],
             impersonation_headers)

        expect(response).to have_http_status(:ok)
        expect(Ai::InterventionPolicy.find_by(account: account, action_category: "dev.task_requeue").policy)
          .to eq("notify_and_proceed")
      end

      # Positive control: the person's own session may lift it.
      it "lets the person's own session write the mark false" do
        row = policy!("dev.task_requeue", policy: "require_approval", conditions: { mark => true })

        bulk([ { action_category: "dev.task_requeue", scope: "global", policy: "require_approval",
                 conditions: { mark => false } } ])

        expect(response).to have_http_status(:ok)
        expect(row.reload.conditions[mark]).to be(false)
      end
    end
  end
end

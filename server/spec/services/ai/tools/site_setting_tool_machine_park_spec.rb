# frozen_string_literal: true

require "rails_helper"

# Act-on-behalf: an INSTANCE principal (an operator's Claude Code session
# reaching the hub with a node grant) may REQUEST a protected setting change
# and can never decide or run it. It parks; a person decides in their own REST
# session; the write then runs AS that person.
#
# Every example asserts the row (the setting, the request) as well as the
# envelope: a refusal that writes anyway passes an envelope-shaped assertion.
RSpec.describe Ai::Tools::SiteSettingTool, "instance principal parks a protected write" do
  let(:account) { create(:account) }
  let!(:operator) { create(:user, account: account, permissions: [ "admin.access", "ai.autonomy.approve" ]) }
  let(:node_instance) { double("NodeInstance", id: "bb11cc22-0000-4000-8000-000000000002", account: account) }
  let(:granted) { [ "platform.site_setting_set_protected" ] }
  let(:protected_key) { "zz_machine_park_protected_key" }
  let(:session_id) { "mcp-session-under-test" }

  before do
    described_class.register_key(protected_key, setting_type: "string", description: "machine park spec key",
                                                protected: true, machine_parkable: true)
    Rails.cache.clear
    ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
    ::Mcp::Principal.tool_grant_resolver = ->(_instance) { granted }
  end

  after { ::Mcp::Principal.reset! }

  def instance_tool(label: nil, internal: false)
    tool = described_class.new(account: account, internal: internal)
    tool.instance_authorized = true
    tool.node_instance = node_instance
    tool.call_origin = "mcp_instance"
    tool.session_label = label if label
    tool
  end

  def last_refusal_reason
    AuditLog.where(action: "ai.approvals.machine_park_refused").order(:created_at).last&.metadata&.fetch("reason", nil)
  end

  def park(key: protected_key, value: "armed", tool: instance_tool)
    tool.execute(params: { action: "site_setting_set_protected", key: key, value: value })
  end

  def workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)

  def parked_request(result)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true, requires_human_session: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  describe "the park hook" do
    it "parks for an instance whose grant names the tool, writing nothing" do
      request = parked_request(park)

      expect(request.requires_human_session?).to be(true)
      expect(request.machine_requested?).to be(true)
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "records who asked (the instance) and an opaque session label, never the raw session id" do
      label = Digest::SHA256.hexdigest("mcp-session-label:#{session_id}")[0, 16]
      request = parked_request(park(tool: instance_tool(label: label)))

      principal = request.request_data.dig("params", "principal")
      expect(principal).to include("kind" => "instance", "node_instance_id" => node_instance.id,
                                   "session_label" => label)
      expect(request.request_data.to_json).not_to include(session_id)
    end

    it "carries the label from the MCP door through the registrar onto the parked request" do
      result = Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.site_setting_set_protected", params: { key: protected_key, value: "armed" }, account: account,
        instance_authorized: true, node_instance: node_instance, origin: "mcp_instance", session_label: "abc123"
      )

      expect(parked_request(result).request_data.dig("params", "principal", "session_label")).to eq("abc123")
    end

    it "never lets the label authorize: a different label parks and dedupes exactly as none" do
      first = parked_request(park(tool: instance_tool(label: "aaaa")))
      again = park(tool: instance_tool(label: "bbbb"))

      expect(again[:data]).to include(deduplicated: true, approval_request_id: first.id)
    end

    it "refuses an instance whose grant does not cover the tool, and parks nothing" do
      ::Mcp::Principal.tool_grant_resolver = ->(_instance) { [ "platform.site_setting_get" ] }

      result = park

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("platform.site_setting_set_protected")
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(AuditLog.where(action: "ai.approvals.machine_park_refused").last.metadata)
        .to include("reason" => "grant_not_cleared", "node_instance_id" => node_instance.id)
    end

    it "refuses a glob grant that merely covers the tool: the grant must name it" do
      [ "platform.*", "platform.site_setting_*", "platform.site_setting_set*", "platform.site_setting_{get,set_protected}" ]
        .each do |pattern|
        Rails.cache.clear
        ::Mcp::Principal.tool_grant_resolver = ->(_instance) { [ pattern ] }

        result = park

        expect(result[:success]).to be(false), "#{pattern} parked: #{result.inspect}"
        expect(last_refusal_reason).to eq("grant_not_cleared")
      end
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "parks when the exact name is granted alongside a broad glob" do
      ::Mcp::Principal.tool_grant_resolver = ->(_instance) { [ "platform.*", "platform.site_setting_set_protected" ] }

      expect(parked_request(park)).to be_pending
    end

    it "refuses an instance carrying no node instance" do
      tool = described_class.new(account: account)
      tool.instance_authorized = true

      expect(park(tool: tool)[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(last_refusal_reason).to eq("no_node_instance")
    end

    it "refuses a tool carrying a node instance but not authorized as an instance" do
      tool = described_class.new(account: account)
      tool.node_instance = node_instance

      expect(park(tool: tool)[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(last_refusal_reason).to eq("not_instance")
    end

    it "refuses an in-process internal caller, instance or not" do
      result = described_class.new(account: account, internal: true)
                              .execute(params: { action: "site_setting_set_protected", key: protected_key, value: "x" })

      expect(result[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "refuses an internal caller that is also an authenticated instance, by reason code" do
      tool = instance_tool(internal: true)

      expect(park(tool: tool)[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(last_refusal_reason).to eq("internal_caller")
    end

    it "still refuses an unregistered key and an ordinary key, so the park cannot launder a plain write" do
      described_class.register_key("zz_machine_park_plain", setting_type: "string", description: "plain")

      expect(park(key: "zz_not_registered")[:success]).to be(false)
      expect(last_refusal_reason).to eq("key_refused")
      Rails.cache.clear
      expect(park(key: "zz_machine_park_plain")[:success]).to be(false)
      expect(last_refusal_reason).to eq("key_refused")
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "refuses a protected key its owner did not register machine-parkable, so it stays person-initiated" do
      described_class.register_key("zz_person_only_protected", setting_type: "string", description: "person only",
                                                               protected: true)

      result = park(key: "zz_person_only_protected")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("only a person may initiate")
      expect(last_refusal_reason).to eq("key_not_machine_parkable")
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "leaves the human-session category list and the self-hosting node id person-initiated only" do
      person_only = [ Ai::Approvals::HumanSessionPolicy::SETTING_KEY, "self_hosting_node_id" ]
        .select { |key| described_class.operator_configurable_keys.key?(key) }
      expect(person_only).to include(Ai::Approvals::HumanSessionPolicy::SETTING_KEY)

      person_only.each do |key|
        Rails.cache.clear
        result = park(key: key, value: "[]")

        expect(result[:success]).to be(false), "#{key} parked: #{result.inspect}"
        expect(last_refusal_reason).to eq("key_not_machine_parkable")
      end
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "registers exactly the dev-merge names and the ssh host-key switch as machine-parkable, of the real keys" do
      parkable = described_class.operator_configurable_keys.select { |name, spec| spec[:machine_parkable] && !name.start_with?("zz_") }.keys

      expect(parkable - [ "dev_merge.private_extension_names", "system.ssh.require_host_key" ]).to be_empty
      expect(parkable).to include("dev_merge.private_extension_names")
    end

    it "records neither caller text nor an unregistered key's name in the refusal audit, and collapses repeats" do
      long_key = "zz_#{'k' * 5_000}"

      3.times { park(key: long_key) }

      rows = AuditLog.where(action: "ai.approvals.machine_park_refused")
      expect(rows.count).to eq(1)
      expect(rows.first.metadata).to include("setting_key" => "unregistered", "reason" => "key_refused")
      expect(rows.first.metadata.to_json.length).to be < 1_000
    end

    it "refuses a value its registered check rejects, before it can park" do
      SiteSetting.register_value_check(protected_key) { |value| value == "bad" ? "not allowed" : nil }

      expect(park(value: "bad")[:success]).to be(false)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(AuditLog.where(action: "ai.approvals.machine_park_refused").last.metadata.to_json).not_to include("bad")
    ensure
      SiteSetting.value_checks.delete(protected_key)
    end

    it "does not admit an instance to the ordinary or the read verb" do
      %w[site_setting_set site_setting_get].each do |action|
        result = instance_tool.execute(params: { action: action, key: protected_key, value: "x" })
        expect(result[:success]).to be(false), "#{action}: #{result.inspect}"
      end
      expect(Ai::ApprovalRequest.count).to eq(0)
    end
  end

  describe "the instance can never reach the write" do
    it "cannot approve or reject its own parked request through the approval workflow" do
      request = parked_request(park)

      %w[mcp_instance mcp_oauth agent_bridge].each do |origin|
        expect(workflow.approve(request: request, approver: operator, origin: origin)).to be(false)
        expect(workflow.reject(request: request, approver: operator, origin: origin)).to be(false)
      end
      expect(request.reload).to be_pending
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "cannot run the write by replaying an approved request as itself" do
      request = parked_request(park)
      operation = Ai::DeferredOperation.find(request.source_id)
      expect(workflow.approve(request: request, approver: operator,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)
      SiteSetting.where(key: protected_key).delete_all
      # The one status in which a replay is honoured (the approval's own run is over).
      operation.update_column(:status, "executing")

      tool = instance_tool
      tool.replaying_operation = operation
      result = tool.execute(params: { action: "site_setting_set_protected", key: protected_key, value: "again" })

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("denied to instance principals")
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "cannot use a decided operation as a licence: it only parks afresh, and writes nothing" do
      request = parked_request(park)
      operation = Ai::DeferredOperation.find(request.source_id)
      workflow.approve(request: request, approver: operator, origin: Ai::ApprovalDecision::REST_SESSION)
      SiteSetting.where(key: protected_key).delete_all

      tool = instance_tool
      tool.replaying_operation = operation
      again = parked_request(tool.execute(params: { action: "site_setting_set_protected", key: protected_key,
                                                    value: "again" }))

      expect(again.id).not_to eq(request.id)
      expect(again).to be_pending
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "keeps the run-time authorization refusing every instance" do
      result = instance_tool.send(:authorization_error, { action: "site_setting_set_protected", key: protected_key,
                                                          value: "x" })

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("denied to instance principals")
    end
  end

  describe "the replay" do
    it "writes only on a person's own-session approval, and runs AS that person" do
      request = parked_request(park(value: "armed"))

      expect(workflow.approve(request: request, approver: operator, origin: "mcp_oauth")).to be(false)
      expect(SiteSetting.find_by(key: protected_key)).to be_nil

      expect(workflow.approve(request: request, approver: operator,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(true)

      expect(SiteSetting.get(protected_key)).to eq("armed")
      expect(AuditLog.where(action: "update_site_setting").last.user_id).to eq(operator.id)
      expect(request.reload.confirming_approver).to eq(operator)
    end

    it "refuses the replay when the deciding person lacks admin.access, leaving the request pending" do
      weak = create(:user, account: account, permissions: [ "ai.autonomy.approve" ])
      request = parked_request(park)

      expect(workflow.approve(request: request, approver: weak,
                              origin: Ai::ApprovalDecision::REST_SESSION)).to be(false)
      expect(request.reload).to be_pending
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end
  end

  describe "dedupe and rate limit (Ai::Approvals::MachinePark)" do
    it "returns the existing pending request for a duplicate park, case-insensitively" do
      first = parked_request(park(value: "one"))

      second_result = park(value: "two")

      expect(second_result[:data]).to include(pending: true, deduplicated: true,
                                              approval_request_id: first.id)
      expect(Ai::ApprovalRequest.count).to eq(1)
      expect(AuditLog.where(action: "ai.approvals.machine_park_deduped").count).to eq(1)
    end

    it "parks again once the earlier request has been decided" do
      first = parked_request(park)
      workflow.reject(request: first, approver: operator, origin: Ai::ApprovalDecision::REST_SESSION)

      second = parked_request(park)

      expect(second.id).not_to eq(first.id)
    end

    it "keys the dedupe on the principal: another instance parks its own request" do
      other = double("NodeInstance", id: "cc11dd22-0000-4000-8000-000000000003", account: account)
      ::Mcp::Principal.instance_resolver = ->(cn) { [ node_instance, other ].find { |n| n.id == cn } }
      parked_request(park)

      tool = described_class.new(account: account)
      tool.instance_authorized = true
      tool.node_instance = other
      tool.call_origin = "mcp_instance"

      expect(parked_request(park(tool: tool)).id).to be_present
      expect(Ai::ApprovalRequest.count).to eq(2)
    end

    it "refuses a park over the per-principal limit and audits it" do
      SiteSetting.set(Ai::Approvals::MachinePark::RATE_LIMIT_SETTING, 2, setting_type: "integer")
      2.times do |i|
        described_class.register_key("#{protected_key}_#{i}", setting_type: "string", description: "k", protected: true,
                                                                   machine_parkable: true)
        parked_request(park(key: "#{protected_key}_#{i}"))
      end
      described_class.register_key("#{protected_key}_over", setting_type: "string", description: "k", protected: true,
                                                                  machine_parkable: true)

      result = park(key: "#{protected_key}_over")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("limit 2")
      expect(Ai::ApprovalRequest.count).to eq(2)
      expect(AuditLog.where(action: "ai.approvals.machine_park_rate_limited").count).to eq(1)
    end

    it "falls back to the named default when the setting is unset or not a positive number" do
      expect(Ai::Approvals::MachinePark.rate_limit).to eq(Ai::Approvals::MachinePark::DEFAULT_RATE_LIMIT)
      SiteSetting.set(Ai::Approvals::MachinePark::RATE_LIMIT_SETTING, "0", setting_type: "integer")
      expect(Ai::Approvals::MachinePark.rate_limit).to eq(Ai::Approvals::MachinePark::DEFAULT_RATE_LIMIT)
    end
  end

  describe "other human-only verbs an instance parks are untouched" do
    let(:other_tool_class) do
      klass = Class.new(::Ai::Tools::BaseTool) do
        def self.definition
          { name: "spec_other_human_tool", description: "human-only probe",
            parameters: { action: { type: "string", required: false } } }
        end

        declare_action "spec_other_human_write", mutating: true, human_only: true,
                                                 action_category: "spec.other.human",
                                                 executor_class: "Ai::Executors::DeferredToolCall",
                                                 gate_context: :deferred_tool_call_context,
                                                 on_proceed: :deferred_tool_call_result
        define_method(:call) { |_params| success_result(ran: true) }
      end
      klass.const_set(:REQUIRED_PERMISSION, nil)
      stub_const("SpecOtherHumanTool", klass)
    end

    before do
      Ai::InterventionPolicy.register_category!("spec.other.human")
      ::Mcp::Principal.tool_grant_resolver = lambda { |_instance|
        [ "platform.spec_other_human_write", "platform.site_setting_set_protected" ]
      }
    end

    it "takes no lock, dedupe or limit: the same instance parks it past the limit, twice over" do
      SiteSetting.set(Ai::Approvals::MachinePark::RATE_LIMIT_SETTING, 2, setting_type: "integer")
      allow(Ai::Approvals::MachinePark).to receive(:guard).and_call_original

      requests = Array.new(4) do
        tool = other_tool_class.new(account: account)
        tool.instance_authorized = true
        tool.node_instance = node_instance
        tool.call_origin = "mcp_instance"
        parked_request(tool.execute(params: { action: "spec_other_human_write" }))
      end

      expect(requests.map(&:id).uniq.size).to eq(4)
      expect(Ai::Approvals::MachinePark).not_to have_received(:guard)
      expect(AuditLog.where(action: %w[ai.approvals.machine_park_deduped ai.approvals.machine_park_rate_limited])).to be_empty
    end

    it "does not spend the protected-setting budget: the limit counts per action category" do
      SiteSetting.set(Ai::Approvals::MachinePark::RATE_LIMIT_SETTING, 1, setting_type: "integer")
      tool = other_tool_class.new(account: account)
      tool.instance_authorized = true
      tool.node_instance = node_instance
      tool.call_origin = "mcp_instance"
      parked_request(tool.execute(params: { action: "spec_other_human_write" }))

      expect(parked_request(park)).to be_pending
    end
  end

  describe "the notification" do
    it "opens the approvals queue for a request an instance parked, and carries no value" do
      request = parked_request(park(value: "s3cret-looking-value"))

      note = Notification.where(user: operator).order(:created_at).last

      expect(note.action_url).to eq("/app/ai/control/approvals/queue?request=#{request.id}")
      expect([ note.title, note.message, request.description ].join(" ")).not_to include("s3cret-looking-value")
    end
  end

  describe "the approval card" do
    it "shows the tool, key, new value and (to an admin.access holder) the current value" do
      SiteSetting.set(protected_key, "old-value")
      request = parked_request(park(value: "new-value"))

      card = Ai::Approvals::ChangeCard.for(request, viewer: operator)

      expect(card).to include(tool: "site_setting", action: "site_setting_set_protected", key: protected_key,
                              new_value: "new-value", current_value: "old-value", current_value_set: true)
    end

    it "withholds the current value from a viewer who could not read it on the REST API" do
      SiteSetting.set(protected_key, "old-value")
      request = parked_request(park(value: "new-value"))
      reader = create(:user, account: account, permissions: [ "ai.agents.read" ])

      card = Ai::Approvals::ChangeCard.for(request, viewer: reader)

      expect(card).to include(key: protected_key, new_value: "new-value")
      expect(card).not_to have_key(:current_value)
    end
  end
end

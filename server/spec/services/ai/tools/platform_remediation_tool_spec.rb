# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PlatformRemediationTool do
  let(:tool_class) { described_class }
  let(:account) { create(:account) }
  let(:cs) { Platform::ComponentStatus }

  # The first user in an account is given the OWNER role, so every actor here
  # declares its permissions explicitly (spec/factories/users.rb).
  let(:owner) { create(:user, account: account) }
  let(:reader) { create(:user, account: account, permissions: %w[ai_monitoring.read]) }
  let(:requester) { create(:user, account: account, permissions: %w[ai_monitoring.read ai.autonomy.manage]) }
  let(:nobody) { create(:user, account: account, permissions: []) }

  let(:component) do
    create(:platform_component_status, account: account,
                                       component_kind: "node_instance", component_ref: "inst-1",
                                       display_name: "Instance 1", verdict: cs::DOWN)
  end

  before do
    owner # ensure the OWNER role is claimed before the explicit-permission users are made
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  after do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  def tool(user:)
    tool_class.new(account: account, user: user)
  end

  def register_lane(kind, report)
    lane = Object.new
    lane.define_singleton_method(:key) { "fleet_autonomy" }
    lane.define_singleton_method(:describe) { |_c, _k, account: nil| report }
    Platform::Remediation::Registry.register_lane(kind, lane)
  end

  # ── Declarations ────────────────────────────────────────────────────────
  #
  # BaseTool#execute takes the UNDECLARED path — a bare `return call(params)`
  # plus one telemetry row — for any action with no declaration. That is the
  # "fails open" hazard, and it is closed here by every public action being
  # declared, asserted by set EQUALITY rather than by existence.
  describe "action declarations" do
    it "declares every action it advertises, and advertises every action it declares" do
      advertised = tool_class.action_definitions.keys.to_set
      declared = tool_class.declared_actions.keys.to_set
      registered = Ai::Tools::PlatformApiToolRegistry::TOOLS
                     .select { |_name, klass| klass == tool_class.name }.keys.to_set

      expect(declared).to eq(advertised)
      expect(registered).to eq(advertised)
    end

    it "declares the two reads non-mutating and request_approval mutating" do
      expect(tool_class.declared_action("get_remediation_route")[:mutating]).to be false
      expect(tool_class.declared_action("get_runbook")[:mutating]).to be false
      expect(tool_class.declared_action("request_approval")[:mutating]).to be true
    end

    it "gives request_approval the approval action category, which the platform already seeds" do
      declaration = tool_class.declared_action("request_approval")

      expect(declaration[:action_category]).to eq("approval")
      expect(Ai::InterventionPolicy.category_registered?("approval")).to be true
    end

    # Design §5.1: there is no respond_to_approval verb. Answering an approval
    # stays operator-side; an agent that can answer its own approvals has
    # closed the loop on itself.
    it "offers no verb that answers an approval" do
      expect(tool_class.declared_actions.keys)
        .to all(satisfy { |name| !name.match?(/respond|approve|reject|decide/) })
    end

    # BootstrapVerbs is served to every agent whatever its tool_families
    # scope, and is read-only by contract.
    it "keeps all three actions out of BootstrapVerbs" do
      tool_class.declared_actions.each_key do |action|
        expect(Ai::Tools::BootstrapVerbs.include?(action)).to be(false), "#{action} is a bootstrap verb"
      end
    end

    # The readOnlyHint annotation is derived from the action NAME, so the
    # names are what make it true. Asserted against the catalog's own
    # predicate, not against a copy of its prefix list — a re-implementation
    # would share whatever blind spot the original has.
    #
    # Both arms: the write must NOT be hinted read-only. A predicate that
    # answered true for everything would look like a pass on the reads alone.
    it "names the reads so Mcp::ToolCatalog annotates them readOnlyHint" do
      catalog = Mcp::ToolCatalog.new(protocol_version: "2025-06-18")

      expect(catalog.send(:read_only_action?, "get_remediation_route")).to be true
      expect(catalog.send(:read_only_action?, "get_runbook")).to be true
      expect(catalog.send(:read_only_action?, "request_approval")).to be false
    end
  end

  # ── get_remediation_route ───────────────────────────────────────────────
  describe "get_remediation_route" do
    it "returns not_actuatable with the runbook when nothing claims the kind" do
      Platform::Runbook::Registry.register("instance.silent", doc: "docs/runbooks/silent.md#triage")

      result = tool(user: reader).execute(params: {
        action: "get_remediation_route", component_kind: "node_instance",
        component_ref: "inst-1", signal_kind: "instance.silent"
      }.tap { component })

      expect(result[:success]).to be true
      expect(result[:data][:route][:state]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:data][:route][:reason]).to eq(Platform::RemediationRouter::NO_LANE)
      expect(result[:data][:route][:runbook]).to include(kind: "doc")
    end

    it "reports the lane's own refusal verbatim" do
      component
      register_lane("instance.silent",
                    state: cs::REMEDIATION_NOT_ACTUATABLE, can_proceed: false,
                    reason: "INV-1: refusing to remediate the instance hosting this control plane")

      result = tool(user: reader).execute(params: {
        action: "get_remediation_route", component_kind: "node_instance",
        component_ref: "inst-1", signal_kind: "instance.silent"
      })

      expect(result[:data][:route][:reason]).to start_with("INV-1:")
    end

    it "errors on a component it cannot find" do
      result = tool(user: reader).execute(params: {
        action: "get_remediation_route", component_kind: "node_instance",
        component_ref: "nope", signal_kind: "instance.silent"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/No component status/)
    end

    it "refuses a caller without the read floor" do
      component
      result = tool(user: nobody).execute(params: {
        action: "get_remediation_route", component_kind: "node_instance",
        component_ref: "inst-1", signal_kind: "instance.silent"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/permission denied: ai_monitoring.read/)
    end
  end

  describe "get_runbook" do
    it "renders a bound runbook" do
      Platform::Runbook::Registry.register("a.kind", doc: "docs/runbooks/a.md#top")

      result = tool(user: reader).execute(params: { action: "get_runbook", signal_kind: "a.kind" })

      expect(result[:data][:runbook]).to include(kind: "doc", path: "docs/runbooks/a.md", anchor: "top")
    end

    it "says an unregistered kind is not known" do
      result = tool(user: reader).execute(params: { action: "get_runbook", signal_kind: "never.seen" })

      expect(result[:data][:runbook]).to eq(kind: "none", known: false, reason: "NotRegistered")
    end

    it "requires a signal kind" do
      expect(tool(user: reader).execute(params: { action: "get_runbook" })[:success]).to be false
    end
  end

  # ── request_approval ────────────────────────────────────────────────────
  describe "request_approval" do
    let(:params) do
      { action: "request_approval", component_kind: "node_instance", component_ref: "inst-1",
        signal_kind: "instance.silent", rationale: "the instance has been silent for 20 minutes" }
    end

    before do
      component
      register_lane("instance.silent",
                    state: cs::REMEDIATION_AWAITING_OPERATOR, can_proceed: false,
                    policy: "require_approval", reason: "ConsentBudgetExhausted")
    end

    it "creates exactly one pending approval request and returns its id" do
      expect { @result = tool(user: requester).execute(params: params) }
        .to change { Ai::ApprovalRequest.where(account_id: account.id).count }.by(1)

      request = Ai::ApprovalRequest.find(@result[:data][:approval_request_id])
      expect(@result[:success]).to be true
      expect(@result[:data][:status]).to eq("pending")
      expect(@result[:data][:deduplicated]).to be false
      expect(request.source_type).to eq("Platform::ComponentStatus")
      expect(request.source_id).to eq(component.id)
      expect(request.requested_by_id).to eq(requester.id)
    end

    # The card is read by an audience wider than the permission that made it,
    # so it carries the lane's own words rather than a paraphrase.
    it "carries the routed lane's report onto the card" do
      result = tool(user: requester).execute(params: params)
      request = Ai::ApprovalRequest.find(result[:data][:approval_request_id])

      expect(request.request_data["signal_kind"]).to eq("instance.silent")
      expect(request.request_data["lane_key"]).to eq("fleet_autonomy")
      expect(request.request_data["reason"]).to eq("ConsentBudgetExhausted")
      expect(request.request_data["can_proceed"]).to be false
      expect(request.request_data["component_ref"]).to eq("inst-1")
    end

    describe "dedupe" do
      it "returns the live request instead of minting a second card" do
        first = tool(user: requester).execute(params: params)

        expect { @second = tool(user: requester).execute(params: params) }
          .not_to change { Ai::ApprovalRequest.where(account_id: account.id).count }

        expect(@second[:data][:deduplicated]).to be true
        expect(@second[:data][:approval_request_id]).to eq(first[:data][:approval_request_id])
      end

      # The other arm: a genuinely new occurrence carries a new fingerprint
      # and does get its own card. Without this the dedupe could be a
      # "never create twice" bug and look identical.
      it "mints a second card for a different fingerprint" do
        tool(user: requester).execute(params: params.merge(fingerprint: "occurrence-1"))

        expect { tool(user: requester).execute(params: params.merge(fingerprint: "occurrence-2")) }
          .to change { Ai::ApprovalRequest.where(account_id: account.id).count }.by(1)
      end

      it "mints a second card for a different signal kind" do
        tool(user: requester).execute(params: params)

        expect { tool(user: requester).execute(params: params.merge(signal_kind: "instance.disk_full")) }
          .to change { Ai::ApprovalRequest.where(account_id: account.id).count }.by(1)
      end

      # A request past expires_at is answered by the hourly expiry sweep, not
      # at read time, so it lingers in `pending` after it stopped being live.
      # Deduping against those would swallow a fresh request for up to an hour.
      it "does not dedupe against a request that has expired" do
        first = tool(user: requester).execute(params: params)
        Ai::ApprovalRequest.find(first[:data][:approval_request_id])
                           .update_column(:expires_at, 1.hour.ago)

        expect { tool(user: requester).execute(params: params) }
          .to change { Ai::ApprovalRequest.where(account_id: account.id).count }.by(1)
      end
    end

    describe "authorization" do
      it "refuses a caller holding only the read floor" do
        expect { @result = tool(user: reader).execute(params: params) }
          .not_to change { Ai::ApprovalRequest.where(account_id: account.id).count }

        expect(@result[:success]).to be false
        expect(@result[:error]).to match(/permission denied: ai.autonomy.manage/)
      end

      it "allows a caller holding ai.autonomy.manage" do
        expect(tool(user: requester).execute(params: params)[:success]).to be true
      end

      # Requesting is not answering. The permission to answer must not be the
      # one this verb charges, or holding it would imply the other.
      it "does not accept ai.autonomy.approve in place of the write permission" do
        approver = create(:user, account: account,
                                 permissions: %w[ai_monitoring.read ai.autonomy.approve])

        expect(tool(user: approver).execute(params: params)[:success]).to be false
      end
    end

    it "requires a rationale" do
      result = tool(user: requester).execute(params: params.merge(rationale: "   "))

      expect(result[:success]).to be false
      expect(result[:error]).to match(/rationale is required/)
    end

    # Core never constructs a proceed: the approval reaches a person and
    # nothing else happens.
    it "never calls the lane's proceed!" do
      lane = instance_double("Lane", key: "spy_lane")
      allow(lane).to receive(:describe).and_return(state: cs::REMEDIATION_AWAITING_OPERATOR, can_proceed: false)
      allow(lane).to receive(:proceed!)
      Platform::Remediation::Registry.register_lane("instance.silent", lane)

      tool(user: requester).execute(params: params)

      expect(lane).not_to have_received(:proceed!)
    end
  end

  describe "an unknown action" do
    it "is refused rather than dispatched" do
      result = tool(user: requester).execute(params: { action: "delete_everything" })

      expect(result[:success]).to be false
    end
  end
end

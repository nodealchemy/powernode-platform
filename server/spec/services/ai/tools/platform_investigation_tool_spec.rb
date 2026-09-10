# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — the operator's door onto the
# investigation (design §5.3).
RSpec.describe Ai::Tools::PlatformInvestigationTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ "platform.status.read", "ai.autonomy.manage" ]) }
  let(:tool) { described_class.new(account: account, user: user) }

  let!(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: Platform::ComponentStatus::DOWN,
                                       conditions: [ { "type" => "Connected", "status" => false,
                                                       "reason" => "ConnectionError", "severity" => "down" } ])
  end

  def exec(params)
    tool.execute(params: params.with_indifferent_access)
  end

  # The verb existing, declared and gated is not the verb being CALLABLE. A tool
  # class with no registry entry passes every declaration lint in this suite and
  # is still unreachable over MCP — the "exists, passes review, never executed"
  # shape. Resolved by execution through the registry, not by reading it.
  describe "advertisement" do
    it "resolves every declared action through the registry to this class" do
      described_class.declared_actions.each_key do |action|
        expect(Ai::Tools::PlatformApiToolRegistry.find_tool(action)).to eq(described_class),
                                                                       "#{action} does not resolve to this tool"
      end
    end

    # The other arm: `find_tool` returns nil rather than a default, so the
    # assertion above cannot pass by the registry answering something for
    # everything.
    it "resolves nothing for a name nobody registered" do
      expect(Ai::Tools::PlatformApiToolRegistry.find_tool("platform_uninvestigate")).to be_nil
    end
  end

  describe "declaration" do
    it "declares exactly one mutating verb and two reads" do
      declared = described_class.declared_actions

      expect(declared.keys).to contain_exactly("platform_investigate", "get_investigation", "get_investigations")
      expect(declared["platform_investigate"][:mutating]).to be(true)
      expect(declared["get_investigation"][:mutating]).to be(false)
      expect(declared["get_investigations"][:mutating]).to be(false)
    end

    it "documents every declared action" do
      expect(described_class.action_definitions.keys).to match_array(described_class.declared_actions.keys)
    end

    # The umbrella schema validates for EVERY action on the class, so a
    # component parameter marked required there would make the no-component
    # listing verb raise before it ran.
    it "marks only `action` required on the umbrella schema" do
      required = described_class.definition[:parameters].select { |_k, v| v[:required] }.keys

      expect(required).to eq([ :action ])
    end
  end

  describe "platform_investigate" do
    it "opens an investigation and returns it with its evidence recorded" do
      result = exec(action: "platform_investigate", component_kind: "docker_host", component_ref: "host-1")

      expect(result[:success]).to be true
      expect(result[:data][:opened]).to be(true)
      expect(result[:data][:investigation][:trigger]).to eq("operator")
      expect(result[:data][:investigation][:status]).to eq("open")
      expect(result[:data][:component][:display_name]).to eq("web-1")
      expect(Platform::Investigation.count).to eq(1)
    end

    # It opens; it does not conclude. Ranking is an LLM call and belongs in the
    # worker, so an open investigation with no hypotheses is the correct
    # product of this verb, not an incomplete one.
    it "returns before ranking, with no hypotheses" do
      exec(action: "platform_investigate", component_kind: "docker_host", component_ref: "host-1")

      expect(Platform::Investigation.first.hypotheses).to eq([])
      expect(Platform::Investigation.first.evidence["conditions"]).to be_present
    end

    it "reports the bound it hit rather than opening a second one" do
      exec(action: "platform_investigate", component_kind: "docker_host", component_ref: "host-1")

      result = exec(action: "platform_investigate", component_kind: "docker_host", component_ref: "host-1")

      expect(result[:success]).to be true
      expect(result[:data][:opened]).to be(false)
      expect(result[:data][:refused]).to eq(Platform::InvestigationService::REFUSED_ALREADY_OPEN)
      expect(result[:data][:daily_cap]).to eq(Platform::InvestigationService.daily_cap)
      expect(Platform::Investigation.count).to eq(1)
    end

    it "requires both halves of the component name" do
      expect(exec(action: "platform_investigate", component_kind: "docker_host")[:success]).to be false
      expect(exec(action: "platform_investigate", component_ref: "host-1")[:success]).to be false
    end

    it "refuses a component this account cannot see" do
      create(:platform_component_status, account: create(:account), component_kind: "docker_host",
                                         component_ref: "someone-elses")

      result = exec(action: "platform_investigate", component_kind: "docker_host", component_ref: "someone-elses")

      expect(result[:success]).to be false
      expect(result[:error]).to include("No component status")
      expect(Platform::Investigation.count).to eq(0)
    end

    it "reaches a shared component, which has no tenant of its own" do
      create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                  component_ref: "breaker-1")

      result = exec(action: "platform_investigate", component_kind: "provider_circuit_breaker",
                    component_ref: "breaker-1")

      expect(result[:data][:opened]).to be(true)
      expect(result[:data][:component][:shared]).to be(true)
    end
  end

  describe "get_investigation" do
    let(:investigation) do
      Platform::InvestigationService.new(account: account).open!(component, trigger: "operator")[:investigation]
    end

    it "returns the full record including the assembled evidence" do
      result = exec(action: "get_investigation", investigation_id: investigation.id)

      expect(result[:success]).to be true
      expect(result[:data][:investigation][:id]).to eq(investigation.id)
      expect(result[:data][:investigation][:evidence]).to be_present
    end

    it "requires an id and reports one it cannot find" do
      expect(exec(action: "get_investigation")[:success]).to be false
      expect(exec(action: "get_investigation", investigation_id: SecureRandom.uuid)[:success]).to be false
    end

    it "does not return another account's investigation" do
      other_account = create(:account)
      other_component = create(:platform_component_status, account: other_account, component_kind: "docker_host",
                                                           component_ref: "theirs")
      theirs = Platform::InvestigationService.new(account: other_account)
                                             .open!(other_component, trigger: "operator")[:investigation]

      expect(exec(action: "get_investigation", investigation_id: theirs.id)[:success]).to be false
    end
  end

  describe "get_investigations" do
    before { investigation }

    let(:investigation) do
      Platform::InvestigationService.new(account: account).open!(component, trigger: "operator")[:investigation]
    end

    it "lists this account's investigations without their evidence" do
      result = exec(action: "get_investigations")

      expect(result[:data][:count]).to eq(1)
      expect(result[:data][:investigations].first).not_to have_key(:evidence)
    end

    it "filters by status and by component, both arms" do
      expect(exec(action: "get_investigations", status: "open")[:data][:count]).to eq(1)
      expect(exec(action: "get_investigations", status: "completed")[:data][:count]).to eq(0)
      expect(exec(action: "get_investigations", component_kind: "docker_host",
                  component_ref: "host-1")[:data][:count]).to eq(1)
      expect(exec(action: "get_investigations", component_kind: "kubernetes_cluster")[:data][:count]).to eq(0)
    end

    it "caps the page size at 100 however large a limit is asked for" do
      expect(exec(action: "get_investigations", limit: 5000)[:success]).to be true
    end
  end

  describe "permission gating" do
    # THE FLOOR. An operator who can see the component on the page can ask
    # about it; a different floor would give a visible component a verb that
    # refuses for no reason the operator can see.
    it "lets a reader read" do
      reader = create(:user, account: account, permissions: [ "platform.status.read" ])
      reading_tool = described_class.new(account: account, user: reader)

      expect(reading_tool.execute(params: { action: "get_investigations" }.with_indifferent_access)[:success])
        .to be true
    end

    # …but opening one spends money and creates a row somebody must dispose
    # of, so the write verb is priced above the read floor. A single gate for
    # the whole tool would have handed every reader the LLM call.
    it "refuses the write verb to a reader who holds only the floor" do
      reader = create(:user, account: account, permissions: [ "platform.status.read" ])
      reading_tool = described_class.new(account: account, user: reader)

      result = reading_tool.execute(
        params: { action: "platform_investigate", component_kind: "docker_host",
                  component_ref: "host-1" }.with_indifferent_access
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("ai.autonomy.manage")
      expect(Platform::Investigation.count).to eq(0)
    end

    it "refuses even the reads to a principal holding neither" do
      stranger = create(:user, account: account, permissions: [])
      stranger_tool = described_class.new(account: account, user: stranger)

      result = stranger_tool.execute(params: { action: "get_investigations" }.with_indifferent_access)

      expect(result[:success]).to be false
      expect(result[:error]).to include("platform.status.read")
    end

    # A principal that cannot answer the permission question is REFUSED, not
    # admitted. The "unless respond_to?" arm that would admit it fails open.
    it "refuses a principal that cannot answer the permission question" do
      faceless = described_class.new(account: account, user: Object.new)

      expect(faceless.execute(params: { action: "get_investigations" }.with_indifferent_access)[:success])
        .to be false
    end
  end

  it "names an unknown action rather than silently doing nothing" do
    result = exec(action: "platform_uninvestigate")

    expect(result[:success]).to be false
    expect(result[:error]).to include("Unknown action")
  end
end

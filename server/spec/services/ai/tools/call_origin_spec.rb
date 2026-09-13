# frozen_string_literal: true

require "rails_helper"

# The call_origin vocabulary, the MCP principal's mapping onto it, and the
# registrar threading it onto the tool (MCP identity plan §4.2-§4.3).
RSpec.describe "call_origin (MCP identity plan R3)" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # A tool whose only job is to report the origin it was built with.
  let(:probe_class) do
    Class.new(Ai::Tools::BaseTool) do
      def self.name = "CallOriginProbeTool"

      def self.definition
        { name: "call_origin_probe", description: "Reports its call_origin", parameters: {} }
      end

      protected

      def call(_params)
        success_result(origin: call_origin)
      end
    end
  end

  def run_probe(origin)
    Ai::Tools::McpPlatformToolRegistrar.run_guarded(
      probe_class, tool_id: "local.call_origin_probe", params: {}, account: account, user: user, origin: origin
    )
  end

  describe "the vocabulary" do
    it "names every tool door, and each is a machine's" do
      expect(Ai::Tools::CallOrigin::ALL).to contain_exactly(
        "mcp_oauth", "mcp_instance", "mcp_federation", "mcp_cable", "agent_bridge", "skill_recipe",
        "concierge", "a2a", "skill_executor", "system_service"
      )
      expect(Ai::Tools::CallOrigin::ALL).to all(satisfy { |o| Ai::Tools::CallOrigin.machine?(o) })
    end

    it "answers false for nil and for a value it does not define" do
      expect(Ai::Tools::CallOrigin.machine?(nil)).to be(false)
      expect(Ai::Tools::CallOrigin.machine?("rest_session")).to be(false)
    end
  end

  # A tool constructed directly names its door in the constructor (reviewer
  # guidance 3), validated exactly as the registrar's origin: is.
  describe "BaseTool.new(call_origin:)" do
    it "carries the door it was built with, and nil when it names none" do
      expect(probe_class.new(account: account, user: user, call_origin: "concierge").send(:call_origin)).to eq("concierge")
      expect(probe_class.new(account: account, user: user).send(:call_origin)).to be_nil
    end

    it "refuses a door outside the vocabulary" do
      expect { probe_class.new(account: account, user: user, call_origin: "rest_session") }
        .to raise_error(ArgumentError, /call_origin/)
    end
  end

  describe "Mcp::Principal#call_origin" do
    it "maps each authenticated kind to its door" do
      expect(Mcp::Principal.for_user(user).call_origin).to eq("mcp_oauth")
      expect(Mcp::Principal.new(kind: :instance, account: account, subject_id: "i-1").call_origin).to eq("mcp_instance")
      expect(Mcp::Principal.new(kind: :federation, account: account, subject_id: "f-1").call_origin).to eq("mcp_federation")
    end
  end

  describe "McpPlatformToolRegistrar threading" do
    it "sets the origin the caller named on the tool it builds" do
      expect(run_probe("agent_bridge")).to include(success: true, data: { origin: "agent_bridge" })
    end

    it "leaves an unmarked call unmarked (nil), which grants nothing" do
      expect(run_probe(nil)).to include(success: true, data: { origin: nil })
    end

    it "refuses an origin outside the vocabulary before the tool runs" do
      expect { run_probe("rest_session") }.to raise_error(ArgumentError, /call_origin/)
    end
  end
end

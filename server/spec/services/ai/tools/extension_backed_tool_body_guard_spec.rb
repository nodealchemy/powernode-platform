# frozen_string_literal: true

require "rails_helper"

# GUARD (IMP-128fe17fd8c8): THE PER-CLASS EXTENSION GUARDS ARE STILL LOAD-BEARING.
#
# IMP-128fe17fd8c8 moved the refusal for a de-advertised action UP to the
# invocation seam (Ai::Tools::McpPlatformToolRegistrar#unadvertised_refusal), so
# tools/call is refused before the tool is ever constructed. The two request
# specs that used to assert these tools' own envelopes over HTTP
# (spec/requests/api/v1/mcp/tools_list_core_mode_{docker_runtime,disk_image}_spec.rb)
# consequently re-pointed at the seam's message — which left the tool-body
# guards with NO assertion anywhere on the tree, even though the comments on
# both classes and on #unadvertised_refusal call them defence in depth for the
# paths that do not pass the seam.
#
# That is exactly the failure the seam was built to end (a property held one
# class at a time by hand-written guards, pinned by nothing), reintroduced one
# layer down. This file pins the layer.
#
# THE ORACLE IS THE TOOL'S OWN MESSAGE, not the seam's, and #call is invoked
# directly on a tool constructed by hand — the shape the real bypass doors take:
# Api::V1::System::Platform::StorageMigrationsController#call_mcp_action and
# System::Ai::Skills::BaseSkillExecutor#tool both resolve/construct a platform
# tool without going through McpPlatformToolRegistrar.execute_tool.
RSpec.describe "extension-backed tool body guards" do
  let(:account) { create(:account) }

  describe Ai::Tools::DockerProvisioningTool do
    let(:tool) { described_class.new(account: account) }

    # All four actions on this class are extension-backed, so the guard is
    # unconditional on the class rather than keyed by action.
    %w[system_provision_docker_runtime system_decommission_docker_runtime
       system_mark_docker_ready system_list_managed_docker_hosts].each do |action|
      it "refuses #{action} in core mode with its own envelope, not a NameError" do
        hide_const("System")

        result = tool.send(:call, action: action)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/requires the 'system' extension/)
      end
    end

    it "does not refuse when the extension namespace is present" do
      skip "system extension not loaded in this run" unless described_class.extension_available?

      expect(tool.send(:call, action: "zz_not_an_action")[:error])
        .not_to match(/requires the 'system' extension/)
    end
  end

  describe Ai::Tools::DiskImageOperatorTool do
    let(:tool) { described_class.new(account: account) }

    described_class::EXTENSION_BACKED_ACTIONS.each do |action|
      it "refuses #{action} in core mode with its own envelope, not a NameError" do
        hide_const("System")

        result = tool.send(:call, action: action)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/#{action} requires the 'system' extension/)
      end
    end

    # CONTROL ARM — the guard is per ACTION here, not per class. provision_ci_worker
    # is core-only and must still run in core mode; the worker build is doubled
    # because what is under test is that the guard does NOT fire, not what the
    # action does.
    it "does not refuse the core-only action in core mode" do
      hide_const("System")
      allow(tool).to receive(:provision_ci_worker).and_return({ success: true, data: { control: true } })

      expect(tool.send(:call, action: "provision_ci_worker"))
        .to eq({ success: true, data: { control: true } })
    end
  end
end

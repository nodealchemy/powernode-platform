# frozen_string_literal: true

require "rails_helper"

# Focused on the paused-instance case (fc-32 review: `active?` doesn't
# include "paused", so terminating a paused sandbox always refused with
# "Container is not active"). Not a full spec of this tool.
RSpec.describe Ai::Tools::ContainerTerminateTool do
  let(:account) { create(:account) }
  let(:tool_user) { create(:user, account: account, permissions: %w[ai.agents.execute]) }
  let(:tool) { described_class.new(account: account, user: tool_user) }
  let(:template) { create(:devops_container_template, account: account) }

  describe "agent_container_terminate" do
    it "terminates a paused instance (paused is not terminal)" do
      instance = create(:devops_container_instance, :paused, account: account, template: template)
      # #initialize unconditionally builds a Gitea client; stub construction
      # (not just #cancel) so it never reaches the "no active Gitea provider"
      # error this fixture has no need to provision around.
      allow_any_instance_of(Devops::ContainerOrchestrationService).to receive(:build_gitea_client).and_return(nil)
      allow_any_instance_of(Devops::ContainerOrchestrationService).to receive(:cancel).and_return(true)

      result = tool.execute(params: { action: "agent_container_terminate", execution_id: instance.execution_id })

      expect(result[:success]).to be true
    end

    it "refuses a genuinely terminal instance (completed)" do
      instance = create(:devops_container_instance, :completed, account: account, template: template)

      result = tool.execute(params: { action: "agent_container_terminate", execution_id: instance.execution_id })

      expect(result[:success]).to be false
      expect(result[:error]).to include("not active")
    end
  end
end

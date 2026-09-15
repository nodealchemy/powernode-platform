# frozen_string_literal: true

require "rails_helper"

# IMP-5e2b153a3a04. CampaignDriver#claim asks Ai::Campaigns::Authorization before
# it takes a campaign's single-driver lease (IMP-c7a173fd2198). DevLoopTool acted
# on campaign loops under the tool's own ai.agents.update: dev_next_task took the
# same lease directly, and dev_complete_task (claim_if_pending), dev_update_task
# and delegate_ralph_task changed a campaign's tasks with no campaign check. A
# caller holding ai.agents.update but not ai.campaigns.manage could hold the
# lease — locking the legitimate driver out — or drain and rewrite the queue.
RSpec.describe Ai::Tools::DevLoopTool, "campaign-loop actions ask the campaign authorization" do
  let(:account) { create(:account) }
  let(:manager) do
    create(:user, account: account, permissions: %w[ai.campaigns.read ai.campaigns.manage ai.agents.update])
  end
  let(:outsider) { create(:user, account: account, permissions: %w[ai.agents.update]) }
  let(:campaign) { Ai::DevLoop::CampaignDriver.new(account: account, user: manager).start(name: "LeaseAuthz")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  def pull(holder: nil, **tool_options)
    params = { action: "dev_next_task", loop_id: loop_record.id }
    params[:holder] = holder if holder
    described_class.new(account: account, **tool_options).execute(params: params.with_indifferent_access)
  end

  describe "dev_next_task" do
    it "refuses a caller without ai.campaigns.manage and does not take the driver lease" do
      result = pull(user: outsider, holder: "outsider-session")

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("campaign_not_authorized")
      expect(campaign.reload.driver_lease_holder).to be_nil
    end

    it "refuses a holder-less pull from that caller while the lease is free" do
      result = pull(user: outsider)

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("campaign_not_authorized")
    end

    it "still lets a campaign manager take the lease" do
      result = pull(user: manager, holder: "manager-session")

      expect(result[:halted]).to be_falsey
      expect(campaign.reload.driver_lease_holder).to eq("manager-session")
    end

    # The production shape of an agent principal: Ai::AgentToolBridgeService
    # runs every tool with the agent AND `user: agent.creator`, so the creator is
    # the one asked.
    it "admits an agent whose creator may drive the campaign" do
      agent = create(:ai_agent, account: account, creator: manager)

      result = pull(agent: agent, user: manager, holder: "agent-session")

      expect(result[:halted]).to be_falsey
      expect(campaign.reload.driver_lease_holder).to eq("agent-session")
    end

    it "admits an agent principal of this account that carries no user" do
      agent = create(:ai_agent, account: account, creator: manager)

      result = pull(agent: agent, holder: "agent-session")

      expect(result[:halted]).to be_falsey
      expect(campaign.reload.driver_lease_holder).to eq("agent-session")
    end

    it "leaves a non-campaign loop ungated by the campaign check" do
      plain_loop = create(:ai_ralph_loop, account: account)
      create(:ai_ralph_task, ralph_loop: plain_loop, task_key: "IMP-plain", priority: 5)

      result = described_class.new(account: account, user: outsider)
                              .execute(params: { action: "dev_next_task", loop_id: plain_loop.id }.with_indifferent_access)

      expect(result[:halted]).to be_falsey
      expect(result.dig(:task, :task_key)).to eq("IMP-plain")
    end
  end

  describe "actions that change a campaign loop's tasks without pulling one" do
    let!(:task) do
      create(:ai_ralph_task, ralph_loop: loop_record, task_key: "IMP-campaign", priority: 5,
                             description: "Original title")
    end

    def act(user, action, **params)
      described_class.new(account: account, user: user).execute(
        params: { action: action, loop_id: loop_record.id, task_key: task.task_key }.merge(params).with_indifferent_access
      )
    end

    it "refuses dev_complete_task with claim_if_pending and leaves the task pending" do
      result = act(outsider, "dev_complete_task", claim_if_pending: true, outcome: "failed",
                                                  summary: "Closed out of band by a caller who may not drive this campaign.")

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("campaign_not_authorized")
      expect(task.reload.status).to eq("pending")
    end

    it "lets a campaign manager close the same task out of band" do
      result = act(manager, "dev_complete_task", claim_if_pending: true, outcome: "failed",
                                                 summary: "Finished out of band by the campaign's driver; it failed.")

      expect(result[:halted]).to be_falsey
      expect(task.reload.status).to eq("failed")
    end

    it "refuses dev_update_task and leaves the brief unchanged" do
      result = act(outsider, "dev_update_task", description: "Rewritten by an outsider")

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("campaign_not_authorized")
      expect(task.reload.description).to eq("Original title")
    end

    it "refuses delegate_ralph_task before starting the task or spawning an agent" do
      expect(Ai::Tools::AgentManagementTool).not_to receive(:new)

      result = act(outsider, "delegate_ralph_task", agent_id: "agent-9")

      expect(result[:halted]).to be(true)
      expect(result[:reason]).to eq("campaign_not_authorized")
      expect(task.reload.status).to eq("pending")
    end
  end
end

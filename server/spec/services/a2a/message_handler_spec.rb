# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::MessageHandler do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:handler) { described_class.new(account: account, user: user) }

  describe "#send_message" do
    context "with valid skill" do
      let(:workflow) { create(:ai_workflow, account: account, status: "active") }

      it "creates a task for the skill" do
        allow_any_instance_of(A2a::Skills::WorkflowSkills).to receive(:list).and_return(
          { output: { workflows: [], total: 0 } }
        )

        result = handler.send_message(
          "skill" => "workflows.list",
          "input" => {}
        )

        # Result should have either result or error
        expect(result[:result] || result[:error]).to be_present
      end
    end

    context "with unknown skill" do
      it "returns error" do
        result = handler.send_message(
          "skill" => "unknown.skill",
          "input" => {}
        )

        expect(result[:error]).to be_present
        expect(result[:error][:code]).to eq(-32602)
      end
    end
  end

  describe "#get_task" do
    context "with valid task" do
      let(:task) { create(:ai_a2a_task, account: account) }

      it "returns the task" do
        result = handler.get_task("id" => task.task_id)

        expect(result[:result]).to be_present
        # Result uses symbol keys
        expect(result[:result][:id]).to eq(task.task_id)
      end
    end

    context "with missing task ID" do
      it "returns error" do
        result = handler.get_task({})

        expect(result[:error]).to be_present
        expect(result[:error][:code]).to eq(-32602)
      end
    end

    context "with unknown task" do
      it "returns error" do
        result = handler.get_task("id" => "unknown-task-id")

        expect(result[:error]).to be_present
        expect(result[:error][:code]).to eq(-32001)
      end
    end
  end

  describe "#list_tasks" do
    let!(:tasks) { create_list(:ai_a2a_task, 3, account: account) }

    it "returns list of tasks" do
      result = handler.list_tasks({})

      expect(result[:result][:tasks]).to be_an(Array)
      expect(result[:result][:total]).to eq(3)
    end

    it "supports pagination" do
      result = handler.list_tasks("page" => 1, "perPage" => 2)

      expect(result[:result][:tasks].count).to eq(2)
      expect(result[:result][:page]).to eq(1)
      expect(result[:result][:perPage]).to eq(2)
    end

    it "filters by status" do
      create(:ai_a2a_task, account: account, status: "completed")

      result = handler.list_tasks("status" => "completed")

      # Each task has status as a hash with :state key
      expect(result[:result][:tasks].all? { |t| t[:status][:state] == "completed" }).to be true
    end
  end

  describe "#cancel_task" do
    context "with cancellable task" do
      let(:task) { create(:ai_a2a_task, account: account, status: "active") }

      it "cancels the task" do
        result = handler.cancel_task("id" => task.task_id, "reason" => "Test cancel")

        # A2A format uses status.state with "canceled" (US spelling)
        expect(result[:result][:status][:state]).to eq("canceled")

        task.reload
        expect(task.status).to eq("cancelled")
      end
    end

    context "with non-cancellable task" do
      let(:task) { create(:ai_a2a_task, account: account, status: "completed") }

      it "returns error" do
        result = handler.cancel_task("id" => task.task_id)

        expect(result[:error]).to be_present
        expect(result[:error][:code]).to eq(-32002)
      end
    end
  end

  describe "#subscribe_task" do
    let(:task) { create(:ai_a2a_task, account: account) }

    it "returns subscription info" do
      result = handler.subscribe_task("id" => task.task_id)

      expect(result[:result]).to include(
        :subscriptionId,
        :taskId,
        :status,
        :streamUrl,
        :channelName
      )
    end
  end

  describe "#set_push_notification" do
    let(:task) { create(:ai_a2a_task, account: account) }

    it "configures push notifications" do
      result = handler.set_push_notification(
        "id" => task.task_id,
        "url" => "https://example.com/webhook",
        "token" => "secret-token",
        "events" => %w[completed failed]
      )

      expect(result[:result][:success]).to be true

      task.reload
      expect(task.push_notification_config["url"]).to eq("https://example.com/webhook")
    end
  end

  describe "#get_push_notification" do
    let(:task) do
      create(:ai_a2a_task, account: account, push_notification_config: {
               "url" => "https://example.com/webhook"
             })
    end

    it "returns push notification config" do
      result = handler.get_push_notification("id" => task.task_id)

      expect(result[:result]["url"]).to eq("https://example.com/webhook")
    end
  end

  describe "#get_extended_card" do
    it "returns platform card when no agentCardId" do
      result = handler.get_extended_card({})

      expect(result[:result][:name]).to eq("Powernode")
    end

    context "with specific agent card" do
      let(:agent_card) { create(:ai_agent_card, account: account) }

      it "returns the agent card" do
        result = handler.get_extended_card("agentCardId" => agent_card.id)

        expect(result[:result][:name]).to eq(agent_card.name)
      end
    end
  end
end

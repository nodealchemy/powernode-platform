# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ConciergeService do
  include PermissionTestHelpers

  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.conversations.create", "ai.missions.manage", account: account) }
  # Non-tool-capable provider (ollama) so #process_message routes through the
  # action-grammar path (call_concierge_legacy → WorkerLlmClient#complete), which
  # is what these specs stub. Tool-capable providers (openai/anthropic) route
  # through ConciergeToolBridge#execute_tool_loop (complete_with_tools) instead —
  # see Ai::ConciergeService::TOOL_CAPABLE_PROVIDERS and #tool_bridge_available?.
  let(:provider) { create(:ai_provider, provider_type: "ollama") }
  let(:credential) { create(:ai_provider_credential, provider: provider, account: account, is_active: true) }
  let(:agent) do
    create(:ai_agent, account: account, provider: provider, is_concierge: true, status: "active")
  end
  let(:conversation) do
    create(:ai_conversation, account: account, user: user, agent: agent, provider: provider, status: "active")
  end
  let(:service) { described_class.new(conversation: conversation, user: user) }

  before { credential }

  describe "#process_message" do
    context "when LLM returns [RESPOND]" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "[RESPOND] Hello! How can I help you today?", usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 })
        )
      end

      it "adds an assistant message to the conversation" do
        expect { service.process_message("Hello") }.to change { conversation.messages.count }.by(1)

        last_message = conversation.messages.last
        expect(last_message.role).to eq("assistant")
        expect(last_message.content).to eq("Hello! How can I help you today?")
      end
    end

    context "when LLM returns [ACTION:check_status]" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "[ACTION:check_status]", usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 })
        )
      end

      it "checks mission status and responds" do
        service.process_message("What are my active missions?")
        last_message = conversation.messages.last
        expect(last_message.role).to eq("assistant")
        expect(last_message.content).to include("No active missions")
      end

      context "with active missions" do
        let(:repo) { create(:git_repository, account: account) }

        before do
          create(:ai_mission, :active, account: account, created_by: user, name: "Test Mission", repository: repo)
        end

        it "lists active missions" do
          service.process_message("What's the status?")
          last_message = conversation.messages.last
          expect(last_message.content).to include("Test Mission")
        end
      end
    end

    context "when LLM returns [CONFIRM:create_mission]" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '[CONFIRM:create_mission] {"name": "Add Login", "repository": "my-repo", "objective": "Add login page"} I\'d like to create a mission to add a login page.', usage: { prompt_tokens: 50, completion_tokens: 30, total_tokens: 80 })
        )
      end

      it "posts a confirmation card message" do
        service.process_message("Create a mission to add a login page")

        last_message = conversation.messages.last
        expect(last_message.role).to eq("assistant")
        expect(last_message.content_metadata["concierge_action"]).to be true
        expect(last_message.content_metadata["action_type"]).to eq("create_mission")
        expect(last_message.content_metadata["action_params"]).to include("name" => "Add Login")
        expect(last_message.content_metadata["action_context"]["status"]).to eq("pending")
        expect(last_message.content_metadata["actions"]).to be_an(Array)
        expect(last_message.content_metadata["actions"].first["type"]).to eq("confirm")
      end
    end

    context "when LLM returns [CONFIRM:delegate_to_team]" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '[CONFIRM:delegate_to_team] {"team": "Dev Team", "objective": "Refactor auth"} Shall I delegate this to the Dev Team?', usage: { prompt_tokens: 50, completion_tokens: 30, total_tokens: 80 })
        )
      end

      it "posts a confirmation card for delegation" do
        service.process_message("Have the dev team refactor auth")

        last_message = conversation.messages.last
        expect(last_message.content_metadata["action_type"]).to eq("delegate_to_team")
        expect(last_message.content_metadata["action_params"]).to include("team" => "Dev Team")
      end
    end

    context "when no credential is available" do
      before do
        credential.update!(is_active: false)
      end

      it "responds with a no-provider message" do
        service.process_message("Hello")
        last_message = conversation.messages.last
        expect(last_message.content).to include("no AI provider")
      end
    end

    context "when LLM call fails" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: nil, finish_reason: "error", raw_response: { error: "API error" })
        )
      end

      it "responds with a fallback message" do
        service.process_message("Hello")
        last_message = conversation.messages.last
        expect(last_message.content).to include("trouble processing")
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_raise(StandardError, "unexpected")
      end

      it "handles the error gracefully" do
        service.process_message("Hello")
        last_message = conversation.messages.last
        expect(last_message.content).to include("error processing your request")
      end
    end

    context "when response has no action marker" do
      before do
        allow_any_instance_of(WorkerLlmClient).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "Just a regular response without markers.", usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 })
        )
      end

      it "treats it as a respond action" do
        service.process_message("Hello")
        last_message = conversation.messages.last
        expect(last_message.role).to eq("assistant")
        expect(last_message.content).to eq("Just a regular response without markers.")
      end
    end
  end

  describe "#handle_confirmed_action" do
    context "create_mission" do
      let(:repo) { create(:git_repository, account: account, full_name: "org/my-repo") }

      before do
        repo
        allow_any_instance_of(Ai::Missions::OrchestratorService).to receive(:start!).and_return(true)
      end

      it "creates a mission and starts it" do
        expect {
          service.handle_confirmed_action("create_mission", {
            "name" => "Add Login Page",
            "repository" => "my-repo",
            "objective" => "Add a login page with OAuth",
            "mission_type" => "development"
          })
        }.to change { account.ai_missions.count }.by(1)

        mission = account.ai_missions.last
        expect(mission.name).to eq("Add Login Page")
        expect(mission.objective).to eq("Add a login page with OAuth")
        expect(mission.conversation).to eq(conversation)
      end

      it "posts a system message after creation" do
        service.handle_confirmed_action("create_mission", {
          "name" => "Add Login Page",
          "repository" => "my-repo",
          "objective" => "Add a login page with OAuth"
        })

        system_messages = conversation.messages.where(role: "system")
        expect(system_messages.last.content).to include("Add Login Page")
        expect(system_messages.last.content).to include("created and started")
      end

      it "handles repository not found" do
        service.handle_confirmed_action("create_mission", {
          "repository" => "nonexistent-repo",
          "objective" => "Something"
        })

        last_message = conversation.messages.last
        expect(last_message.role).to eq("assistant")
        expect(last_message.content).to include("not found")
      end
    end

    context "delegate_to_team" do
      let(:team) { create(:ai_agent_team, account: account, name: "Dev Team", status: "active") }

      before { team }

      it "delegates to the team" do
        expect(WorkerJobService).to receive(:enqueue_ai_team_execution).with(hash_including(
          team_id: team.id,
          user_id: user.id
        ))

        service.handle_confirmed_action("delegate_to_team", {
          "team" => "Dev Team",
          "objective" => "Refactor auth module"
        })
      end

      it "handles team not found" do
        service.handle_confirmed_action("delegate_to_team", {
          "team" => "Nonexistent Team",
          "objective" => "Something"
        })

        last_message = conversation.messages.last
        expect(last_message.content).to include("not found")
      end
    end

    context "approve_mission_gate" do
      let(:mission) do
        create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
               status: "active", current_phase: "review_plan",
               custom_phases: [
                 { "key" => "compose_plan", "requires_approval" => false },
                 { "key" => "review_plan", "requires_approval" => true },
                 { "key" => "execute", "requires_approval" => false }
               ])
      end

      it "routes an approval-gate confirmation through the OrchestratorService engine" do
        orchestrator = instance_double(Ai::Missions::OrchestratorService)
        allow(Ai::Missions::OrchestratorService).to receive(:new).with(mission: mission).and_return(orchestrator)
        expect(orchestrator).to receive(:handle_approval!).with(
          hash_including(gate: "review_plan", user: user, decision: "approved")
        )

        service.handle_confirmed_action("approve_mission_gate", {
          "mission_id" => mission.id, "gate" => "review_plan", "decision" => "approved"
        })
      end

      it "tells the operator when the mission no longer exists" do
        service.handle_confirmed_action("approve_mission_gate", {
          "mission_id" => "00000000-0000-0000-0000-000000000000"
        })
        expect(conversation.messages.last.content).to include("couldn't find")
      end

      it "declines a stale confirm when the mission is no longer awaiting approval" do
        mission.update!(current_phase: "execute")
        expect(Ai::Missions::OrchestratorService).not_to receive(:new)

        service.handle_confirmed_action("approve_mission_gate", {
          "mission_id" => mission.id, "gate" => "review_plan", "decision" => "approved"
        })

        expect(mission.reload.current_phase).to eq("execute")
        expect(conversation.messages.last.content).to include("isn't awaiting approval")
      end

      it "declines a confirm naming a gate other than the one the mission is at" do
        expect(Ai::Missions::OrchestratorService).not_to receive(:new)

        service.handle_confirmed_action("approve_mission_gate", {
          "mission_id" => mission.id, "gate" => "handoff", "decision" => "approved"
        })

        expect(mission.reload.current_phase).to eq("review_plan")
        expect(conversation.messages.last.content).to include("stale")
      end

      it "declines a stale rejection the same way" do
        mission.update!(current_phase: "execute")
        expect(Ai::Missions::OrchestratorService).not_to receive(:new)

        service.handle_confirmed_action("approve_mission_gate", {
          "mission_id" => mission.id, "gate" => "review_plan", "decision" => "rejected"
        })

        expect(mission.reload.current_phase).to eq("execute")
      end
    end

    context "unknown action" do
      it "responds with unknown action message" do
        service.handle_confirmed_action("unknown_action", {})

        last_message = conversation.messages.last
        expect(last_message.content).to include("Unknown action type")
      end
    end

    context "when action raises an error" do
      before do
        allow_any_instance_of(described_class).to receive(:create_mission).and_raise(StandardError, "boom")
      end

      it "handles the error gracefully" do
        service.handle_confirmed_action("create_mission", {})

        last_message = conversation.messages.last
        expect(last_message.content).to include("Failed to execute action")
      end
    end
  end

  describe "#post_mission_update" do
    let(:mission) { create(:ai_mission, :active, account: account, created_by: user, name: "My Mission") }

    it "posts phase_changed milestone" do
      expect {
        service.post_mission_update(mission, "phase_changed", { phase: "testing", phase_progress: 50 })
      }.to change { conversation.messages.count }.by(1)

      msg = conversation.messages.last
      expect(msg.role).to eq("system")
      expect(msg.content).to include("testing")
      expect(msg.content).to include("50%")
      expect(msg.content_metadata["activity_type"]).to eq("mission_phase_changed")
    end

    it "posts approval_required milestone" do
      service.post_mission_update(mission, "approval_required", { gate: "code_review" })

      msg = conversation.messages.last
      expect(msg.content).to include("awaiting")
      expect(msg.content).to include("Code review")
    end

    it "posts completed milestone" do
      service.post_mission_update(mission, "completed", { summary: "All done!" })

      msg = conversation.messages.last
      expect(msg.content).to include("completed successfully")
    end

    it "posts failed milestone" do
      service.post_mission_update(mission, "failed", { error: "CI failed" })

      msg = conversation.messages.last
      expect(msg.content).to include("failed")
      expect(msg.content).to include("CI failed")
    end

    it "ignores unknown event types" do
      expect {
        service.post_mission_update(mission, "unknown_event", {})
      }.not_to change { conversation.messages.count }
    end
  end

  describe "#parse_action (private, tested via process_message)" do
    # Testing the parsing logic indirectly through process_message
    # and directly via send(:parse_action) for edge cases

    it "parses [RESPOND] markers" do
      action, body = service.send(:parse_action, "[RESPOND] Hello there!")
      expect(action).to eq(:respond)
      expect(body).to eq("Hello there!")
    end

    it "parses [ACTION:intent] markers" do
      action, body = service.send(:parse_action, "[ACTION:check_status] checking now")
      expect(action).to eq(:action)
      expect(body[:intent]).to eq("check_status")
      expect(body[:body]).to eq("checking now")
    end

    it "parses [CONFIRM:intent] markers with JSON" do
      text = '[CONFIRM:create_mission] {"name":"Test"} Creating a test mission.'
      action, body = service.send(:parse_action, text)
      expect(action).to eq(:confirm)
      expect(body[:intent]).to eq("create_mission")
      expect(body[:params]).to eq({ "name" => "Test" })
    end

    it "handles responses without markers as respond" do
      action, body = service.send(:parse_action, "Just a plain response")
      expect(action).to eq(:respond)
      expect(body).to eq("Just a plain response")
    end

    it "handles nil response" do
      action, body = service.send(:parse_action, nil)
      expect(action).to eq(:respond)
    end
  end

  describe "legacy_system_prompt" do
    it "includes platform capabilities" do
      prompt = service.send(:legacy_system_prompt)
      expect(prompt).to include("ACTIVE MISSIONS")
      expect(prompt).to include("[RESPOND]")
      expect(prompt).to include("[CONFIRM:create_mission]")
    end

    it "includes active missions context" do
      repo = create(:git_repository, account: account)
      create(:ai_mission, :active, account: account, created_by: user, name: "Active Test", repository: repo)

      prompt = service.send(:legacy_system_prompt)
      expect(prompt).to include("Active Test")
    end

    it "shows no missions when none active" do
      prompt = service.send(:legacy_system_prompt)
      expect(prompt).to include("None currently active")
    end

    it "injects the delegate-first operating posture into the system prompt" do
      prompt = service.send(:legacy_system_prompt)
      expect(prompt).to include("DELEGATE FIRST")
      expect(prompt).to include("campaign_propose")
    end
  end

  # IMP-128fe17fd8c8. The handoff override's "provision" example used to name
  # `system_provision_docker_runtime` as a literal. That action is core-hosted
  # but extension-BACKED, so PlatformApiToolRegistry.advertised_action? drops it
  # from tools/list (and from every other advertisement surface) in core mode —
  # while the prompt kept steering the model at it. The example is now derived
  # from the same registry that answers tools/list.
  describe "delegated_override provisioning example" do
    def override_content
      service.send(:delegated_override)[:content]
    end

    it "names the provisioning actions the registry currently advertises" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools).and_return(
        { "system_provision_zz_widget" => Ai::Tools::DockerProvisioningTool,
          "list_agents" => Ai::Tools::DockerProvisioningTool }
      )

      content = override_content
      expect(content).to include("system_provision_zz_widget")
      # Not a name the registry answered with, and not the old literal.
      expect(content).not_to include("system_provision_docker_runtime")
      expect(content).not_to include("list_agents")
    end

    # THE SELECTOR MUST NOT RE-HARDCODE A NAMING CONVENTION. Only three real
    # registry keys carry the `system_provision_` prefix and all three are
    # extension-backed, so a prefix-anchored pattern empties out in core mode
    # while provision_ci_worker and the platform_provisioning_* family are
    # advertised and runnable there. Both shapes below must be named.
    it "names provisioning actions that do not carry the system_ prefix" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools).and_return(
        { "zz_provision_widget_worker" => Ai::Tools::DiskImageOperatorTool,
          "platform_zz_provisioning_compose_plan" => Ai::Tools::DiskImageOperatorTool,
          "zz_list_widget_nodes" => Ai::Tools::DiskImageOperatorTool }
      )

      content = override_content
      expect(content).to include("zz_provision_widget_worker")
      expect(content).to include("platform_zz_provisioning_compose_plan")
      expect(content).not_to include("zz_list_widget_nodes")
    end

    it "omits the clause entirely when the registry advertises no provisioning action" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools).and_return({})

      content = override_content
      expect(content).not_to match(/offered on this control plane/)
      expect(content).not_to include("system_provision_")
      # The instruction itself survives — only the example list is conditional.
      expect(content).to include("call the matching")
    end
  end
end

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

  # IMP-6fbbf47fcc3b. THE SWEEP, not one more literal. IMP-128fe17fd8c8 derived
  # the provisioning example above but left three siblings hardcoded in the same
  # block: system_list_package_repositories, system_list_nodes and
  # system_list_instances. All three are hosted in extensions/system, so on a
  # core-mode control plane PlatformApiToolRegistry.available_tools drops them
  # from tools/list AND McpPlatformToolRegistrar#unadvertised_refusal refuses
  # them at tools/call — while the handoff prompt kept naming them. Every
  # literal action name in the override must now come from the registry or not
  # be there at all.
  describe "delegated_override action-name sweep" do
    def override_content
      service.send(:delegated_override)[:content]
    end

    # The shape a registry action name takes: 2+ snake_case segments.
    let(:action_shaped) { /\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/ }

    # TWO SHAPES action_shaped CANNOT SEE, both of which this fix actually
    # removed or could reintroduce (review finding):
    #
    #   * a hyphenated SKILL SLUG. The literal dropped here was exactly that —
    #     "system-list-package-repositories-summary", seeded by
    #     extensions/system and therefore absent in core mode for the same
    #     reason the three action names were. It matches no snake_case shape at
    #     all, so re-adding one would leave both sweep examples green.
    #   * a SINGLE-SEGMENT registry key. "deliver", "escalate" and "scoreboard"
    #     are real action names with no underscore. Scanned as bare words and
    #     intersected with the REAL registry, so an ordinary English word only
    #     counts when it is also an action the platform dispatches.
    let(:slug_shaped) { /\b[a-z0-9]+(?:-[a-z0-9]+){2,}\b/ }
    let(:word_shaped) { /\b[a-z][a-z0-9]+\b/ }

    def bare_action_names(content)
      content.scan(word_shaped).uniq & Ai::Tools::PlatformApiToolRegistry.all_tools.keys
    end

    # Tokens of this shape in the override that are NOT registry actions, and so
    # cannot be registry-derived. Both entries are pinned by their own example
    # below, so the allowlist cannot quietly absorb a regression.
    let(:prose_tokens) do
      %w[
        system_packages
        system_package_repositories
        request_confirmation
      ]
    end

    # A registry that answers every selector with a name no hardcoded prompt
    # could have known. Any real action name surviving into the rendered
    # override is therefore a literal, not a derivation.
    let(:fixture_registry) do
      { "zz_list_package_repositories" => Ai::Tools::DockerProvisioningTool,
        "zz_provision_widget"          => Ai::Tools::DockerProvisioningTool,
        "zz_list_nodes"                => Ai::Tools::DiskImageOperatorTool,
        "zz_list_instances"            => Ai::Tools::DiskImageOperatorTool,
        "discover_skills"              => Ai::Tools::SkillTool }
    end

    it "names no action beyond the ones the registry answered with" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools).and_return(fixture_registry)

      content = override_content
      tokens = content.scan(action_shaped).uniq
      # POSITIVE CONTROL: the derivation actually fired, so an empty/erased
      # prompt cannot pass this example by naming nothing at all.
      expect(tokens).to include(
        "zz_list_package_repositories", "zz_provision_widget",
        "zz_list_nodes", "zz_list_instances", "discover_skills"
      )
      expect(tokens - fixture_registry.keys - prose_tokens).to eq([])
      expect(content.scan(slug_shaped)).to eq([])
      expect(bare_action_names(content) - fixture_registry.keys).to eq([])
    end

    it "drops every example whose action this control plane does not advertise" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools).and_return({})

      content = override_content
      expect(content.scan(action_shaped).uniq - prose_tokens).to eq([])
      expect(content.scan(slug_shaped)).to eq([])
      expect(bare_action_names(content)).to eq([])
      # The mandate itself survives — only the examples are conditional.
      expect(content).to include("MANDATORY: INVOKE TOOLS, DO NOT DESCRIBE")
      expect(content).to include("call the matching")
    end

    # THE DEGRADED SHAPE IS A DECISION, NOT AN ACCIDENT (review finding). One
    # derivation now feeds four selectors, so a registry that raises drops the
    # package-repo example, the fleet example AND the discovery instruction —
    # strictly more than the parenthetical clause the previous version lost.
    # That is the direction the sweep chose (name nothing you cannot confirm),
    # and this pins that a raise still leaves a usable prompt rather than an
    # empty or half-rendered one.
    it "keeps the mandate, and names nothing, when the registry raises" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:available_tools)
        .and_raise(StandardError, "registry unavailable")

      content = override_content
      expect(content.scan(action_shaped).uniq - prose_tokens).to eq([])
      expect(bare_action_names(content)).to eq([])
      expect(content).to include("MANDATORY: INVOKE TOOLS, DO NOT DESCRIBE")
      expect(content).to include("call the matching")
      expect(content).to include("AGENT HANDOFF FOR THIS QUERY")
    end

    it "allowlists only tokens that are not registry actions" do
      real = Ai::Tools::PlatformApiToolRegistry.all_tools.keys
      expect(prose_tokens & real).to eq([])
    end

    it "pins request_confirmation to the bridge that synthesises it" do
      bridge = Ai::ConciergeToolBridge.new(
        agent: agent, account: account, conversation: conversation, user: user
      )
      expect(bridge.send(:confirmation_tool_definition)[:name]).to eq("request_confirmation")
    end
  end

  # IMP-6fbbf47fcc3b, review finding. #delegated_override is NOT the only
  # concierge prompt that names actions, and it is the rarest: it renders only
  # on a router handoff, while DELEGATION_POSTURE is appended to both assembled
  # prompts on EVERY turn and names eight registry actions as literals.
  #
  # Those eight stay literal by decision (see the constant's comment) because
  # each resolves to a core-hosted class with no advertisement gate, so the
  # registry answers true for them on every deployment. THIS IS THAT DECISION'S
  # RATCHET: it resolves whatever the assembled prompt actually names and fails
  # the moment one of those classes moves to an extension, grows a gate, or a
  # new extension-hosted name joins the posture — the exact way the defect this
  # task fixed would come back, in the prompt path that runs every turn.
  describe "action names outside #delegated_override" do
    let(:action_shaped) { /\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/ }
    let(:registry) { Ai::Tools::PlatformApiToolRegistry.all_tools }
    let(:posture_actions) do
      described_class::DELEGATION_POSTURE.scan(action_shaped).uniq & registry.keys
    end

    it "names the delegation ladder's actions in the assembled prompt" do
      # POSITIVE CONTROL for both examples below: the scan really does reach
      # the posture's action names through the assembled prompt, so neither
      # example can pass by finding nothing.
      named = service.send(:legacy_system_prompt).scan(action_shaped).uniq & registry.keys

      expect(posture_actions).to contain_exactly(
        "spawn_task", "recruit_agent", "execute_agent", "execute_team",
        "create_team", "campaign_propose", "campaign_approve_proposal",
        "campaign_delegate"
      )
      expect(named).to include(*posture_actions)
    end

    it "names only core-hosted actions that carry no advertisement gate" do
      base_owner = Ai::Tools::BaseTool.method(:permitted?).owner
      named = service.send(:legacy_system_prompt).scan(action_shaped).uniq & registry.keys
      expect(named).not_to be_empty

      named.each do |name|
        klass = registry[name].constantize
        source = Object.const_source_location(klass.name)&.first

        expect(source).to start_with(Rails.root.to_s),
                          "#{name} (#{klass}) is hosted outside core (#{source.inspect}) — " \
                          "derive it from available_tools instead of naming it literally"
        expect(klass.method(:permitted?).owner).to eq(base_owner),
                                                   "#{name} (#{klass}) overrides .permitted?, so it can be de-advertised — derive it"
        expect(klass).not_to respond_to(:extension_available?),
                             "#{name} (#{klass}) is extension-gated — derive it"
        expect(klass).not_to respond_to(:action_advertised?),
                             "#{name} (#{klass}) carries a per-action advertisement gate — derive it"
      end
    end

    it "advertises every action the posture names, on this control plane" do
      advertised = Ai::Tools::PlatformApiToolRegistry.available_tools.keys
      expect(posture_actions - advertised).to eq([])
    end
  end
  # HIER-P1 — an agent the team composer creates from a spec is not a root:
  # its lineage parent is the concierge that designed it (the conversation's
  # agent), written through Ai::Agents::HierarchyWriter inside the same
  # transaction as the team.
  describe "#create_team_from_spec lineage" do
    let(:params) do
      {
        "name" => "Lineage Team",
        "coordination_strategy" => "hierarchical",
        "members" => [
          { "role" => "analyst", "priority" => 1,
            "agent_spec" => { "name" => "Spec Analyst", "agent_type" => "data_analyst",
                              "system_prompt_summary" => "Analyse things" } }
        ],
        "new_agents_to_create" => [
          { "role" => "analyst",
            "agent_spec" => { "name" => "Spec Analyst", "agent_type" => "data_analyst",
                              "system_prompt_summary" => "Analyse things" } }
        ]
      }
    end

    before do
      allow(Ai::AgentModelSelector).to receive(:recommend).and_return(
        provider: provider, model: "test-model", provider_type: "ollama",
        reason: "spec", score_details: {}
      )
    end

    it "attaches every agent created from a spec under the composing concierge" do
      service.send(:create_team_from_spec, params)

      created = account.ai_agents.find_by(name: "Spec Analyst")
      expect(created).to be_present
      expect(created.parent_agent_id).to eq(agent.id)

      edges = Ai::AgentLineage.for_child(created.id).active
      expect(edges.pluck(:parent_agent_id)).to eq([ agent.id ])
      expect(edges.first.spawn_reason).to eq("team_composition")
      expect(edges.first.metadata["role"]).to eq("analyst")
      expect(Ai::AgentTeam.find_by(account: account, name: "Lineage Team").members.count).to eq(1)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Missions::PrdGenerationService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:credential) { create(:ai_provider_credential, provider: provider, account: account, is_active: true) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }
  let(:repository) { create(:git_repository, account: account) }
  let(:mission) do
    create(:ai_mission,
      account: account,
      created_by: user,
      repository: repository,
      objective: "Add user authentication with JWT tokens",
      selected_feature: {
        "title" => "JWT Authentication",
        "description" => "Implement JWT-based auth flow",
        "complexity" => "medium"
      },
      analysis_result: {
        "tech_stack" => {
          "dependencies" => %w[express jsonwebtoken bcrypt],
          "dev_dependencies" => %w[jest supertest]
        },
        "structure" => {
          "entries" => [
            { "path" => "src", "type" => "tree" },
            { "path" => "package.json", "type" => "blob" },
            { "path" => "src/index.js", "type" => "blob" },
            { "path" => "src/routes", "type" => "tree" }
          ]
        },
        "recent_activity" => {
          "recent_commits" => [
            { "sha" => "abc12345", "message" => "Initial commit" }
          ],
          "open_issues" => [
            { "number" => 1, "title" => "Add authentication" }
          ]
        }
      }
    )
  end

  subject(:service) { described_class.new(mission: mission) }

  before do
    # Ensure credential and agent exist
    credential
    agent
  end

  describe '#generate!' do
    let(:ai_response_json) do
      {
        "title" => "JWT Authentication",
        "description" => "Implement JWT-based authentication",
        "tasks" => [
          {
            "key" => "task_1",
            "name" => "Create auth middleware",
            "description" => "Create JWT verification middleware in src/middleware/auth.js",
            "priority" => 1,
            "acceptance_criteria" => "Middleware validates JWT tokens and attaches user to request",
            "dependencies" => []
          },
          {
            "key" => "task_2",
            "name" => "Create login endpoint",
            "description" => "Create POST /api/auth/login endpoint",
            "priority" => 2,
            "acceptance_criteria" => "Endpoint accepts email/password and returns JWT",
            "dependencies" => ["task_1"]
          }
        ]
      }.to_json
    end

    let(:client) { instance_double(Ai::ProviderClientService) }

    before do
      allow(Ai::ProviderClientService).to receive(:new).with(credential).and_return(client)
      allow(provider).to receive(:default_model).and_return("gpt-4")
    end

    context 'when AI returns valid PRD JSON' do
      before do
        allow(client).to receive(:send_message).and_return({
          success: true,
          response: { choices: [{ message: { content: ai_response_json } }] },
          metadata: { usage: { prompt_tokens: 500, completion_tokens: 300 } }
        })
      end

      it 'generates PRD and creates RalphLoop with tasks' do
        prd = service.generate!

        expect(prd).to be_a(Hash)
        expect(prd["tasks"]).to be_an(Array)
        expect(prd["tasks"].length).to eq(2)
        expect(prd["generated_at"]).to be_present

        # Verify mission was updated
        mission.reload
        expect(mission.prd_json).to eq(prd)
        expect(mission.ralph_loop_id).to be_present

        # Verify RalphLoop was created correctly
        ralph_loop = mission.ralph_loop
        expect(ralph_loop.name).to include(mission.name)
        expect(ralph_loop.account).to eq(account)
        expect(ralph_loop.default_agent).to eq(agent)
        expect(ralph_loop.mission).to eq(mission)
        expect(ralph_loop.status).to eq("pending")

        # Verify tasks were created
        expect(ralph_loop.ralph_tasks.count).to eq(2)
        task_keys = ralph_loop.ralph_tasks.pluck(:task_key)
        expect(task_keys).to include("task_1", "task_2")
      end
    end

    context 'when AI returns JSON in code fences' do
      before do
        fenced_response = "Here's the PRD:\n```json\n#{ai_response_json}\n```\nLet me know if you need changes."
        allow(client).to receive(:send_message).and_return({
          success: true,
          response: { choices: [{ message: { content: fenced_response } }] },
          metadata: {}
        })
      end

      it 'extracts and parses the JSON from code fences' do
        prd = service.generate!

        expect(prd["tasks"].length).to eq(2)
        expect(prd["tasks"].first["key"]).to eq("task_1")
      end
    end

    context 'when AI returns unparseable response' do
      before do
        allow(client).to receive(:send_message).and_return({
          success: true,
          response: { choices: [{ message: { content: "I cannot generate a PRD for this." } }] },
          metadata: {}
        })
      end

      it 'falls back to single task from objective' do
        prd = service.generate!

        expect(prd["tasks"].length).to eq(1)
        expect(prd["tasks"].first["description"]).to eq(mission.objective)
      end
    end

    context 'when AI provider returns error' do
      before do
        allow(client).to receive(:send_message).and_return({
          success: false,
          error: "Rate limit exceeded"
        })
      end

      it 'raises PrdGenerationError' do
        expect { service.generate! }.to raise_error(
          Ai::Missions::PrdGenerationService::PrdGenerationError,
          /AI provider returned error/
        )
      end
    end

    context 'when no credentials available' do
      before do
        credential.update!(is_active: false)
      end

      it 'raises PrdGenerationError' do
        expect { service.generate! }.to raise_error(
          Ai::Missions::PrdGenerationService::PrdGenerationError,
          /No active AI provider credentials/
        )
      end
    end

    context 'when mission has no objective or feature' do
      let(:mission) do
        create(:ai_mission,
          account: account,
          created_by: user,
          repository: repository,
          objective: nil,
          selected_feature: {}
        )
      end

      it 'raises PrdGenerationError for missing context' do
        expect { service.generate! }.to raise_error(
          Ai::Missions::PrdGenerationService::PrdGenerationError,
          /must have a selected feature or objective/
        )
      end
    end

    context 'when no agent is available' do
      before do
        Ai::Agent.where(account: account).destroy_all
        allow(client).to receive(:send_message).and_return({
          success: true,
          response: { choices: [{ message: { content: ai_response_json } }] },
          metadata: {}
        })
      end

      it 'raises PrdGenerationError' do
        expect { service.generate! }.to raise_error(
          Ai::Missions::PrdGenerationService::PrdGenerationError,
          /No AI agent available/
        )
      end
    end
  end

  describe 'private methods' do
    describe '#build_user_message' do
      it 'includes objective and feature details' do
        message = service.send(:build_user_message)

        expect(message).to include("Add user authentication with JWT tokens")
        expect(message).to include("JWT Authentication")
        expect(message).to include("medium")
      end

      it 'includes tech stack from analysis' do
        message = service.send(:build_user_message)

        expect(message).to include("express")
        expect(message).to include("jsonwebtoken")
      end

      it 'includes repository structure' do
        message = service.send(:build_user_message)

        expect(message).to include("[dir] src")
        expect(message).to include("[file] package.json")
      end

      it 'includes recent commits' do
        message = service.send(:build_user_message)

        expect(message).to include("abc12345")
        expect(message).to include("Initial commit")
      end

      it 'includes open issues' do
        message = service.send(:build_user_message)

        expect(message).to include("#1")
        expect(message).to include("Add authentication")
      end
    end

    describe '#parse_prd_from_response' do
      it 'parses direct JSON' do
        json = { "title" => "Test", "tasks" => [{ "key" => "t1", "description" => "Do thing" }] }.to_json
        result = service.send(:parse_prd_from_response, json)

        expect(result["tasks"].length).to eq(1)
        expect(result["generated_at"]).to be_present
      end

      it 'extracts JSON from code fences' do
        json = { "title" => "Test", "tasks" => [{ "key" => "t1", "description" => "Do thing" }] }.to_json
        text = "Here you go:\n```json\n#{json}\n```"
        result = service.send(:parse_prd_from_response, text)

        expect(result["tasks"].length).to eq(1)
      end

      it 'falls back to single task for unparseable text' do
        result = service.send(:parse_prd_from_response, "This is just text with no JSON")

        expect(result["tasks"].length).to eq(1)
        expect(result["tasks"].first["description"]).to eq(mission.objective)
      end
    end

    describe '#find_default_agent' do
      it 'returns account agent when no team' do
        result = service.send(:find_default_agent)
        expect(result).to eq(agent)
      end

      it 'prefers team agent when team is set' do
        team = create(:ai_agent_team, account: account)
        team_agent = create(:ai_agent, account: account, provider: provider, creator: user)
        create(:ai_agent_team_member, team: team, agent: team_agent)
        mission.update!(team: team)

        result = service.send(:find_default_agent)
        expect(result).to eq(team_agent)
      end
    end
  end
end

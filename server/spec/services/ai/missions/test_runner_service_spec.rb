# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Missions::TestRunnerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:repository) { create(:git_repository, account: account) }
  let(:mission) do
    create(:ai_mission,
      account: account,
      created_by: user,
      repository: repository,
      branch_name: "mission/abc-feature",
      status: "active",
      started_at: Time.current,
      current_phase: "testing"
    )
  end

  subject(:service) { described_class.new(mission: mission) }

  describe '#trigger!' do
    context 'when no git credentials are available' do
      before do
        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first).and_return(nil)
      end

      it 'auto-passes with explanation' do
        result = service.trigger!

        expect(result[:status]).to eq("passed")
        expect(result[:method]).to eq("auto_pass")
        expect(result[:reason]).to include("No git credentials")
      end

      it 'updates mission test_result' do
        service.trigger!
        mission.reload

        expect(mission.test_result["status"]).to eq("passed")
        expect(mission.test_result["method"]).to eq("auto_pass")
      end
    end

    context 'when credentials exist but no CI workflow file found' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        # No workflow files found
        described_class::CI_WORKFLOW_PATHS.each do |path|
          allow(client).to receive(:get_file_content)
            .with(repository.owner, repository.name, path)
            .and_return(nil)
        end
      end

      it 'auto-passes with no workflow explanation' do
        result = service.trigger!

        expect(result[:status]).to eq("passed")
        expect(result[:method]).to eq("auto_pass")
        expect(result[:reason]).to include("No CI workflow file")
      end
    end

    context 'when CI workflow exists and dispatches successfully' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        # CI workflow found
        allow(client).to receive(:get_file_content)
          .with(repository.owner, repository.name, ".gitea/workflows/ci.yml")
          .and_return({ content: "name: CI\non: push" })

        allow(client).to receive(:trigger_workflow)
          .and_return({ success: true })

        allow(client).to receive(:list_workflow_runs)
          .and_return([{ "id" => 42, "head_branch" => "mission/abc-feature" }])

        allow(service).to receive(:sleep) # Skip the 2s wait in tests
      end

      it 'triggers workflow and records run_id' do
        result = service.trigger!

        expect(result[:status]).to eq("running")
        expect(result[:method]).to eq("ci_workflow")
        expect(result[:run_id]).to eq(42)

        mission.reload
        expect(mission.test_result["status"]).to eq("running")
        expect(mission.test_result["workflow_file"]).to eq("ci.yml")
      end
    end

    context 'when workflow dispatch fails' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        allow(client).to receive(:get_file_content)
          .with(repository.owner, repository.name, ".gitea/workflows/ci.yml")
          .and_return({ content: "name: CI" })

        allow(client).to receive(:trigger_workflow)
          .and_return({ success: false, error: "Workflow not found" })
      end

      it 'auto-passes with dispatch failure reason' do
        result = service.trigger!

        expect(result[:status]).to eq("passed")
        expect(result[:method]).to eq("auto_pass")
        expect(result[:reason]).to include("Workflow dispatch failed")
      end
    end

    context 'when mission has no repository' do
      let(:mission) do
        create(:ai_mission, :research,
          account: account,
          created_by: user
        )
      end

      it 'raises TestRunnerError' do
        expect { service.trigger! }.to raise_error(
          Ai::Missions::TestRunnerService::TestRunnerError,
          /No repository linked/
        )
      end
    end
  end

  describe '#check_status' do
    context 'when test_result is auto_pass' do
      before do
        mission.update!(test_result: {
          "run_id" => "uuid-123",
          "status" => "passed",
          "method" => "auto_pass"
        })
      end

      it 'returns completed and passed' do
        result = service.check_status

        expect(result[:status]).to eq("completed")
        expect(result[:passed]).to be true
      end
    end

    context 'when test_result is blank' do
      before { mission.update!(test_result: {}) }

      it 'returns unknown status' do
        result = service.check_status

        expect(result[:status]).to eq("unknown")
        expect(result[:passed]).to be false
      end
    end

    context 'when CI workflow has completed successfully' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        mission.update!(test_result: {
          "run_id" => 42,
          "status" => "running",
          "method" => "ci_workflow"
        })

        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        allow(client).to receive(:get_workflow_run)
          .with(repository.owner, repository.name, 42)
          .and_return({ "status" => "completed", "conclusion" => "success" })
      end

      it 'returns completed and passed' do
        result = service.check_status

        expect(result[:status]).to eq("completed")
        expect(result[:passed]).to be true

        mission.reload
        expect(mission.test_result["status"]).to eq("passed")
      end
    end

    context 'when CI workflow has failed' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        mission.update!(test_result: {
          "run_id" => 42,
          "status" => "running",
          "method" => "ci_workflow"
        })

        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        allow(client).to receive(:get_workflow_run)
          .with(repository.owner, repository.name, 42)
          .and_return({ "status" => "completed", "conclusion" => "failure" })
      end

      it 'returns completed and not passed' do
        result = service.check_status

        expect(result[:status]).to eq("completed")
        expect(result[:passed]).to be false
        expect(result[:conclusion]).to eq("failure")
      end
    end

    context 'when CI workflow is still running' do
      let(:git_credential) { instance_double("GitProviderCredential") }
      let(:client) { instance_double("Devops::Git::GiteaApiClient") }

      before do
        mission.update!(test_result: {
          "run_id" => 42,
          "status" => "running",
          "method" => "ci_workflow"
        })

        allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :first)
          .and_return(git_credential)
        allow(Devops::Git::ApiClient).to receive(:for).with(git_credential).and_return(client)

        allow(client).to receive(:get_workflow_run)
          .with(repository.owner, repository.name, 42)
          .and_return({ "status" => "in_progress", "conclusion" => nil })
      end

      it 'returns running status' do
        result = service.check_status

        expect(result[:status]).to eq("running")
        expect(result[:passed]).to be false
      end
    end
  end
end

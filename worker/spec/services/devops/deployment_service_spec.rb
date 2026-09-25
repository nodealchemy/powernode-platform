# frozen_string_literal: true

require "spec_helper"
require_relative "../../../app/services/devops/deployment_service"
require_relative "../../../app/services/devops/git_operations_service"

RSpec.describe Devops::DeploymentService do
  let(:api_client) { instance_double("BackendApiClient") }
  let(:service) { described_class.new(api_client: api_client, logger: Logger.new(IO::NULL)) }

  describe "#deploy with the workflow strategy" do
    # fc-23 removed the internal/devops/providers/:id API fallback from
    # #fetch_provider_config (the route never existed). Before this fix, a
    # nil provider_config fell through silently into
    # GitOperationsService.new(provider_config: nil), which failed later
    # with an opaque NoMethodError deep inside provider construction.
    it "raises a descriptive ArgumentError when neither context source has a provider_config" do
      expect do
        service.deploy(config: { "strategy" => "workflow" }, context: {})
      end.to raise_error(ArgumentError, /provider_config required for workflow strategy/)
    end

    it "does not raise when context[:provider_config] is present" do
      provider_config = { "provider_type" => "gitea", "base_url" => "https://gitea.example.test", "api_token" => "t" }
      fake_git_ops = instance_double(Devops::GitOperationsService, trigger_workflow: true)
      allow(Devops::GitOperationsService).to receive(:new).and_return(fake_git_ops)

      expect do
        service.deploy(
          config: { "strategy" => "workflow" },
          context: { provider_config: provider_config, repository: { full_name: "acme/repo" } }
        )
      end.not_to raise_error
    end
  end
end

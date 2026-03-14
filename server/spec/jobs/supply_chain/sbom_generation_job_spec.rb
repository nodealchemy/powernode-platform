# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::SbomGenerationJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:repository) { double("Repository", id: SecureRandom.uuid, account: account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:service) { instance_double(SupplyChain::SbomGenerationService) }
  let(:options) do
    {
      source_path: "/tmp/test",
      ecosystems: [ "npm", "gem" ],
      format: "cyclonedx_1_5"
    }
  end

  before do
    allow(SupplyChain::SbomGenerationService).to receive(:new).and_return(service)
    allow(service).to receive(:generate).and_return(sbom)
    allow(SupplyChainChannel).to receive(:broadcast_sbom_created)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "queue configuration" do
    it "uses supply_chain_default queue" do
      expect(described_class.new.queue_name).to eq("supply_chain_default")
    end
  end

  describe "#perform" do
    context "with valid account and no repository" do
      it "finds the account by account_id" do
        expect(Account).to receive(:find).with(account.id).and_return(account)

        described_class.perform_now(account.id, nil, options)
      end

      it "calls SbomGenerationService with correct arguments" do
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: nil,
          options: hash_including(options)
        ).and_return(service)

        described_class.perform_now(account.id, nil, options)
      end

      it "calls generate on the service with correct arguments" do
        expect(service).to receive(:generate).with(
          source_path: "/tmp/test",
          ecosystems: [ "npm", "gem" ],
          format: "cyclonedx_1_5"
        ).and_return(sbom)

        described_class.perform_now(account.id, nil, options)
      end

      it "broadcasts sbom_created event" do
        expect(SupplyChainChannel).to receive(:broadcast_sbom_created).with(sbom)

        described_class.perform_now(account.id, nil, options)
      end
    end

    context "with repository_id provided" do
      let(:repositories_relation) { double("ActiveRecord::Relation") }

      before do
        allow(Account).to receive(:find).with(account.id).and_return(account)
        allow(account).to receive(:devops_repositories).and_return(repositories_relation)
        allow(repositories_relation).to receive(:find).with(repository.id).and_return(repository)
      end

      it "finds the repository within account scope" do
        expect(account).to receive(:devops_repositories).and_return(repositories_relation)
        expect(repositories_relation).to receive(:find).with(repository.id).and_return(repository)

        described_class.perform_now(account.id, repository.id, options)
      end

      it "passes repository to SbomGenerationService" do
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: repository,
          options: hash_including(options)
        ).and_return(service)

        described_class.perform_now(account.id, repository.id, options)
      end
    end

    context "with nil repository_id" do
      it "passes nil repository to SbomGenerationService" do
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: nil,
          options: hash_including(options)
        ).and_return(service)

        described_class.perform_now(account.id, nil, options)
      end
    end

    context "with empty string repository_id" do
      it "treats empty string as nil and passes nil repository" do
        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: nil,
          options: hash_including(options)
        ).and_return(service)

        described_class.perform_now(account.id, "", options)
      end
    end

    context "format handling" do
      context "when format is not specified" do
        let(:options_without_format) do
          {
            source_path: "/tmp/test",
            ecosystems: [ "npm" ]
          }
        end

        it "defaults to cyclonedx_1_5 format" do
          expect(service).to receive(:generate).with(
            source_path: "/tmp/test",
            ecosystems: [ "npm" ],
            format: "cyclonedx_1_5"
          ).and_return(sbom)

          described_class.perform_now(account.id, nil, options_without_format)
        end
      end

      context "when format is explicitly specified" do
        let(:options_with_custom_format) do
          {
            source_path: "/tmp/test",
            ecosystems: [ "npm" ],
            format: "spdx_2_3"
          }
        end

        it "uses the specified format" do
          expect(service).to receive(:generate).with(
            source_path: "/tmp/test",
            ecosystems: [ "npm" ],
            format: "spdx_2_3"
          ).and_return(sbom)

          described_class.perform_now(account.id, nil, options_with_custom_format)
        end
      end
    end

    context "vulnerability scanning" do
      context "when scan_vulnerabilities is not specified" do
        it "enqueues VulnerabilityScanJob by default" do
          expect {
            described_class.perform_now(account.id, nil, options)
          }.to have_enqueued_job(SupplyChain::VulnerabilityScanJob).with(sbom.id)
        end
      end

      context "when scan_vulnerabilities is true" do
        let(:options_with_scan) do
          options.merge(scan_vulnerabilities: true)
        end

        it "enqueues VulnerabilityScanJob" do
          expect {
            described_class.perform_now(account.id, nil, options_with_scan)
          }.to have_enqueued_job(SupplyChain::VulnerabilityScanJob).with(sbom.id)
        end
      end

      context "when scan_vulnerabilities is false" do
        let(:options_without_scan) do
          options.merge(scan_vulnerabilities: false)
        end

        it "does not enqueue VulnerabilityScanJob" do
          expect {
            described_class.perform_now(account.id, nil, options_without_scan)
          }.not_to have_enqueued_job(SupplyChain::VulnerabilityScanJob)
        end
      end

      context "when scan_vulnerabilities is nil" do
        let(:options_with_nil_scan) do
          options.merge(scan_vulnerabilities: nil)
        end

        it "enqueues VulnerabilityScanJob (nil is not false)" do
          expect {
            described_class.perform_now(account.id, nil, options_with_nil_scan)
          }.to have_enqueued_job(SupplyChain::VulnerabilityScanJob).with(sbom.id)
        end
      end
    end

    context "logging" do
      it "logs start message" do
        expect(Rails.logger).to receive(:info).with("[SbomGenerationJob] Starting SBOM generation for account #{account.id}")

        described_class.perform_now(account.id, nil, options)
      end

      it "logs completion message with sbom id" do
        expect(Rails.logger).to receive(:info).with("[SbomGenerationJob] SBOM generation completed: #{sbom.id}")

        described_class.perform_now(account.id, nil, options)
      end
    end

    context "error handling" do
      context "when account is not found" do
        it "raises ActiveRecord::RecordNotFound" do
          expect {
            described_class.perform_now("non-existent-id", nil, options)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end

        it "logs error message" do
          allow(Account).to receive(:find).and_raise(ActiveRecord::RecordNotFound.new("Account not found"))

          expect(Rails.logger).to receive(:error).with("[SbomGenerationJob] Failed: Account not found")

          expect {
            described_class.perform_now("non-existent-id", nil, options)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when repository is not found" do
        let(:repositories_relation) { double("ActiveRecord::Relation") }

        before do
          allow(account).to receive(:devops_repositories).and_return(repositories_relation)
          allow(repositories_relation).to receive(:find).with("non-existent-repo-id").and_raise(ActiveRecord::RecordNotFound)
        end

        it "raises ActiveRecord::RecordNotFound" do
          expect {
            described_class.perform_now(account.id, "non-existent-repo-id", options)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when SbomGenerationService raises an error" do
        let(:service_error) { StandardError.new("SBOM generation failed") }

        before do
          allow(service).to receive(:generate).and_raise(service_error)
        end

        it "logs the error message" do
          expect(Rails.logger).to receive(:error).with("[SbomGenerationJob] Failed: SBOM generation failed")

          expect {
            described_class.perform_now(account.id, nil, options)
          }.to raise_error(StandardError, "SBOM generation failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(account.id, nil, options)
          }.to raise_error(StandardError, "SBOM generation failed")
        end

        it "does not broadcast sbom_created" do
          expect(SupplyChainChannel).not_to receive(:broadcast_sbom_created)

          expect {
            described_class.perform_now(account.id, nil, options)
          }.to raise_error(StandardError)
        end

        it "does not enqueue VulnerabilityScanJob" do
          expect {
            begin
              described_class.perform_now(account.id, nil, options)
            rescue StandardError
              # Expected error
            end
          }.not_to have_enqueued_job(SupplyChain::VulnerabilityScanJob)
        end
      end

      context "when broadcast fails" do
        let(:broadcast_error) { StandardError.new("Broadcast failed") }

        before do
          allow(SupplyChainChannel).to receive(:broadcast_sbom_created).and_raise(broadcast_error)
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with("[SbomGenerationJob] Failed: Broadcast failed")

          expect {
            described_class.perform_now(account.id, nil, options)
          }.to raise_error(StandardError, "Broadcast failed")
        end

        it "re-raises the error" do
          expect {
            described_class.perform_now(account.id, nil, options)
          }.to raise_error(StandardError, "Broadcast failed")
        end
      end
    end

    context "options handling" do
      it "converts string keys to symbol keys with with_indifferent_access" do
        string_options = {
          "source_path" => "/tmp/test",
          "ecosystems" => [ "npm" ],
          "format" => "cyclonedx_1_5"
        }

        expect(SupplyChain::SbomGenerationService).to receive(:new).with(
          account: account,
          repository: nil,
          options: hash_including("source_path", "ecosystems", "format")
        ).and_return(service)

        described_class.perform_now(account.id, nil, string_options)
      end

      it "handles empty options hash" do
        expect(service).to receive(:generate).with(
          source_path: nil,
          ecosystems: nil,
          format: "cyclonedx_1_5"
        ).and_return(sbom)

        described_class.perform_now(account.id, nil, {})
      end

      it "handles nil options" do
        expect(service).to receive(:generate).with(
          source_path: nil,
          ecosystems: nil,
          format: "cyclonedx_1_5"
        ).and_return(sbom)

        described_class.perform_now(account.id, nil, nil)
      end
    end

    context "integration test" do
      let(:repositories_relation) { double("ActiveRecord::Relation") }

      before do
        allow(Account).to receive(:find).with(account.id).and_return(account)
        allow(account).to receive(:devops_repositories).and_return(repositories_relation)
        allow(repositories_relation).to receive(:find).with(repository.id).and_return(repository)
      end

      it "successfully completes full workflow" do
        result_sbom = nil

        expect {
          result_sbom = described_class.perform_now(account.id, repository.id, options)
        }.to have_enqueued_job(SupplyChain::VulnerabilityScanJob)

        expect(SupplyChainChannel).to have_received(:broadcast_sbom_created).with(sbom)
        expect(Rails.logger).to have_received(:info).with("[SbomGenerationJob] Starting SBOM generation for account #{account.id}")
        expect(Rails.logger).to have_received(:info).with("[SbomGenerationJob] SBOM generation completed: #{sbom.id}")
      end
    end
  end
end

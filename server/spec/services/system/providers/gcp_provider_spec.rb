# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples"

RSpec.describe System::Providers::GcpProvider do
  let(:connection) do
    instance_double("System::ProviderConnection",
      tenant: "test-project",
      secret_key: '{"project_id": "test-project"}',
      config: { "project_id" => "test-project", "default_zone" => "us-central1-a" }
    )
  end
  let(:region) { instance_double("System::ProviderRegion", region_code: "us-central1") }
  let(:instances_client) { double("Google Instances Client") }
  let(:addresses_client) { double("Google Addresses Client") }
  let(:disks_client) { double("Google Disks Client") }
  let(:images_client) { double("Google Images Client") }
  let(:zone_operations_client) { double("Google ZoneOperations Client") }

  subject(:provider) { described_class.new(connection, region: region) }

  before do
    # Mock the GCP client creation - these are private methods with memoization
    allow(provider).to receive(:instances_client).and_return(instances_client)
    allow(provider).to receive(:addresses_client).and_return(addresses_client)
    allow(provider).to receive(:disks_client).and_return(disks_client)
    allow(provider).to receive(:images_client).and_return(images_client)
    allow(provider).to receive(:zone_operations_client).and_return(zone_operations_client)
  end

  it_behaves_like "a cloud provider"

  describe "#provider_type" do
    it "returns 'gcp'" do
      expect(provider.provider_type).to eq("gcp")
    end
  end

  describe "#get_instance" do
    let(:access_config) { double("Google AccessConfig", nat_i_p: "35.192.1.2") }
    let(:network_interface) do
      double("Google NetworkInterface",
        network_i_p: "10.128.0.2",
        access_configs: [access_config]
      )
    end

    let(:instance) do
      double("Google Instance",
        name: "test-instance",
        id: 12345678901234567,
        status: "RUNNING",
        machine_type: "zones/us-central1-a/machineTypes/n1-standard-1",
        network_interfaces: [network_interface]
      )
    end

    before do
      allow(instances_client).to receive(:get).and_return(instance)
    end

    it "returns instance details" do
      result = provider.get_instance("test-instance")

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("test-instance")
      expect(result[:status]).to eq("running")
      expect(result[:private_ip_address]).to eq("10.128.0.2")
      expect(result[:public_ip_address]).to eq("35.192.1.2")
    end
  end

  describe "#list_instances" do
    let(:access_config) { double("Google AccessConfig", nat_i_p: "35.192.1.2") }
    let(:network_interface) do
      double("Google NetworkInterface",
        network_i_p: "10.128.0.2",
        access_configs: [access_config]
      )
    end

    let(:instance) do
      double("Google Instance",
        name: "test-instance",
        status: "RUNNING",
        machine_type: "zones/us-central1-a/machineTypes/n1-standard-1",
        network_interfaces: [network_interface]
      )
    end

    before do
      allow(instances_client).to receive(:list).and_return([instance])
    end

    it "returns list of instances" do
      result = provider.list_instances

      expect(result[:success]).to be true
      expect(result[:instances]).to be_an(Array)
      expect(result[:instances].first[:cloud_instance_id]).to eq("test-instance")
    end
  end

  describe "#terminate_instance" do
    let(:operation) do
      double("Google Operation",
        name: "operation-12345",
        status: :DONE,
        error: nil
      )
    end

    before do
      allow(instances_client).to receive(:delete).and_return(operation)
      allow(zone_operations_client).to receive(:get).and_return(operation)
    end

    it "returns success" do
      result = provider.terminate_instance("test-instance")

      expect(result[:success]).to be true
      expect(result[:status]).to eq("terminating")
    end
  end

  describe "status normalization" do
    it "normalizes GCP status to common format" do
      expect(provider.send(:normalize_status, "PROVISIONING")).to eq("pending")
      expect(provider.send(:normalize_status, "STAGING")).to eq("pending")
      expect(provider.send(:normalize_status, "RUNNING")).to eq("running")
      expect(provider.send(:normalize_status, "STOPPING")).to eq("stopping")
      expect(provider.send(:normalize_status, "STOPPED")).to eq("stopped")
      expect(provider.send(:normalize_status, "TERMINATED")).to eq("terminated")
      expect(provider.send(:normalize_status, "SUSPENDING")).to eq("stopping")
      expect(provider.send(:normalize_status, "SUSPENDED")).to eq("stopped")
    end
  end

  describe "error handling" do
    context "when authentication fails" do
      before do
        # GCP uses PermissionDeniedError for auth failures
        stub_const("Google::Cloud::PermissionDeniedError", Class.new(StandardError)) unless defined?(Google::Cloud::PermissionDeniedError)
        allow(instances_client).to receive(:list).and_raise(
          Google::Cloud::PermissionDeniedError.new("Permission denied")
        )
      end

      it "raises AuthenticationError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::AuthenticationError)
      end
    end

    context "when resource not found" do
      before do
        stub_const("Google::Cloud::NotFoundError", Class.new(StandardError)) unless defined?(Google::Cloud::NotFoundError)
        allow(instances_client).to receive(:list).and_raise(
          Google::Cloud::NotFoundError.new("Instance not found")
        )
      end

      it "raises ResourceNotFoundError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::ResourceNotFoundError)
      end
    end

    context "when rate limited" do
      before do
        stub_const("Google::Cloud::ResourceExhaustedError", Class.new(StandardError)) unless defined?(Google::Cloud::ResourceExhaustedError)
        allow(instances_client).to receive(:list).and_raise(
          Google::Cloud::ResourceExhaustedError.new("Rate limit exceeded")
        )
      end

      it "raises RateLimitError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::RateLimitError)
      end
    end
  end
end

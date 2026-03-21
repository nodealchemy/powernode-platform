# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples"

RSpec.describe System::Providers::AzureProvider do
  let(:connection) do
    instance_double("System::ProviderConnection",
      access_key: "client-id-12345",
      secret_key: "client-secret",
      tenant: "subscription-id-12345",
      config: {
        "client_id" => "client-id-12345",
        "client_secret" => "client-secret",
        "tenant_id" => "tenant-id-12345",
        "subscription_id" => "subscription-id-12345",
        "resource_group" => "test-rg"
      }
    )
  end
  let(:region) { instance_double("System::ProviderRegion", region_code: "eastus") }
  let(:compute_client) { double("Azure Compute Client") }
  let(:network_client) { double("Azure Network Client") }
  let(:virtual_machines) { double("Azure VirtualMachines") }
  let(:network_interfaces) { double("Azure NetworkInterfaces") }
  let(:public_ips) { double("Azure PublicIPAddresses") }

  subject(:provider) { described_class.new(connection, region: region) }

  before do
    # Mock the Azure client creation
    allow(provider).to receive(:compute_client).and_return(compute_client)
    allow(provider).to receive(:network_client).and_return(network_client)
    allow(compute_client).to receive(:virtual_machines).and_return(virtual_machines)
    allow(network_client).to receive(:network_interfaces).and_return(network_interfaces)
    allow(network_client).to receive(:public_ipaddresses).and_return(public_ips)
  end

  it_behaves_like "a cloud provider"

  describe "#provider_type" do
    it "returns 'azure'" do
      expect(provider.provider_type).to eq("azure")
    end
  end

  describe "#get_instance" do
    let(:instance_view_status1) { double("InstanceViewStatus", code: "ProvisioningState/succeeded", display_status: "Provisioning succeeded") }
    let(:instance_view_status2) { double("InstanceViewStatus", code: "PowerState/running", display_status: "VM running") }
    let(:instance_view) { double("VirtualMachineInstanceView", statuses: [instance_view_status1, instance_view_status2]) }
    let(:hardware_profile) { double("HardwareProfile", vm_size: "Standard_D2s_v3") }
    let(:nic_ref) { double("NetworkInterfaceReference", id: "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/test-nic") }
    let(:network_profile) { double("NetworkProfile", network_interfaces: [nic_ref]) }

    let(:virtual_machine) do
      double("Azure VirtualMachine",
        id: "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm",
        name: "test-vm",
        hardware_profile: hardware_profile,
        instance_view: instance_view,
        network_profile: network_profile
      )
    end

    let(:ip_config) do
      double("NetworkInterfaceIPConfiguration",
        private_ipaddress: "10.0.0.4",
        public_ipaddress: double("PublicIPAddressRef", id: "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip")
      )
    end

    let(:network_interface) do
      double("Azure NetworkInterface",
        ip_configurations: [ip_config]
      )
    end

    let(:public_ip) do
      double("Azure PublicIPAddress",
        ip_address: "40.76.1.2"
      )
    end

    before do
      allow(virtual_machines).to receive(:get).and_return(virtual_machine)
      allow(network_interfaces).to receive(:get).and_return(network_interface)
      allow(public_ips).to receive(:get).and_return(public_ip)
    end

    it "returns instance details" do
      result = provider.get_instance("test-vm")

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("test-vm")
      expect(result[:status]).to eq("running")
    end
  end

  describe "#list_instances" do
    let(:instance_view_status1) { double("InstanceViewStatus", code: "ProvisioningState/succeeded", display_status: "Provisioning succeeded") }
    let(:instance_view_status2) { double("InstanceViewStatus", code: "PowerState/running", display_status: "VM running") }
    let(:instance_view) { double("VirtualMachineInstanceView", statuses: [instance_view_status1, instance_view_status2]) }
    let(:hardware_profile) { double("HardwareProfile", vm_size: "Standard_D2s_v3") }
    let(:nic_ref) { double("NetworkInterfaceReference", id: "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/test-nic") }
    let(:network_profile) { double("NetworkProfile", network_interfaces: [nic_ref]) }

    let(:virtual_machine) do
      double("Azure VirtualMachine",
        name: "test-vm",
        hardware_profile: hardware_profile,
        network_profile: network_profile,
        instance_view: instance_view
      )
    end

    let(:ip_config) do
      double("NetworkInterfaceIPConfiguration",
        private_ipaddress: "10.0.0.4",
        public_ipaddress: nil
      )
    end

    let(:network_interface) do
      double("Azure NetworkInterface",
        ip_configurations: [ip_config]
      )
    end

    before do
      allow(virtual_machines).to receive(:list).and_return([virtual_machine])
      allow(virtual_machines).to receive(:get).and_return(virtual_machine)
      allow(network_interfaces).to receive(:get).and_return(network_interface)
    end

    it "returns list of instances" do
      result = provider.list_instances

      expect(result[:success]).to be true
      expect(result[:instances]).to be_an(Array)
    end
  end

  describe "#terminate_instance" do
    before do
      allow(virtual_machines).to receive(:begin_delete).and_return(nil)
    end

    it "returns success" do
      result = provider.terminate_instance("test-vm")

      expect(result[:success]).to be true
      expect(result[:status]).to eq("terminating")
    end
  end

  describe "status normalization" do
    it "normalizes Azure power states to common format" do
      expect(provider.send(:normalize_status, "VM starting")).to eq("starting")
      expect(provider.send(:normalize_status, "VM running")).to eq("running")
      expect(provider.send(:normalize_status, "VM stopping")).to eq("stopping")
      expect(provider.send(:normalize_status, "VM stopped")).to eq("stopped")
      expect(provider.send(:normalize_status, "VM deallocating")).to eq("stopping")
      expect(provider.send(:normalize_status, "VM deallocated")).to eq("stopped")
    end
  end

  describe "error handling" do
    context "when authentication fails" do
      before do
        # Mock Azure error class if not available
        stub_const("MsRestAzure::AzureOperationError", Class.new(StandardError)) unless defined?(MsRestAzure::AzureOperationError)

        error = MsRestAzure::AzureOperationError.new("AuthenticationFailed")
        allow(error).to receive(:body).and_return({ "error" => { "code" => "AuthenticationFailed" } })
        allow(virtual_machines).to receive(:list).and_raise(error)
      end

      it "raises AuthenticationError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::AuthenticationError)
      end
    end

    context "when resource not found" do
      before do
        stub_const("MsRestAzure::AzureOperationError", Class.new(StandardError)) unless defined?(MsRestAzure::AzureOperationError)

        error = MsRestAzure::AzureOperationError.new("ResourceNotFound")
        allow(error).to receive(:body).and_return({ "error" => { "code" => "ResourceNotFound" } })
        allow(virtual_machines).to receive(:list).and_raise(error)
      end

      it "raises ResourceNotFoundError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::ResourceNotFoundError)
      end
    end
  end
end

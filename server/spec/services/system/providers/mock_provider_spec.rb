# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples"

RSpec.describe System::Providers::MockProvider do
  let(:connection) { instance_double("System::ProviderConnection") }
  let(:region) { instance_double("System::ProviderRegion", region_code: "mock-region-1") }

  subject(:provider) { described_class.new(connection, region: region) }

  before do
    # Reset mock state between tests
    described_class.reset!
  end

  it_behaves_like "a cloud provider"

  describe "#provider_type" do
    it "returns 'mock'" do
      expect(provider.provider_type).to eq("mock")
    end
  end

  describe "#create_instance" do
    let(:params) do
      {
        name: "test-instance",
        instance_type: "mock.small",
        image_id: "mock-ami-12345"
      }
    end

    it "returns success with instance details" do
      result = provider.create_instance(params)

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to start_with("mock-")
      expect(result[:status]).to eq("pending")
    end

    it "generates unique instance IDs" do
      result1 = provider.create_instance(params)
      result2 = provider.create_instance(params)

      expect(result1[:cloud_instance_id]).not_to eq(result2[:cloud_instance_id])
    end

    it "stores instance in memory" do
      result = provider.create_instance(params)
      expect(described_class.instances[result[:cloud_instance_id]]).to be_present
    end
  end

  describe "#terminate_instance" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    it "returns success for existing instance" do
      result = provider.terminate_instance(instance_id)

      expect(result[:success]).to be true
      expect(result[:status]).to eq("terminating")
    end

    it "returns error for non-existent instance" do
      result = provider.terminate_instance("nonexistent-id")

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "marks instance as terminating" do
      provider.terminate_instance(instance_id)
      expect(described_class.instances[instance_id][:status]).to eq("terminating")
    end
  end

  describe "#start_instance" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      described_class.instances[result[:cloud_instance_id]][:status] = "stopped"
      result[:cloud_instance_id]
    end

    it "returns success for stopped instance" do
      result = provider.start_instance(instance_id)

      expect(result[:success]).to be true
      expect(result[:status]).to eq("starting")
    end

    it "returns error for non-existent instance" do
      result = provider.start_instance("nonexistent-id")

      expect(result[:success]).to be false
    end
  end

  describe "#stop_instance" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      described_class.instances[result[:cloud_instance_id]][:status] = "running"
      result[:cloud_instance_id]
    end

    it "returns success for running instance" do
      result = provider.stop_instance(instance_id)

      expect(result[:success]).to be true
      expect(result[:status]).to eq("stopping")
    end

    it "accepts force option" do
      result = provider.stop_instance(instance_id, force: true)

      expect(result[:success]).to be true
    end
  end

  describe "#reboot_instance" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      described_class.instances[result[:cloud_instance_id]][:status] = "running"
      result[:cloud_instance_id]
    end

    it "returns success for running instance" do
      result = provider.reboot_instance(instance_id)

      expect(result[:success]).to be true
      expect(result[:status]).to eq("rebooting")
    end
  end

  describe "#get_instance" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      described_class.instances[result[:cloud_instance_id]][:status] = "running"
      result[:cloud_instance_id]
    end

    it "returns instance details for existing instance" do
      result = provider.get_instance(instance_id)

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq(instance_id)
      expect(result[:status]).to eq("running")
      expect(result[:private_ip_address]).to be_present
    end

    it "returns error for non-existent instance" do
      result = provider.get_instance("nonexistent-id")

      expect(result[:success]).to be false
    end
  end

  describe "#list_instances" do
    it "returns empty array when no instances" do
      result = provider.list_instances

      expect(result[:success]).to be true
      expect(result[:instances]).to be_an(Array)
      expect(result[:instances]).to be_empty
    end

    it "returns all instances" do
      provider.create_instance(name: "test1", instance_type: "mock.small")
      provider.create_instance(name: "test2", instance_type: "mock.small")

      result = provider.list_instances

      expect(result[:success]).to be true
      expect(result[:instances].length).to eq(2)
    end
  end

  describe "#create_volume" do
    let(:params) do
      {
        name: "test-volume",
        size_gb: 100,
        volume_type: "ssd"
      }
    end

    it "returns success with volume details" do
      result = provider.create_volume(params)

      expect(result[:success]).to be true
      expect(result[:volume_id]).to start_with("vol-mock-")
      expect(result[:status]).to eq("available")
    end
  end

  describe "#delete_volume" do
    let!(:volume_id) do
      result = provider.create_volume(name: "test", size_gb: 100)
      result[:volume_id]
    end

    it "returns success for existing volume" do
      result = provider.delete_volume(volume_id)

      expect(result[:success]).to be true
    end

    it "returns error for non-existent volume" do
      result = provider.delete_volume("nonexistent-vol")

      expect(result[:success]).to be false
    end
  end

  describe "#attach_volume" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    let!(:volume_id) do
      result = provider.create_volume(name: "test", size_gb: 100)
      result[:volume_id]
    end

    it "returns success with device path" do
      result = provider.attach_volume(volume_id, instance_id, device: "/dev/sdf")

      expect(result[:success]).to be true
      expect(result[:device]).to eq("/dev/sdf")
    end

    it "uses default device if not specified" do
      result = provider.attach_volume(volume_id, instance_id)

      expect(result[:success]).to be true
      expect(result[:device]).to be_present
    end
  end

  describe "#detach_volume" do
    let!(:volume_id) do
      result = provider.create_volume(name: "test", size_gb: 100)
      described_class.volumes[result[:volume_id]][:attached_to] = "mock-instance"
      result[:volume_id]
    end

    it "returns success for attached volume" do
      result = provider.detach_volume(volume_id)

      expect(result[:success]).to be true
    end
  end

  describe "#get_volume" do
    let!(:volume_id) do
      result = provider.create_volume(name: "test", size_gb: 100)
      result[:volume_id]
    end

    it "returns volume details" do
      result = provider.get_volume(volume_id)

      expect(result[:success]).to be true
      expect(result[:volume_id]).to eq(volume_id)
      expect(result[:status]).to eq("available")
    end
  end

  describe "#allocate_ip" do
    it "returns success with IP details" do
      result = provider.allocate_ip

      expect(result[:success]).to be true
      expect(result[:allocation_id]).to start_with("eipalloc-mock-")
      expect(result[:public_ip]).to match(/^203\.0\./)
    end
  end

  describe "#release_ip" do
    let!(:allocation_id) do
      result = provider.allocate_ip
      result[:allocation_id]
    end

    it "returns success for existing allocation" do
      result = provider.release_ip(allocation_id)

      expect(result[:success]).to be true
    end
  end

  describe "#associate_ip" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    let!(:allocation_id) do
      result = provider.allocate_ip
      result[:allocation_id]
    end

    it "returns success with association details" do
      result = provider.associate_ip(instance_id, allocation_id: allocation_id)

      expect(result[:success]).to be true
      expect(result[:association_id]).to start_with("eipassoc-mock-")
      expect(result[:public_ip]).to be_present
    end
  end

  describe "#disassociate_ip" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    let!(:association_id) do
      alloc = provider.allocate_ip
      result = provider.associate_ip(instance_id, allocation_id: alloc[:allocation_id])
      result[:association_id]
    end

    it "returns success for existing association" do
      result = provider.disassociate_ip(association_id)

      expect(result[:success]).to be true
    end
  end

  describe "#create_image" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    it "returns success with image details" do
      result = provider.create_image(instance_id, name: "test-image", description: "Test")

      expect(result[:success]).to be true
      expect(result[:image_id]).to start_with("ami-mock-")
      expect(result[:status]).to eq("pending")
    end
  end

  describe "#delete_image" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    let!(:image_id) do
      result = provider.create_image(instance_id, name: "test-image")
      result[:image_id]
    end

    it "returns success for existing image" do
      result = provider.delete_image(image_id)

      expect(result[:success]).to be true
    end
  end

  describe "#get_image" do
    let!(:instance_id) do
      result = provider.create_instance(name: "test", instance_type: "mock.small")
      result[:cloud_instance_id]
    end

    let!(:image_id) do
      result = provider.create_image(instance_id, name: "test-image")
      result[:image_id]
    end

    it "returns image details" do
      result = provider.get_image(image_id)

      expect(result[:success]).to be true
      expect(result[:image_id]).to eq(image_id)
    end
  end

  describe "#test_connection" do
    it "returns success" do
      result = provider.test_connection

      expect(result[:success]).to be true
      expect(result[:provider]).to eq("mock")
    end
  end
end

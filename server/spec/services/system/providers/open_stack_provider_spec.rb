# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples"

RSpec.describe System::Providers::OpenStackProvider do
  let(:connection) do
    instance_double("System::ProviderConnection",
      access_key: "username",
      secret_key: "password",
      tenant: "project-id",
      endpoint_url: "https://openstack.example.com:5000/v3",
      config: {}
    )
  end
  let(:region) { instance_double("System::ProviderRegion", region_code: "RegionOne") }
  let(:compute_client) { double("Fog::OpenStack::Compute") }
  let(:network_client) { double("Fog::OpenStack::Network") }
  let(:volume_client) { double("Fog::OpenStack::Volume") }
  let(:image_client) { double("Fog::OpenStack::Image") }

  subject(:provider) { described_class.new(connection, region: region) }

  before do
    allow(Fog::OpenStack::Compute).to receive(:new).and_return(compute_client)
    allow(Fog::OpenStack::Network).to receive(:new).and_return(network_client)
    allow(Fog::OpenStack::Volume).to receive(:new).and_return(volume_client)
    allow(Fog::OpenStack::Image).to receive(:new).and_return(image_client)
  end

  it_behaves_like "a cloud provider"

  describe "#provider_type" do
    it "returns 'openstack'" do
      expect(provider.provider_type).to eq("openstack")
    end
  end

  describe "#create_instance" do
    let(:params) do
      {
        name: "test-instance",
        instance_type: "m1.small",
        image_id: "image-uuid-12345",
        security_group_ids: ["sg-12345"],
        network_id: "network-uuid"
      }
    end

    let(:server) do
      double("Fog::OpenStack::Compute::Server",
        id: "server-uuid-12345",
        state: "BUILD",
        addresses: {}
      )
    end

    let(:servers_collection) { double("Fog::OpenStack::Compute::Servers") }

    before do
      allow(compute_client).to receive(:servers).and_return(servers_collection)
      allow(servers_collection).to receive(:create).and_return(server)
    end

    it "returns success with instance details" do
      result = provider.create_instance(params)

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("server-uuid-12345")
      expect(result[:status]).to eq("pending")
    end
  end

  describe "#terminate_instance" do
    let(:server) { double("Fog::OpenStack::Compute::Server") }
    let(:servers_collection) { double("Fog::OpenStack::Compute::Servers") }

    before do
      allow(compute_client).to receive(:servers).and_return(servers_collection)
      allow(servers_collection).to receive(:get).and_return(server)
      allow(server).to receive(:destroy).and_return(true)
    end

    it "returns success" do
      result = provider.terminate_instance("server-uuid")

      expect(result[:success]).to be true
      expect(result[:status]).to eq("terminating")
    end
  end

  describe "#get_instance" do
    let(:server) do
      double("Fog::OpenStack::Compute::Server",
        id: "server-uuid",
        state: "ACTIVE",
        addresses: {
          "private" => [
            { "addr" => "192.168.1.100", "OS-EXT-IPS:type" => "fixed", "version" => 4 },
            { "addr" => "203.0.113.50", "OS-EXT-IPS:type" => "floating", "version" => 4 }
          ]
        },
        flavor: { "id" => "flavor-id" }
      )
    end
    let(:servers_collection) { double("Fog::OpenStack::Compute::Servers") }

    before do
      allow(compute_client).to receive(:servers).and_return(servers_collection)
      allow(servers_collection).to receive(:get).and_return(server)
    end

    it "returns instance details" do
      result = provider.get_instance("server-uuid")

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("server-uuid")
      expect(result[:status]).to eq("running")
      expect(result[:private_ip_address]).to eq("192.168.1.100")
      expect(result[:public_ip_address]).to eq("203.0.113.50")
    end
  end

  describe "status normalization" do
    it "normalizes OpenStack status to common format" do
      expect(provider.send(:normalize_status, "BUILD")).to eq("pending")
      expect(provider.send(:normalize_status, "ACTIVE")).to eq("running")
      expect(provider.send(:normalize_status, "SHUTOFF")).to eq("stopped")
      expect(provider.send(:normalize_status, "DELETED")).to eq("terminated")
      expect(provider.send(:normalize_status, "ERROR")).to eq("failed")
      expect(provider.send(:normalize_status, "REBOOT")).to eq("rebooting")
    end
  end

  describe "error handling" do
    context "when authentication fails" do
      let(:servers_collection) { double("Fog::OpenStack::Compute::Servers") }

      before do
        allow(compute_client).to receive(:servers).and_return(servers_collection)
        allow(servers_collection).to receive(:all).and_raise(
          Excon::Error::Unauthorized.new("401 Unauthorized")
        )
      end

      it "raises AuthenticationError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::AuthenticationError)
      end
    end

    context "when resource not found" do
      let(:servers_collection) { double("Fog::OpenStack::Compute::Servers") }

      before do
        allow(compute_client).to receive(:servers).and_return(servers_collection)
        allow(servers_collection).to receive(:get).and_return(nil)
      end

      it "returns error response" do
        result = provider.get_instance("nonexistent")

        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end
  end
end

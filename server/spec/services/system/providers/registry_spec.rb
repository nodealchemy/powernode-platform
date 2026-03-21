# frozen_string_literal: true

require "rails_helper"

RSpec.describe System::Providers::Registry do
  let(:account) { create(:account) }
  let(:provider) { create(:system_provider, account: account, provider_type: "aws") }
  let(:region) { create(:system_provider_region, account: account, provider: provider) }
  let(:connection) do
    create(:system_provider_connection,
      account: account,
      provider: provider,
      status: "connected",
      access_key: "test-key",
      secret_key: "test-secret"
    )
  end
  let(:node) { create(:system_node, account: account) }
  let(:instance) do
    create(:system_node_instance,
      node: node,
      provider_region: region,
      variety: "cloud"
    )
  end
  let(:volume) do
    create(:system_provider_volume,
      account: account,
      provider_region: region
    )
  end

  before do
    connection # ensure connection exists
  end

  describe ".for" do
    it "returns an AwsProvider for aws provider type" do
      adapter = described_class.for(connection, region: region)
      expect(adapter).to be_a(System::Providers::AwsProvider)
    end

    it "returns an OpenStackProvider for openstack provider type" do
      provider.update!(provider_type: "openstack")
      adapter = described_class.for(connection, region: region)
      expect(adapter).to be_a(System::Providers::OpenStackProvider)
    end

    it "returns a GcpProvider for gcp provider type" do
      provider.update!(provider_type: "gcp")
      adapter = described_class.for(connection, region: region)
      expect(adapter).to be_a(System::Providers::GcpProvider)
    end

    it "returns an AzureProvider for azure provider type" do
      provider.update!(provider_type: "azure")
      adapter = described_class.for(connection, region: region)
      expect(adapter).to be_a(System::Providers::AzureProvider)
    end

    it "returns a MockProvider for mock provider type" do
      provider.update!(provider_type: "mock")
      adapter = described_class.for(connection, region: region)
      expect(adapter).to be_a(System::Providers::MockProvider)
    end

    it "raises UnknownProviderError for unsupported provider type" do
      allow(provider).to receive(:provider_type).and_return("unsupported")
      expect {
        described_class.for(connection, region: region)
      }.to raise_error(System::Providers::Registry::UnknownProviderError, /unsupported/)
    end
  end

  describe ".for_instance" do
    it "creates provider from instance's region and connection" do
      adapter = described_class.for_instance(instance)
      expect(adapter).to be_a(System::Providers::AwsProvider)
    end

    it "raises error if no connection available" do
      connection.update!(status: "error")
      expect {
        described_class.for_instance(instance)
      }.to raise_error(System::Providers::Registry::UnknownProviderError, /No provider connection/)
    end
  end

  describe ".for_volume" do
    it "creates provider from volume's region and connection" do
      adapter = described_class.for_volume(volume)
      expect(adapter).to be_a(System::Providers::AwsProvider)
    end

    it "raises error if no connection available" do
      connection.update!(status: "error")
      expect {
        described_class.for_volume(volume)
      }.to raise_error(System::Providers::Registry::UnknownProviderError, /No provider connection/)
    end
  end

  describe ".for_node" do
    it "creates provider from node's region and connection" do
      adapter = described_class.for_node(node, region: region)
      expect(adapter).to be_a(System::Providers::AwsProvider)
    end
  end

  describe ".available_providers" do
    it "returns list of registered provider types" do
      providers = described_class.available_providers
      expect(providers).to be_an(Array)
      expect(providers).to include("aws", "openstack", "gcp", "azure", "mock")
    end
  end

  describe ".supported?" do
    it "returns true for registered providers" do
      expect(described_class.supported?("aws")).to be true
      expect(described_class.supported?("openstack")).to be true
      expect(described_class.supported?("gcp")).to be true
      expect(described_class.supported?("azure")).to be true
      expect(described_class.supported?("mock")).to be true
    end

    it "returns false for unregistered providers" do
      expect(described_class.supported?("unknown")).to be false
      expect(described_class.supported?("custom")).to be false
    end
  end
end

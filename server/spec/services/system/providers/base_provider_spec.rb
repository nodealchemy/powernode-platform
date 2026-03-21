# frozen_string_literal: true

require "rails_helper"

RSpec.describe System::Providers::BaseProvider do
  # Create a test implementation since BaseProvider is abstract
  let(:test_provider_class) do
    Class.new(described_class) do
      def provider_type
        "test"
      end

      def create_instance(params)
        { success: true, instance_id: "test-123" }
      end

      def terminate_instance(instance_id)
        { success: true }
      end

      def start_instance(instance_id)
        { success: true }
      end

      def stop_instance(instance_id, force: false)
        { success: true }
      end

      def reboot_instance(instance_id)
        { success: true }
      end

      def get_instance(instance_id)
        { success: true, status: "running" }
      end

      def list_instances
        { success: true, instances: [] }
      end
    end
  end

  let(:connection) { instance_double("System::ProviderConnection") }
  let(:region) { instance_double("System::ProviderRegion") }
  let(:provider) { test_provider_class.new(connection, region: region) }

  describe "#initialize" do
    it "stores the connection" do
      expect(provider.connection).to eq(connection)
    end

    it "stores the region" do
      expect(provider.region).to eq(region)
    end
  end

  describe "abstract interface" do
    let(:abstract_provider) { described_class.new(connection, region: region) }

    describe "#provider_type" do
      it "raises NotImplementedError" do
        expect { abstract_provider.provider_type }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#create_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.create_instance({}) }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#terminate_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.terminate_instance("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#start_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.start_instance("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#stop_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.stop_instance("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#reboot_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.reboot_instance("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#get_instance" do
      it "raises NotImplementedError" do
        expect { abstract_provider.get_instance("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#list_instances" do
      it "raises NotImplementedError" do
        expect { abstract_provider.list_instances }.to raise_error(described_class::NotImplementedError)
      end
    end
  end

  describe "additional abstract methods" do
    let(:abstract_provider) { described_class.new(connection, region: region) }

    describe "#create_volume" do
      it "raises NotImplementedError" do
        expect { abstract_provider.create_volume({}) }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#delete_volume" do
      it "raises NotImplementedError" do
        expect { abstract_provider.delete_volume("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#attach_volume" do
      it "raises NotImplementedError" do
        expect { abstract_provider.attach_volume("vol", "inst") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#detach_volume" do
      it "raises NotImplementedError" do
        expect { abstract_provider.detach_volume("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#get_volume" do
      it "raises NotImplementedError" do
        expect { abstract_provider.get_volume("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#allocate_ip" do
      it "raises NotImplementedError" do
        expect { abstract_provider.allocate_ip }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#release_ip" do
      it "raises NotImplementedError" do
        expect { abstract_provider.release_ip("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#associate_ip" do
      it "raises NotImplementedError" do
        expect { abstract_provider.associate_ip("inst") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#disassociate_ip" do
      it "raises NotImplementedError" do
        expect { abstract_provider.disassociate_ip("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#create_image" do
      it "raises NotImplementedError" do
        expect { abstract_provider.create_image("inst", name: "test") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#delete_image" do
      it "raises NotImplementedError" do
        expect { abstract_provider.delete_image("id") }.to raise_error(described_class::NotImplementedError)
      end
    end

    describe "#get_image" do
      it "raises NotImplementedError" do
        expect { abstract_provider.get_image("id") }.to raise_error(described_class::NotImplementedError)
      end
    end
  end

  describe "error classes" do
    it "defines ProviderError" do
      expect(System::Providers::BaseProvider::ProviderError).to be < StandardError
    end

    it "defines AuthenticationError" do
      expect(System::Providers::BaseProvider::AuthenticationError).to be < System::Providers::BaseProvider::ProviderError
    end

    it "defines RateLimitError" do
      expect(System::Providers::BaseProvider::RateLimitError).to be < System::Providers::BaseProvider::ProviderError
    end

    it "defines ResourceNotFoundError" do
      expect(System::Providers::BaseProvider::ResourceNotFoundError).to be < System::Providers::BaseProvider::ProviderError
    end

    it "defines QuotaExceededError" do
      expect(System::Providers::BaseProvider::QuotaExceededError).to be < System::Providers::BaseProvider::ProviderError
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples"

RSpec.describe System::Providers::AwsProvider do
  let(:connection) do
    instance_double("System::ProviderConnection",
      access_key: "AKIATEST12345",
      secret_key: "secret-key-12345",
      config: {}
    )
  end
  let(:region) { instance_double("System::ProviderRegion", region_code: "us-east-1") }
  let(:ec2_client) { instance_double("Aws::EC2::Client") }

  subject(:provider) { described_class.new(connection, region: region) }

  before do
    allow(Aws::EC2::Client).to receive(:new).and_return(ec2_client)
  end

  it_behaves_like "a cloud provider"

  describe "#provider_type" do
    it "returns 'aws'" do
      expect(provider.provider_type).to eq("aws")
    end
  end

  describe "#create_instance" do
    let(:params) do
      {
        name: "test-instance",
        instance_type: "t2.micro",
        image_id: "ami-12345678",
        security_group_ids: ["sg-12345"],
        subnet_id: "subnet-12345"
      }
    end

    let(:instance_state) { instance_double("Aws::EC2::Types::InstanceState", name: "pending") }
    let(:run_instances_response) do
      instance_double("Aws::EC2::Types::Reservation",
        instances: [
          instance_double("Aws::EC2::Types::Instance",
            instance_id: "i-1234567890abcdef0",
            private_ip_address: "10.0.1.100",
            public_ip_address: nil,
            state: instance_state,
            instance_type: "t2.micro"
          )
        ]
      )
    end

    before do
      allow(ec2_client).to receive(:run_instances).and_return(run_instances_response)
      allow(ec2_client).to receive(:create_tags)
    end

    it "returns success with instance details" do
      result = provider.create_instance(params)

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("i-1234567890abcdef0")
      expect(result[:status]).to eq("pending")
      expect(result[:private_ip_address]).to eq("10.0.1.100")
    end

    it "calls EC2 run_instances with correct params" do
      expect(ec2_client).to receive(:run_instances).with(hash_including(
        image_id: "ami-12345678",
        instance_type: "t2.micro",
        min_count: 1,
        max_count: 1
      ))

      provider.create_instance(params)
    end
  end

  describe "#terminate_instance" do
    let(:terminate_response) do
      instance_double("Aws::EC2::Types::TerminateInstancesResult",
        terminating_instances: [
          instance_double("Aws::EC2::Types::InstanceStateChange",
            current_state: instance_double("Aws::EC2::Types::InstanceState", name: "shutting-down")
          )
        ]
      )
    end

    before do
      allow(ec2_client).to receive(:terminate_instances).and_return(terminate_response)
    end

    it "returns success" do
      result = provider.terminate_instance("i-12345")

      expect(result[:success]).to be true
      expect(result[:status]).to eq("terminating")
    end
  end

  describe "#start_instance" do
    let(:start_response) do
      instance_double("Aws::EC2::Types::StartInstancesResult",
        starting_instances: [
          instance_double("Aws::EC2::Types::InstanceStateChange",
            current_state: instance_double("Aws::EC2::Types::InstanceState", name: "pending")
          )
        ]
      )
    end

    let(:describe_response) do
      instance_double("Aws::EC2::Types::DescribeInstancesResult",
        reservations: [
          instance_double("Aws::EC2::Types::Reservation",
            instances: [
              instance_double("Aws::EC2::Types::Instance",
                instance_id: "i-12345",
                instance_type: "t2.micro",
                private_ip_address: "10.0.1.100",
                public_ip_address: nil,
                state: instance_double("Aws::EC2::Types::InstanceState", name: "pending")
              )
            ]
          )
        ]
      )
    end

    before do
      allow(ec2_client).to receive(:start_instances).and_return(start_response)
      allow(ec2_client).to receive(:describe_instances).and_return(describe_response)
    end

    it "returns success" do
      result = provider.start_instance("i-12345")

      expect(result[:success]).to be true
    end
  end

  describe "#stop_instance" do
    let(:stop_response) do
      instance_double("Aws::EC2::Types::StopInstancesResult",
        stopping_instances: [
          instance_double("Aws::EC2::Types::InstanceStateChange",
            current_state: instance_double("Aws::EC2::Types::InstanceState", name: "stopping")
          )
        ]
      )
    end

    let(:describe_response) do
      instance_double("Aws::EC2::Types::DescribeInstancesResult",
        reservations: [
          instance_double("Aws::EC2::Types::Reservation",
            instances: [
              instance_double("Aws::EC2::Types::Instance",
                instance_id: "i-12345",
                instance_type: "t2.micro",
                private_ip_address: "10.0.1.100",
                public_ip_address: nil,
                state: instance_double("Aws::EC2::Types::InstanceState", name: "stopping")
              )
            ]
          )
        ]
      )
    end

    before do
      allow(ec2_client).to receive(:stop_instances).and_return(stop_response)
      allow(ec2_client).to receive(:describe_instances).and_return(describe_response)
    end

    it "returns success" do
      result = provider.stop_instance("i-12345")

      expect(result[:success]).to be true
    end

    it "passes force option" do
      expect(ec2_client).to receive(:stop_instances).with(hash_including(force: true))

      provider.stop_instance("i-12345", force: true)
    end
  end

  describe "#get_instance" do
    let(:describe_response) do
      instance_double("Aws::EC2::Types::DescribeInstancesResult",
        reservations: [
          instance_double("Aws::EC2::Types::Reservation",
            instances: [
              instance_double("Aws::EC2::Types::Instance",
                instance_id: "i-12345",
                instance_type: "t2.micro",
                private_ip_address: "10.0.1.100",
                public_ip_address: "54.1.2.3",
                state: instance_double("Aws::EC2::Types::InstanceState", name: "running")
              )
            ]
          )
        ]
      )
    end

    before do
      allow(ec2_client).to receive(:describe_instances).and_return(describe_response)
    end

    it "returns instance details" do
      result = provider.get_instance("i-12345")

      expect(result[:success]).to be true
      expect(result[:cloud_instance_id]).to eq("i-12345")
      expect(result[:status]).to eq("running")
      expect(result[:private_ip_address]).to eq("10.0.1.100")
      expect(result[:public_ip_address]).to eq("54.1.2.3")
    end
  end

  describe "status normalization" do
    it "normalizes AWS status to common format" do
      expect(provider.send(:normalize_status, "pending")).to eq("pending")
      expect(provider.send(:normalize_status, "running")).to eq("running")
      expect(provider.send(:normalize_status, "shutting-down")).to eq("stopping")
      expect(provider.send(:normalize_status, "terminated")).to eq("terminated")
      expect(provider.send(:normalize_status, "stopping")).to eq("stopping")
      expect(provider.send(:normalize_status, "stopped")).to eq("stopped")
    end
  end

  describe "error handling" do
    # Test error handling via list_instances which has proper rescue block
    context "when AWS authentication fails" do
      before do
        allow(ec2_client).to receive(:describe_instances).and_raise(
          Aws::EC2::Errors::UnauthorizedOperation.new(nil, "Authentication failed")
        )
      end

      it "raises AuthenticationError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::AuthenticationError)
      end
    end

    context "when rate limited" do
      before do
        allow(ec2_client).to receive(:describe_instances).and_raise(
          Aws::EC2::Errors::RequestLimitExceeded.new(nil, "Rate limit exceeded")
        )
      end

      it "raises RateLimitError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::RateLimitError)
      end
    end

    context "when instance not found" do
      before do
        allow(ec2_client).to receive(:describe_instances).and_raise(
          Aws::EC2::Errors::InvalidInstanceIDNotFound.new(nil, "Instance not found")
        )
      end

      it "raises ResourceNotFoundError" do
        expect {
          provider.list_instances
        }.to raise_error(System::Providers::BaseProvider::ResourceNotFoundError)
      end
    end
  end
end

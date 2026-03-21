# frozen_string_literal: true

# Shared examples for provider interface compliance
# All providers must implement the BaseProvider interface

RSpec.shared_examples "a cloud provider" do
  describe "interface compliance" do
    # Core instance operations
    it { is_expected.to respond_to(:provider_type) }
    it { is_expected.to respond_to(:create_instance) }
    it { is_expected.to respond_to(:terminate_instance) }
    it { is_expected.to respond_to(:start_instance) }
    it { is_expected.to respond_to(:stop_instance) }
    it { is_expected.to respond_to(:reboot_instance) }
    it { is_expected.to respond_to(:get_instance) }
    it { is_expected.to respond_to(:list_instances) }

    # Volume operations
    it { is_expected.to respond_to(:create_volume) }
    it { is_expected.to respond_to(:delete_volume) }
    it { is_expected.to respond_to(:attach_volume) }
    it { is_expected.to respond_to(:detach_volume) }
    it { is_expected.to respond_to(:get_volume) }

    # IP operations
    it { is_expected.to respond_to(:allocate_ip) }
    it { is_expected.to respond_to(:release_ip) }
    it { is_expected.to respond_to(:associate_ip) }
    it { is_expected.to respond_to(:disassociate_ip) }

    # Image operations
    it { is_expected.to respond_to(:create_image) }
    it { is_expected.to respond_to(:delete_image) }
    it { is_expected.to respond_to(:get_image) }
  end
end

RSpec.shared_examples "provider response format" do |method, required_keys|
  describe "##{method}" do
    let(:result) { subject.send(method, *method_args) }

    it "returns a hash" do
      expect(result).to be_a(Hash)
    end

    it "includes :success key" do
      expect(result).to have_key(:success)
    end

    required_keys.each do |key|
      it "includes :#{key} key on success" do
        if result[:success]
          expect(result).to have_key(key)
        end
      end
    end
  end
end

RSpec.shared_examples "provider error handling" do
  describe "error handling" do
    it "returns success: false with error message on failure" do
      # Each provider should implement this with appropriate mocking
      pending "implement provider-specific error handling tests"
    end
  end
end

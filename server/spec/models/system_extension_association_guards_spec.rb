# frozen_string_literal: true

require 'rails_helper'

# Core models declare associations to `System::...` classes provided by the
# (public) system extension. Those declarations are wrapped in the established
# `if defined?(::System::...)` seam so that in CORE mode (system extension not
# loaded) they degrade gracefully instead of NameError-ing — both at access
# time and, for the `dependent: :destroy` on Account, at destroy time.
#
# In this suite the system extension IS loaded, so the FULL-mode branch is
# active. We assert (a) full-mode behavior is intact (the association still
# resolves to the System class and is callable), and (b) the guard idiom itself
# degrades to a safe reader when the System constant is hidden (core mode),
# exercised via `hide_const` on a fresh class that re-runs the exact guard.
RSpec.describe 'System extension association guards', type: :model do
  describe 'full mode (system extension loaded)' do
    before { skip 'system extension not loaded' unless defined?(::System::NodeInstance) }

    it 'Account#system_provider_credentials resolves to System::ProviderCredential and is callable' do
      reflection = Account.reflect_on_association(:system_provider_credentials)
      expect(reflection).to be_present
      expect(reflection.klass).to eq(::System::ProviderCredential)
      expect(reflection.options[:dependent]).to eq(:destroy)

      account = create(:account)
      expect { account.system_provider_credentials.to_a }.not_to raise_error
      expect(account.system_provider_credentials).to be_empty
    end

    it 'Devops::DockerHost#node_instance resolves to System::NodeInstance and reads nil for external hosts' do
      reflection = Devops::DockerHost.reflect_on_association(:node_instance)
      expect(reflection).to be_present
      expect(reflection.klass).to eq(::System::NodeInstance)

      host = build(:devops_docker_host)
      expect { host.node_instance }.not_to raise_error
      expect(host.node_instance).to be_nil
    end

    it 'Devops::KubernetesNode#node_instance resolves to System::NodeInstance' do
      reflection = Devops::KubernetesNode.reflect_on_association(:node_instance)
      expect(reflection).to be_present
      expect(reflection.klass).to eq(::System::NodeInstance)
    end

    it 'Ai::ProvisioningCodeDeployment#node_instance resolves to System::NodeInstance' do
      reflection = Ai::ProvisioningCodeDeployment.reflect_on_association(:node_instance)
      expect(reflection).to be_present
      expect(reflection.klass).to eq(::System::NodeInstance)
    end
  end

  describe 'core mode (System constant undefined) — guard idiom' do
    it 'degrades a belongs_to reader to nil instead of raising' do
      hide_const('System::NodeInstance') if defined?(::System::NodeInstance)

      guarded = Class.new do
        if defined?(::System::NodeInstance)
          def node_instance = :real_association
        else
          def node_instance = nil
        end
      end

      expect { guarded.new.node_instance }.not_to raise_error
      expect(guarded.new.node_instance).to be_nil
    end

    it 'degrades a has_many reader to an empty collection instead of raising' do
      hide_const('System::ProviderCredential') if defined?(::System::ProviderCredential)

      guarded = Class.new do
        if defined?(::System::ProviderCredential)
          def system_provider_credentials = :real_association
        else
          def system_provider_credentials = []
        end
      end

      expect { guarded.new.system_provider_credentials }.not_to raise_error
      expect(guarded.new.system_provider_credentials).to eq([])
    end
  end
end

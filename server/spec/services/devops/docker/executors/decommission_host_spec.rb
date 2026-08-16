# frozen_string_literal: true

require 'rails_helper'

# IMP-20fb59ec849d — the core-side AutonomyGate executor for Docker host
# teardown. It exists because the REST DELETE could not name the system
# extension's Runtime::DecommissionDockerHost (core-purity gate #9), and the
# teardown turned out to need nothing from that extension.
RSpec.describe Devops::Docker::Executors::DecommissionHost do
  let(:account) { create(:account) }
  let(:deferred_operation) { double('Ai::DeferredOperation', account: account) }
  let(:node) { sdwan_test_node(account: account) }
  let(:node_instance) { sdwan_test_node_instance(node: node) }
  let(:managed_host) do
    create(:devops_docker_host,
           account: account,
           provisioning_state: 'managed',
           api_endpoint: 'tcp://[fd00::40]:2376',
           node_instance_id: node_instance.id)
  end
  let(:external_host) { create(:devops_docker_host, account: account) }
  let(:vault_provider) { instance_double(Security::VaultCredentialProvider) }

  before do
    allow(Security::VaultCredentialProvider).to receive(:new).and_return(vault_provider)
    allow(vault_provider).to receive(:purge_credential!).and_return(true)
  end

  describe '.execute' do
    it 'purges the credential and destroys a managed host' do
      host_id = managed_host.id

      result = described_class.execute({ host_id: host_id }, deferred_operation: deferred_operation)

      expect(result).to eq(success: true, data: { host_id: host_id, decommissioned: true })
      expect(vault_provider).to have_received(:purge_credential!)
        .with(credential_type: :docker_daemon_tls, credential_id: host_id)
      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end

    it 'destroys an external host without purging anything' do
      host_id = external_host.id

      result = described_class.execute({ host_id: host_id }, deferred_operation: deferred_operation)

      expect(result[:success]).to be true
      expect(vault_provider).not_to have_received(:purge_credential!)
      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end

    # The replay path stores params in JSONB, so the executor reads back
    # string keys hours after the request that wrote symbols.
    it 'reads host_id from a string key' do
      host_id = external_host.id

      described_class.execute({ 'host_id' => host_id }, deferred_operation: deferred_operation)

      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end

    it 'refuses a host belonging to another account' do
      foreign_host = create(:devops_docker_host, account: create(:account))

      expect {
        described_class.execute({ host_id: foreign_host.id }, deferred_operation: deferred_operation)
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(Devops::DockerHost.find_by(id: foreign_host.id)).to be_present
    end

    # Ai::DeferredOperation belongs_to :account (required), so no real caller
    # arrives without one. The context below is the shape that COULD — the
    # duck-typed account-carrying contexts the gate's executor keyword accepts
    # — and it is what makes the absence of an "if account is nil" fallback
    # observable: with one, this resolves and destroys a row nobody has been
    # shown to own; without one, nothing is resolved at all.
    it 'resolves nothing when the operation carries no account' do
      unanchored = double('context', account: nil)
      host_id = external_host.id

      expect {
        described_class.execute({ host_id: host_id }, deferred_operation: unanchored)
      }.to raise_error(NoMethodError)

      expect(Devops::DockerHost.find_by(id: host_id)).to be_present
    end

    it 'resolves nothing when there is no operation at all' do
      host_id = external_host.id

      expect {
        described_class.execute({ host_id: host_id }, deferred_operation: nil)
      }.to raise_error(NoMethodError)

      expect(Devops::DockerHost.find_by(id: host_id)).to be_present
    end
  end

  describe '.preview' do
    it 'names a managed host and says the TLS material goes with it' do
      payload = described_class.preview({ host_id: managed_host.id },
                                        deferred_operation: deferred_operation)

      expect(payload[:summary]).to include(managed_host.name)
      expect(payload[:impact]).to include('TLS material')
    end

    it 'does not claim a Vault purge for an external host' do
      payload = described_class.preview({ host_id: external_host.id },
                                        deferred_operation: deferred_operation)

      expect(payload[:summary]).to include(external_host.name)
      expect(payload[:impact]).not_to include('TLS material')
    end

    # Fails closed: with no anchor there is nobody whose row this can be
    # proven to be, so the card names the id it was given.
    it 'names the bare id when there is no account to anchor on' do
      payload = described_class.preview({ host_id: managed_host.id }, deferred_operation: nil)

      expect(payload[:summary]).to include(managed_host.id)
      expect(payload[:summary]).not_to include(managed_host.name)
    end

    # An unresolvable host is not an external one. Saying "destroys the host
    # record and its containers, images, ..." here would assert to an approver
    # that no TLS material is at stake, which nothing has established.
    it 'does not describe an unresolvable host as if it were external' do
      external_payload = described_class.preview({ host_id: external_host.id },
                                                 deferred_operation: deferred_operation)
      missing_payload = described_class.preview({ host_id: SecureRandom.uuid },
                                                deferred_operation: deferred_operation)

      expect(missing_payload[:impact]).not_to eq(external_payload[:impact])
      expect(missing_payload[:impact]).not_to include('TLS material')
    end
  end
end

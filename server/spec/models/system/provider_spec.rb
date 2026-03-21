# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::Provider, type: :model do
  let(:account) { create(:account) }

  describe 'constants' do
    it 'defines valid provider types' do
      expect(described_class::PROVIDER_TYPES).to eq(%w[aws openstack gcp azure digitalocean linode vultr custom mock])
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:provider_regions).class_name('System::ProviderRegion').dependent(:destroy) }
    it { is_expected.to have_many(:provider_connections).class_name('System::ProviderConnection').dependent(:destroy) }
    it { is_expected.to have_many(:provider_instance_types).class_name('System::ProviderInstanceType').dependent(:destroy) }
    it { is_expected.to have_many(:provider_volume_types).class_name('System::ProviderVolumeType').dependent(:destroy) }
    it { is_expected.to have_many(:provider_networks).class_name('System::ProviderNetwork').dependent(:destroy) }
    it { is_expected.to have_many(:operations).class_name('System::Operation').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:system_provider, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:provider_type) }
    it { is_expected.to validate_inclusion_of(:provider_type).in_array(described_class::PROVIDER_TYPES) }

    it 'validates uniqueness of name scoped to account' do
      create(:system_provider, account: account, name: 'my-provider')
      duplicate = build(:system_provider, account: account, name: 'my-provider')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'allows same name in different accounts' do
      other_account = create(:account)
      create(:system_provider, account: account, name: 'my-provider')
      other_provider = build(:system_provider, account: other_account, name: 'my-provider')

      expect(other_provider).to be_valid
    end
  end

  describe 'scopes' do
    let!(:aws_provider) { create(:system_provider, account: account, provider_type: 'aws') }
    let!(:gcp_provider) { create(:system_provider, account: account, provider_type: 'gcp') }
    let!(:azure_provider) { create(:system_provider, account: account, provider_type: 'azure') }
    let!(:openstack_provider) { create(:system_provider, account: account, provider_type: 'openstack') }

    describe '.by_type' do
      it 'returns providers by type' do
        expect(described_class.by_type('aws')).to include(aws_provider)
        expect(described_class.by_type('aws')).not_to include(gcp_provider)
      end
    end

    describe '.aws' do
      it 'returns only AWS providers' do
        expect(described_class.aws).to include(aws_provider)
        expect(described_class.aws).not_to include(gcp_provider, azure_provider)
      end
    end

    describe '.gcp' do
      it 'returns only GCP providers' do
        expect(described_class.gcp).to include(gcp_provider)
        expect(described_class.gcp).not_to include(aws_provider)
      end
    end

    describe '.azure' do
      it 'returns only Azure providers' do
        expect(described_class.azure).to include(azure_provider)
        expect(described_class.azure).not_to include(aws_provider)
      end
    end

    describe '.openstack' do
      it 'returns only OpenStack providers' do
        expect(described_class.openstack).to include(openstack_provider)
        expect(described_class.openstack).not_to include(aws_provider)
      end
    end
  end

  describe 'type predicates' do
    let(:provider) { build(:system_provider, account: account) }

    describe '#aws?' do
      it 'returns true for AWS provider' do
        provider.provider_type = 'aws'
        expect(provider.aws?).to be true
      end

      it 'returns false for other types' do
        provider.provider_type = 'gcp'
        expect(provider.aws?).to be false
      end
    end

    describe '#gcp?' do
      it 'returns true for GCP provider' do
        provider.provider_type = 'gcp'
        expect(provider.gcp?).to be true
      end
    end

    describe '#azure?' do
      it 'returns true for Azure provider' do
        provider.provider_type = 'azure'
        expect(provider.azure?).to be true
      end
    end

    describe '#openstack?' do
      it 'returns true for OpenStack provider' do
        provider.provider_type = 'openstack'
        expect(provider.openstack?).to be true
      end
    end

    describe '#custom?' do
      it 'returns true for custom provider' do
        provider.provider_type = 'custom'
        expect(provider.custom?).to be true
      end
    end
  end

  describe '#has_capability?' do
    let(:provider) { create(:system_provider, account: account) }

    it 'returns true when capability is present and true' do
      provider.update!(capabilities: { 'snapshots' => true, 'volumes' => true })
      expect(provider.has_capability?(:snapshots)).to be true
      expect(provider.has_capability?('volumes')).to be true
    end

    it 'returns false when capability is not present' do
      provider.update!(capabilities: { 'snapshots' => true })
      expect(provider.has_capability?(:volumes)).to be false
    end

    it 'returns false when capability is false' do
      provider.update!(capabilities: { 'snapshots' => false })
      expect(provider.has_capability?(:snapshots)).to be false
    end

    it 'returns false when capabilities is nil' do
      expect(provider.has_capability?(:anything)).to be false
    end
  end

  describe 'config accessor' do
    let(:provider) { create(:system_provider, account: account) }

    it 'allows storing and retrieving config data' do
      provider.update!(config: {
        'api_endpoint' => 'https://api.example.com',
        'region' => 'us-east-1',
        'settings' => { 'timeout' => 30 }
      })

      provider.reload
      expect(provider.config['api_endpoint']).to eq('https://api.example.com')
      expect(provider.config['settings']['timeout']).to eq(30)
    end
  end

  describe 'cascading deletes' do
    let(:provider) { create(:system_provider, account: account) }

    it 'destroys associated regions when destroyed' do
      region = create(:system_provider_region, provider: provider)

      expect { provider.destroy }.to change(System::ProviderRegion, :count).by(-1)
      expect { region.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'destroys associated connections when destroyed' do
      connection = create(:system_provider_connection, provider: provider)

      expect { provider.destroy }.to change(System::ProviderConnection, :count).by(-1)
      expect { connection.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::NodeInstance, 'geolocation and network enhancements', type: :model do
  let(:account) { create(:account) }
  let(:node) { create(:system_node, account: account) }

  describe 'MAC_ADDRESS_REGEX constant' do
    it 'matches valid MAC addresses with colons' do
      expect('00:11:22:33:44:55').to match(System::NodeInstance::MAC_ADDRESS_REGEX)
    end

    it 'matches valid MAC addresses with dashes' do
      expect('00-11-22-33-44-55').to match(System::NodeInstance::MAC_ADDRESS_REGEX)
    end

    it 'matches lowercase MAC addresses' do
      expect('aa:bb:cc:dd:ee:ff').to match(System::NodeInstance::MAC_ADDRESS_REGEX)
    end

    it 'does not match invalid MAC addresses' do
      expect('invalid-mac').not_to match(System::NodeInstance::MAC_ADDRESS_REGEX)
      expect('00:11:22:33:44').not_to match(System::NodeInstance::MAC_ADDRESS_REGEX) # Too short
      expect('00:11:22:33:44:55:66').not_to match(System::NodeInstance::MAC_ADDRESS_REGEX) # Too long
    end
  end

  describe 'validations' do
    describe 'mac_address' do
      it 'accepts valid MAC addresses' do
        instance = build(:system_node_instance, node: node, mac_address: '00:11:22:33:44:55')
        expect(instance).to be_valid
      end

      it 'allows nil mac_address' do
        instance = build(:system_node_instance, node: node, mac_address: nil)
        expect(instance).to be_valid
      end

      it 'rejects invalid MAC addresses' do
        instance = build(:system_node_instance, node: node, mac_address: 'invalid')
        expect(instance).not_to be_valid
        expect(instance.errors[:mac_address]).to include('must be a valid MAC address')
      end
    end

    describe 'latitude' do
      it 'accepts valid latitude values' do
        instance = build(:system_node_instance, node: node, latitude: 45.0)
        expect(instance).to be_valid
      end

      it 'allows nil latitude' do
        instance = build(:system_node_instance, node: node, latitude: nil)
        expect(instance).to be_valid
      end

      it 'rejects latitude below -90' do
        instance = build(:system_node_instance, node: node, latitude: -91)
        expect(instance).not_to be_valid
        expect(instance.errors[:latitude]).to be_present
      end

      it 'rejects latitude above 90' do
        instance = build(:system_node_instance, node: node, latitude: 91)
        expect(instance).not_to be_valid
        expect(instance.errors[:latitude]).to be_present
      end

      it 'accepts boundary values' do
        instance = build(:system_node_instance, node: node, latitude: -90)
        expect(instance).to be_valid

        instance.latitude = 90
        expect(instance).to be_valid
      end
    end

    describe 'longitude' do
      it 'accepts valid longitude values' do
        instance = build(:system_node_instance, node: node, longitude: -122.4)
        expect(instance).to be_valid
      end

      it 'allows nil longitude' do
        instance = build(:system_node_instance, node: node, longitude: nil)
        expect(instance).to be_valid
      end

      it 'rejects longitude below -180' do
        instance = build(:system_node_instance, node: node, longitude: -181)
        expect(instance).not_to be_valid
        expect(instance.errors[:longitude]).to be_present
      end

      it 'rejects longitude above 180' do
        instance = build(:system_node_instance, node: node, longitude: 181)
        expect(instance).not_to be_valid
        expect(instance.errors[:longitude]).to be_present
      end

      it 'accepts boundary values' do
        instance = build(:system_node_instance, node: node, longitude: -180)
        expect(instance).to be_valid

        instance.longitude = 180
        expect(instance).to be_valid
      end
    end
  end

  describe '#has_coordinates?' do
    it 'returns true when both latitude and longitude are present' do
      instance = build(:system_node_instance, node: node, latitude: 37.7749, longitude: -122.4194)
      expect(instance.has_coordinates?).to be true
    end

    it 'returns false when latitude is nil' do
      instance = build(:system_node_instance, node: node, latitude: nil, longitude: -122.4194)
      expect(instance.has_coordinates?).to be false
    end

    it 'returns false when longitude is nil' do
      instance = build(:system_node_instance, node: node, latitude: 37.7749, longitude: nil)
      expect(instance.has_coordinates?).to be false
    end

    it 'returns false when both are nil' do
      instance = build(:system_node_instance, node: node, latitude: nil, longitude: nil)
      expect(instance.has_coordinates?).to be false
    end
  end

  describe '#coordinates' do
    it 'returns hash with latitude and longitude when present' do
      instance = build(:system_node_instance, node: node, latitude: 37.7749, longitude: -122.4194)
      expect(instance.coordinates).to eq({ latitude: 37.7749, longitude: -122.4194 })
    end

    it 'returns nil when coordinates are not present' do
      instance = build(:system_node_instance, node: node, latitude: nil, longitude: nil)
      expect(instance.coordinates).to be_nil
    end
  end

  describe '#set_coordinates!' do
    it 'updates latitude and longitude' do
      instance = create(:system_node_instance, node: node)
      instance.set_coordinates!(40.7128, -74.0060)

      instance.reload
      expect(instance.latitude).to eq(40.7128)
      expect(instance.longitude).to eq(-74.0060)
    end
  end

  describe '#has_mac_address?' do
    it 'returns true when mac_address is present' do
      instance = build(:system_node_instance, node: node, mac_address: '00:11:22:33:44:55')
      expect(instance.has_mac_address?).to be true
    end

    it 'returns false when mac_address is nil' do
      instance = build(:system_node_instance, node: node, mac_address: nil)
      expect(instance.has_mac_address?).to be false
    end
  end

  describe '#normalized_mac_address' do
    it 'returns uppercase MAC with colons' do
      instance = build(:system_node_instance, node: node, mac_address: 'aa-bb-cc-dd-ee-ff')
      expect(instance.normalized_mac_address).to eq('AA:BB:CC:DD:EE:FF')
    end

    it 'returns nil when mac_address is nil' do
      instance = build(:system_node_instance, node: node, mac_address: nil)
      expect(instance.normalized_mac_address).to be_nil
    end
  end

  describe '#netboot_enabled?' do
    it 'returns true for physical instances with private_netboot enabled' do
      instance = build(:system_node_instance, node: node, variety: 'physical', private_netboot: true)
      expect(instance.netboot_enabled?).to be true
    end

    it 'returns false for cloud instances even with private_netboot' do
      instance = build(:system_node_instance, node: node, variety: 'cloud', private_netboot: true)
      expect(instance.netboot_enabled?).to be false
    end

    it 'returns false when private_netboot is false' do
      instance = build(:system_node_instance, node: node, variety: 'physical', private_netboot: false)
      expect(instance.netboot_enabled?).to be false
    end
  end

  describe '#enable_netboot!' do
    it 'enables netboot for physical instances' do
      instance = create(:system_node_instance, :physical, node: node, private_netboot: false)
      instance.enable_netboot!

      expect(instance.reload.private_netboot).to be true
    end

    it 'returns false for cloud instances' do
      instance = create(:system_node_instance, node: node, variety: 'cloud', private_netboot: false)
      result = instance.enable_netboot!

      expect(result).to be false
      expect(instance.reload.private_netboot).to be false
    end
  end

  describe '#disable_netboot!' do
    it 'disables netboot' do
      instance = create(:system_node_instance, :physical, node: node, private_netboot: true)
      instance.disable_netboot!

      expect(instance.reload.private_netboot).to be false
    end
  end

  describe 'factory traits' do
    describe ':with_coordinates' do
      it 'creates instance with San Francisco coordinates' do
        instance = create(:system_node_instance, :with_coordinates, node: node)
        expect(instance.latitude).to eq(37.7749)
        expect(instance.longitude).to eq(-122.4194)
      end
    end

    describe ':with_mac_address' do
      it 'creates instance with MAC address' do
        instance = create(:system_node_instance, :with_mac_address, node: node)
        expect(instance.mac_address).to eq('00:11:22:33:44:55')
      end
    end

    describe ':with_netboot' do
      it 'creates physical instance with netboot enabled' do
        instance = create(:system_node_instance, :with_netboot, node: node)
        expect(instance.variety).to eq('physical')
        expect(instance.private_netboot).to be true
        expect(instance.mac_address).to be_present
      end
    end
  end
end

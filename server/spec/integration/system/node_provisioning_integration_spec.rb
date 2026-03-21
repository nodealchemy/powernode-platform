# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Node Provisioning Integration', type: :integration do
  let(:account) { create(:account) }
  let(:provider) { create(:system_provider, account: account, provider_type: 'aws') }
  let(:region) { create(:system_provider_region, account: account, provider: provider) }
  let(:instance_type) { create(:system_provider_instance_type, account: account, provider: provider) }
  let(:architecture) { create(:system_node_architecture, :with_checksums, account: account) }
  let(:platform) { create(:system_node_platform, account: account, node_architecture: architecture) }
  let(:template) { create(:system_node_template, account: account, node_platform: platform) }
  let(:node) { create(:system_node, account: account, node_template: template) }

  describe 'node creation workflow' do
    it 'creates node with complete hierarchy' do
      # Verify the hierarchy is properly established
      expect(node.node_template).to eq(template)
      expect(template.node_platform).to eq(platform)
      expect(platform.node_architecture).to eq(architecture)
      expect(node.account).to eq(account)
    end

    it 'supports runtime tracking' do
      node = create(:system_node, account: account, node_template: template, runtime_amount: 0)

      # Simulate runtime increments
      node.increment_runtime!(60)
      expect(node.reload.runtime_amount).to eq(60)
      expect(node.runtime_hours).to eq(1.0)

      node.increment_runtime!(30)
      expect(node.reload.runtime_amount).to eq(90)
      expect(node.runtime_hours).to eq(1.5)
    end

    it 'supports tmpfs configuration' do
      node = create(:system_node, account: account, node_template: template, tmpfs_store: false)

      expect(node.uses_tmpfs?).to be false

      node.enable_tmpfs!
      expect(node.reload.uses_tmpfs?).to be true

      node.disable_tmpfs!
      expect(node.reload.uses_tmpfs?).to be false
    end
  end

  describe 'instance provisioning workflow' do
    it 'creates cloud instance with full configuration' do
      instance = create(:system_node_instance,
                        node: node,
                        provider_region: region,
                        provider_instance_type: instance_type,
                        variety: 'cloud',
                        status: 'pending')

      expect(instance.cloud?).to be true
      expect(instance.pending?).to be true
      expect(instance.account).to eq(account)
    end

    it 'tracks instance through provisioning states' do
      instance = create(:system_node_instance, node: node, status: 'pending')

      # Pending -> Provisioning
      instance.update!(status: 'provisioning')
      expect(instance.provisioning?).to be true

      # Provisioning -> Running (using valid status from STATUSES constant)
      instance.update!(status: 'running',
                       private_ip_address: '10.0.1.100',
                       public_ip_address: '203.0.113.50')
      expect(instance.running?).to be true
      expect(instance.active?).to be true
    end

    it 'supports physical instances with netboot' do
      instance = create(:system_node_instance,
                        node: node,
                        variety: 'physical',
                        mac_address: '00:11:22:33:44:55',
                        private_netboot: false)

      expect(instance.physical?).to be true
      expect(instance.netboot_enabled?).to be false

      instance.enable_netboot!
      expect(instance.netboot_enabled?).to be true
      expect(instance.normalized_mac_address).to eq('00:11:22:33:44:55')
    end

    it 'supports geolocation tracking' do
      instance = create(:system_node_instance, node: node)

      expect(instance.has_coordinates?).to be false

      instance.set_coordinates!(37.7749, -122.4194)
      expect(instance.has_coordinates?).to be true
      expect(instance.coordinates).to eq({ latitude: 37.7749, longitude: -122.4194 })
    end

    describe 'instance control operations' do
      let(:instance) { create(:system_node_instance, :running, node: node) }

      it 'validates control operations based on state' do
        # Running instance can stop/reboot
        expect(instance.can_stop?).to be true
        expect(instance.can_reboot?).to be true
        expect(instance.can_start?).to be false
        expect(instance.can_terminate?).to be true

        # Stop the instance
        instance.update!(status: 'stopped')
        expect(instance.can_start?).to be true
        expect(instance.can_stop?).to be false
        expect(instance.can_reboot?).to be false
        expect(instance.can_terminate?).to be true
      end

      it 'terminates instance' do
        instance.update!(status: 'terminated')
        expect(instance.terminated?).to be true
        expect(instance.active?).to be false
      end
    end
  end

  describe 'module assignment workflow' do
    let!(:base_module) { create(:system_node_module, account: account, node_platform: platform, name: 'base', priority: 100) }
    let!(:app_module) { create(:system_node_module, account: account, node_platform: platform, name: 'app', priority: 50) }

    before do
      create(:system_module_dependency, node_module: app_module, dependency: base_module, required: true)
    end

    it 'assigns modules to node with dependency resolution' do
      # Assign modules to node
      create(:system_node_module_assignment, node: node, node_module: base_module, enabled: true)
      create(:system_node_module_assignment, node: node, node_module: app_module, enabled: true)

      # Resolve dependencies for the node
      result = System::DependencyResolutionService.resolve_for_node(node)

      expect(result.success?).to be true
      expect(result.modules.map(&:id)).to include(base_module.id, app_module.id)
    end

    it 'detects missing dependencies in node configuration' do
      # Only assign app_module without its required dependency
      create(:system_node_module_assignment, node: node, node_module: app_module, enabled: true)

      result = System::DependencyResolutionService.resolve_for_node(node)

      expect(result.success?).to be false
      expect(result.errors.any? { |e| e[:type] == :missing_required }).to be true
    end
  end

  describe 'operation tracking' do
    let(:instance) { create(:system_node_instance, :running, node: node) }

    it 'tracks operations through complete lifecycle' do
      # Create pending operation
      operation = create(:system_operation,
                         account: account,
                         operable: instance,
                         command: 'sync',
                         status: 'pending')

      expect(operation.pending?).to be true

      # Start operation
      operation.update!(status: 'running', started_at: Time.current)
      expect(operation.running?).to be true

      # Complete operation
      operation.update!(status: 'complete', completed_at: Time.current, progress: 100)
      expect(operation.complete?).to be true
    end

    it 'handles operation failure' do
      operation = create(:system_operation, :running, account: account, operable: instance)

      operation.update!(
        status: 'failed',
        completed_at: Time.current,
        error_message: 'Connection timeout'
      )

      expect(operation.failed?).to be true
      expect(operation.error_message).to eq('Connection timeout')
    end

    it 'associates operations with both node and instance' do
      node_operation = create(:system_operation, account: account, operable: node, command: 'configure')
      instance_operation = create(:system_operation, account: account, operable: instance, command: 'sync')

      expect(node.operations).to include(node_operation)
      expect(instance.operations).to include(instance_operation)
    end
  end

  describe 'boot image verification' do
    let(:kernel_checksum) { Digest::SHA256.hexdigest('kernel_content') }
    let(:image_checksum) { Digest::SHA256.hexdigest('image_content') }

    it 'verifies boot image checksums' do
      architecture.update!(
        kernel_checksum: kernel_checksum,
        image_checksum: image_checksum,
        kernel_version: '5.15.0-generic',
        image_format: 'qcow2'
      )

      # Verify correct checksums
      expect(architecture.verify_kernel_checksum(kernel_checksum)).to be true
      expect(architecture.verify_image_checksum(image_checksum)).to be true

      # Reject incorrect checksums
      expect(architecture.verify_kernel_checksum('wrong')).to be false
      expect(architecture.verify_image_checksum('wrong')).to be false
    end

    it 'provides boot files information' do
      info = architecture.boot_files_info

      expect(info[:kernel][:version]).to be_present
      expect(info[:image][:format]).to be_present
    end
  end

  describe 'multi-instance node' do
    it 'supports multiple instances per node' do
      instance1 = create(:system_node_instance, node: node, name: 'web-1')
      instance2 = create(:system_node_instance, node: node, name: 'web-2')
      instance3 = create(:system_node_instance, node: node, name: 'web-3')

      expect(node.node_instances.count).to eq(3)
      expect(node.node_instances.pluck(:name)).to contain_exactly('web-1', 'web-2', 'web-3')
    end

    it 'destroys instances when node is destroyed' do
      instance = create(:system_node_instance, node: node)
      instance_id = instance.id

      node.destroy!

      expect(System::NodeInstance.exists?(instance_id)).to be false
    end
  end

  describe 'mount point configuration' do
    let(:mount_point) { create(:system_node_mount_point, account: account, mount_path: '/data') }
    let(:instance) { create(:system_node_instance, node: node) }

    it 'assigns mount points to instance' do
      instance_mount = create(:system_instance_mount_point,
                              node_instance: instance,
                              mount_point: mount_point,
                              enabled: true)

      expect(instance.mount_points).to include(mount_point)
      expect(instance.instance_mount_points.count).to eq(1)
    end
  end
end

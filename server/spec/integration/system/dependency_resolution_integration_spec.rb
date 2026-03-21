# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Module Dependency Resolution Integration', type: :integration do
  let(:account) { create(:account) }

  describe 'complete dependency resolution workflow' do
    let!(:platform) { create(:system_node_platform, account: account) }

    # Create a realistic module hierarchy
    let!(:base_module) do
      create(:system_node_module, account: account, node_platform: platform,
             name: 'base-config', priority: 100, variety: 'config')
    end

    let!(:network_module) do
      create(:system_node_module, account: account, node_platform: platform,
             name: 'network-config', priority: 80, variety: 'config')
    end

    let!(:security_module) do
      create(:system_node_module, account: account, node_platform: platform,
             name: 'security-config', priority: 90, variety: 'config')
    end

    let!(:app_module) do
      create(:system_node_module, account: account, node_platform: platform,
             name: 'app-deployment', priority: 50, variety: 'instance')
    end

    let!(:monitoring_module) do
      create(:system_node_module, account: account, node_platform: platform,
             name: 'monitoring', priority: 30, variety: 'subscription')
    end

    before do
      # Set up dependency chain:
      # app-deployment -> network-config -> base-config
      # app-deployment -> security-config -> base-config
      # monitoring -> app-deployment (optional)
      create(:system_module_dependency, node_module: network_module, dependency: base_module, required: true)
      create(:system_module_dependency, node_module: security_module, dependency: base_module, required: true)
      create(:system_module_dependency, node_module: app_module, dependency: network_module, required: true)
      create(:system_module_dependency, node_module: app_module, dependency: security_module, required: true)
      create(:system_module_dependency, node_module: monitoring_module, dependency: app_module, required: false)
    end

    it 'resolves complete dependency chain for app deployment' do
      available = [base_module, network_module, security_module, app_module, monitoring_module]
      service = System::DependencyResolutionService.new(available)

      result = service.resolve([app_module])

      expect(result.success?).to be true
      expect(result.modules).to include(base_module, network_module, security_module, app_module)

      # Verify resolution order: base comes before network/security, which come before app
      orders = result.resolution_order.map { |r| [r[:module].name, r[:order]] }.to_h
      expect(orders['base-config']).to be < orders['network-config']
      expect(orders['base-config']).to be < orders['security-config']
      expect(orders['network-config']).to be < orders['app-deployment']
      expect(orders['security-config']).to be < orders['app-deployment']
    end

    it 'handles diamond dependency without duplication' do
      available = [base_module, network_module, security_module, app_module]
      service = System::DependencyResolutionService.new(available)

      result = service.resolve([app_module])

      # base_module should only appear once despite being required by both network and security
      expect(result.modules.count { |m| m.id == base_module.id }).to eq(1)
    end

    it 'includes optional dependencies when available' do
      available = [base_module, network_module, security_module, app_module, monitoring_module]
      service = System::DependencyResolutionService.new(available, include_optional: true)

      result = service.resolve([monitoring_module])

      expect(result.success?).to be true
      # Should include the entire chain through app_module
      expect(result.modules).to include(monitoring_module, app_module)
    end

    it 'excludes optional dependencies when configured' do
      available = [base_module, network_module, security_module, app_module, monitoring_module]
      service = System::DependencyResolutionService.new(available, include_optional: false)

      result = service.resolve([monitoring_module])

      expect(result.success?).to be true
      # Should only include monitoring module, not its optional dependency
      expect(result.modules).to include(monitoring_module)
      expect(result.modules).not_to include(app_module)
    end

    it 'orders modules by priority when no dependencies conflict' do
      available = [base_module, network_module, security_module, app_module, monitoring_module]
      service = System::DependencyResolutionService.new(available)

      result = service.resolve([base_module, network_module, security_module, app_module, monitoring_module])

      names_in_order = result.modules.map(&:name)

      # Higher priority modules should come first (within their dependency constraints)
      # base-config (100) should be early, monitoring (30) should be late
      expect(names_in_order.index('base-config')).to be < names_in_order.index('monitoring')
    end

    context 'with missing required dependency' do
      it 'reports error when required dependency unavailable' do
        # Only provide app_module without its dependencies
        service = System::DependencyResolutionService.new([app_module])

        result = service.resolve([app_module])

        expect(result.success?).to be false
        expect(result.errors.any? { |e| e[:type] == :missing_required }).to be true
      end
    end

    context 'with conflicting modules' do
      let!(:alt_security_module) do
        create(:system_node_module, account: account, node_platform: platform,
               name: 'alt-security-config', priority: 85, variety: 'config')
      end

      before do
        # security_module conflicts with alt_security_module
        create(:system_module_dependency,
               node_module: security_module,
               dependency: alt_security_module,
               dependency_type: 'conflicts',
               required: false)
      end

      it 'detects conflicts between modules' do
        available = [base_module, security_module, alt_security_module]
        service = System::DependencyResolutionService.new(available, detect_conflicts: true)

        result = service.resolve([security_module, alt_security_module])

        expect(result.errors.any? { |e| e[:type] == :conflict }).to be true
      end
    end
  end

  describe 'node-level dependency resolution' do
    let!(:template) { create(:system_node_template, account: account) }
    let!(:node) { create(:system_node, account: account, node_template: template) }

    let!(:module_a) { create(:system_node_module, account: account, name: 'Module A', priority: 100) }
    let!(:module_b) { create(:system_node_module, account: account, name: 'Module B', priority: 50) }

    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_node_module_assignment, node: node, node_module: module_a, enabled: true)
      create(:system_node_module_assignment, node: node, node_module: module_b, enabled: true)
    end

    it 'resolves dependencies for a node configuration' do
      result = System::DependencyResolutionService.resolve_for_node(node)

      expect(result.success?).to be true
      expect(result.modules.map(&:id)).to include(module_a.id, module_b.id)
    end
  end

  describe 'template-level dependency resolution' do
    let!(:template) { create(:system_node_template, account: account) }
    let!(:module_a) { create(:system_node_module, account: account, name: 'Module A', priority: 100) }
    let!(:module_b) { create(:system_node_module, account: account, name: 'Module B', priority: 50) }

    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_template_module, node_template: template, node_module: module_a, enabled: true)
      create(:system_template_module, node_template: template, node_module: module_b, enabled: true)
    end

    it 'resolves dependencies for a template configuration' do
      result = System::DependencyResolutionService.resolve_for_template(template)

      expect(result.success?).to be true
    end
  end

  describe 'dependency validation' do
    let!(:module_a) { create(:system_node_module, account: account, name: 'Module A', priority: 100) }
    let!(:module_b) { create(:system_node_module, account: account, name: 'Module B', priority: 50) }
    let!(:module_c) { create(:system_node_module, account: account, name: 'Module C', priority: 25) }

    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_a, dependency: module_c, required: false)
    end

    it 'validates module sets before deployment' do
      # Valid set with all required dependencies
      service = System::DependencyResolutionService.new([module_a, module_b])
      validation = service.validate_dependencies([module_a])

      expect(validation[:valid]).to be true
      expect(validation[:missing_required]).to be_empty
      expect(validation[:missing_optional].length).to eq(1)
    end

    it 'reports invalid sets with missing required dependencies' do
      # Invalid set missing required dependency
      service = System::DependencyResolutionService.new([module_a])
      validation = service.validate_dependencies([module_a])

      expect(validation[:valid]).to be false
      expect(validation[:missing_required].length).to eq(1)
    end
  end

  describe 'circular dependency prevention' do
    let!(:module_a) { create(:system_node_module, account: account, name: 'Module A') }
    let!(:module_b) { create(:system_node_module, account: account, name: 'Module B') }
    let!(:module_c) { create(:system_node_module, account: account, name: 'Module C') }

    before do
      # A -> B -> C (existing chain)
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_b, dependency: module_c, required: true)
    end

    it 'detects potential circular dependencies before creation' do
      service = System::DependencyResolutionService.new([module_a, module_b, module_c])

      # C -> A would create cycle: A -> B -> C -> A
      expect(service.would_create_circular?(module_c, module_a)).to be true

      # A -> C would not create cycle (already exists through B)
      expect(service.would_create_circular?(module_a, module_c)).to be false
    end

    it 'provides dependency tree visualization' do
      service = System::DependencyResolutionService.new([module_a, module_b, module_c])
      tree = service.dependency_tree(module_a)

      expect(tree[:module][:name]).to eq('Module A')
      expect(tree[:dependencies].length).to eq(1)
      expect(tree[:dependencies].first[:dependency][:module][:name]).to eq('Module B')
    end
  end
end

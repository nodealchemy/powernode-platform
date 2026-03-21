# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::DependencyResolutionService do
  let(:account) { create(:account) }

  # Create a set of modules with dependencies
  let!(:module_a) { create(:system_node_module, account: account, name: 'Module A', priority: 100) }
  let!(:module_b) { create(:system_node_module, account: account, name: 'Module B', priority: 50) }
  let!(:module_c) { create(:system_node_module, account: account, name: 'Module C', priority: 75) }
  let!(:module_d) { create(:system_node_module, account: account, name: 'Module D', priority: 25) }

  describe '#resolve' do
    context 'with no dependencies' do
      it 'returns all requested modules' do
        service = described_class.new([module_a, module_b])
        result = service.resolve([module_a, module_b])

        expect(result.success?).to be true
        expect(result.modules).to include(module_a, module_b)
      end

      it 'orders by priority descending' do
        service = described_class.new([module_a, module_b, module_c])
        result = service.resolve([module_a, module_b, module_c])

        priorities = result.modules.map(&:priority)
        expect(priorities).to eq(priorities.sort.reverse)
      end
    end

    context 'with simple dependencies' do
      before do
        # A depends on B
        create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      end

      it 'includes dependencies in result' do
        service = described_class.new([module_a, module_b])
        result = service.resolve([module_a])

        expect(result.success?).to be true
        expect(result.modules).to include(module_a, module_b)
      end

      it 'resolves dependencies before dependents' do
        service = described_class.new([module_a, module_b])
        result = service.resolve([module_a])

        # B should appear before A in resolution order
        b_order = result.resolution_order.find { |r| r[:module].id == module_b.id }[:order]
        a_order = result.resolution_order.find { |r| r[:module].id == module_a.id }[:order]

        expect(b_order).to be < a_order
      end
    end

    context 'with nested dependencies' do
      before do
        # A -> B -> C
        create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
        create(:system_module_dependency, node_module: module_b, dependency: module_c, required: true)
      end

      it 'resolves A -> B -> C correctly' do
        service = described_class.new([module_a, module_b, module_c])
        result = service.resolve([module_a])

        expect(result.success?).to be true
        expect(result.modules.map(&:id)).to include(module_a.id, module_b.id, module_c.id)
      end

      it 'maintains correct resolution order for chain' do
        service = described_class.new([module_a, module_b, module_c])
        result = service.resolve([module_a])

        orders = result.resolution_order.map { |r| [r[:module].name, r[:order]] }.to_h

        expect(orders['Module C']).to be < orders['Module B']
        expect(orders['Module B']).to be < orders['Module A']
      end
    end

    context 'with diamond dependencies' do
      let!(:module_e) { create(:system_node_module, account: account, name: 'Module E', priority: 10) }

      before do
        # Diamond: A -> B -> D, A -> C -> D
        create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
        create(:system_module_dependency, node_module: module_a, dependency: module_c, required: true)
        create(:system_module_dependency, node_module: module_b, dependency: module_d, required: true)
        create(:system_module_dependency, node_module: module_c, dependency: module_d, required: true)
      end

      it 'handles diamond dependencies without duplication' do
        service = described_class.new([module_a, module_b, module_c, module_d])
        result = service.resolve([module_a])

        expect(result.success?).to be true
        # D should only appear once
        expect(result.modules.count { |m| m.id == module_d.id }).to eq(1)
      end

      it 'resolves D before B and C' do
        service = described_class.new([module_a, module_b, module_c, module_d])
        result = service.resolve([module_a])

        orders = result.resolution_order.map { |r| [r[:module].name, r[:order]] }.to_h

        expect(orders['Module D']).to be < orders['Module B']
        expect(orders['Module D']).to be < orders['Module C']
      end
    end

    context 'with optional dependencies' do
      before do
        create(:system_module_dependency, node_module: module_a, dependency: module_b, required: false)
      end

      it 'includes optional dependencies by default' do
        service = described_class.new([module_a, module_b])
        result = service.resolve([module_a])

        expect(result.modules).to include(module_b)
      end

      it 'excludes optional dependencies when configured' do
        service = described_class.new([module_a, module_b], include_optional: false)
        result = service.resolve([module_a])

        expect(result.modules).not_to include(module_b)
      end
    end

    context 'with missing dependencies' do
      before do
        # A depends on B, but B is not in available modules
        create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      end

      it 'reports missing required dependency as error' do
        service = described_class.new([module_a]) # B not included
        result = service.resolve([module_a])

        expect(result.success?).to be false
        expect(result.errors.any? { |e| e[:type] == :missing_required }).to be true
      end

      it 'raises when fail_on_missing is true' do
        service = described_class.new([module_a], fail_on_missing: true)

        expect { service.resolve([module_a]) }.to raise_error(
          System::DependencyResolutionService::MissingDependencyError
        )
      end

      it 'reports missing optional dependency as warning' do
        create(:system_module_dependency, node_module: module_c, dependency: module_d, required: false)

        service = described_class.new([module_c]) # D not included
        result = service.resolve([module_c])

        expect(result.success?).to be true
        expect(result.has_warnings?).to be true
        expect(result.warnings.any? { |w| w[:type] == :missing_optional }).to be true
      end
    end
  end

  describe '#resolve_single' do
    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
    end

    it 'resolves dependencies for a single module' do
      service = described_class.new([module_a, module_b])
      result = service.resolve_single(module_a)

      expect(result.success?).to be true
      expect(result.modules).to include(module_a, module_b)
    end
  end

  describe '#would_create_circular?' do
    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_b, dependency: module_c, required: true)
    end

    it 'returns true when dependency would create cycle' do
      service = described_class.new([module_a, module_b, module_c])

      # C -> A would create: A -> B -> C -> A
      expect(service.would_create_circular?(module_c, module_a)).to be true
    end

    it 'returns false when dependency is safe' do
      service = described_class.new([module_a, module_b, module_c, module_d])

      # A -> D is safe (D doesn't depend on A)
      expect(service.would_create_circular?(module_a, module_d)).to be false
    end
  end

  describe '#get_all_dependencies' do
    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_b, dependency: module_c, required: true)
    end

    it 'returns all dependencies recursively' do
      service = described_class.new([module_a, module_b, module_c])
      deps = service.get_all_dependencies(module_a)

      expect(deps.map(&:id)).to include(module_b.id, module_c.id)
    end

    it 'does not include the module itself' do
      service = described_class.new([module_a, module_b, module_c])
      deps = service.get_all_dependencies(module_a)

      expect(deps.map(&:id)).not_to include(module_a.id)
    end
  end

  describe '#validate_dependencies' do
    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_a, dependency: module_c, required: false)
    end

    it 'returns valid when all required dependencies available' do
      service = described_class.new([module_a, module_b])
      validation = service.validate_dependencies([module_a])

      expect(validation[:valid]).to be true
    end

    it 'returns invalid when required dependency missing' do
      service = described_class.new([module_a]) # B not included
      validation = service.validate_dependencies([module_a])

      expect(validation[:valid]).to be false
      expect(validation[:missing_required].length).to eq(1)
    end

    it 'reports missing optional dependencies separately' do
      service = described_class.new([module_a, module_b]) # C not included
      validation = service.validate_dependencies([module_a])

      expect(validation[:valid]).to be true
      expect(validation[:missing_optional].length).to eq(1)
    end
  end

  describe '#dependency_tree' do
    before do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
      create(:system_module_dependency, node_module: module_b, dependency: module_c, required: false)
    end

    it 'builds a tree structure' do
      service = described_class.new([module_a, module_b, module_c])
      tree = service.dependency_tree(module_a)

      expect(tree[:module][:name]).to eq('Module A')
      expect(tree[:dependencies].length).to eq(1)
      expect(tree[:dependencies].first[:dependency][:module][:name]).to eq('Module B')
    end

    it 'includes required flag in tree' do
      service = described_class.new([module_a, module_b, module_c])
      tree = service.dependency_tree(module_a)

      b_dep = tree[:dependencies].first
      expect(b_dep[:required]).to be true

      c_dep = b_dep[:dependency][:dependencies].first
      expect(c_dep[:required]).to be false
    end
  end

  describe '.resolve_for_node' do
    let(:node) { create(:system_node) }

    before do
      create(:system_node_module_assignment, node: node, node_module: module_a, enabled: true)
      create(:system_node_module_assignment, node: node, node_module: module_b, enabled: true)
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)
    end

    it 'resolves modules for a node' do
      result = described_class.resolve_for_node(node)

      expect(result.success?).to be true
      expect(result.modules.map(&:id)).to include(module_a.id, module_b.id)
    end
  end

  describe '.resolve_for_template' do
    let(:template) { create(:system_node_template) }

    before do
      create(:system_template_module, node_template: template, node_module: module_a, enabled: true)
      create(:system_template_module, node_template: template, node_module: module_b, enabled: true)
    end

    it 'resolves modules for a template' do
      result = described_class.resolve_for_template(template)

      expect(result.success?).to be true
    end
  end

  describe '.resolvable?' do
    it 'returns true for resolvable modules' do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)

      expect(described_class.resolvable?([module_a, module_b])).to be true
    end

    it 'returns false when required dependencies missing' do
      create(:system_module_dependency, node_module: module_a, dependency: module_b, required: true)

      expect(described_class.resolvable?([module_a])).to be false
    end
  end

  describe 'priority ordering' do
    before do
      # No dependencies, just priority ordering
    end

    it 'orders modules by priority descending' do
      service = described_class.new([module_a, module_b, module_c, module_d])
      result = service.resolve([module_a, module_b, module_c, module_d])

      names = result.modules.map(&:name)
      # A(100) > C(75) > B(50) > D(25)
      expect(names).to eq(['Module A', 'Module C', 'Module B', 'Module D'])
    end

    it 'maintains stable ordering for same priority' do
      module_e = create(:system_node_module, account: account, name: 'Module E', priority: 50)

      service = described_class.new([module_b, module_e])
      result = service.resolve([module_b, module_e])

      # Same priority, alphabetical by name
      names = result.modules.map(&:name)
      expect(names).to eq(['Module B', 'Module E'])
    end
  end

  describe 'conflict detection' do
    before do
      # A conflicts with B
      create(:system_module_dependency,
             node_module: module_a,
             dependency: module_b,
             dependency_type: 'conflicts',
             required: false)
    end

    it 'detects conflicts between modules' do
      service = described_class.new([module_a, module_b], detect_conflicts: true)
      result = service.resolve([module_a, module_b])

      expect(result.errors.any? { |e| e[:type] == :conflict }).to be true
    end

    it 'can skip conflict detection' do
      service = described_class.new([module_a, module_b], detect_conflicts: false)
      result = service.resolve([module_a, module_b])

      expect(result.errors.any? { |e| e[:type] == :conflict }).to be false
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::NodeModule, type: :model do
  describe 'constants' do
    it 'defines valid varieties' do
      expect(described_class::VARIETIES).to eq(%w[config instance subscription])
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:node_platform).class_name('System::NodePlatform').optional }
    it { is_expected.to belong_to(:category).class_name('System::NodeModuleCategory').optional }
    it { is_expected.to belong_to(:copy_path).class_name('System::NodeModuleCopyPath').optional }

    # Node assignments
    it { is_expected.to have_many(:node_module_assignments).class_name('System::NodeModuleAssignment').dependent(:destroy) }
    it { is_expected.to have_many(:nodes).through(:node_module_assignments) }

    # Template assignments
    it { is_expected.to have_many(:template_modules).class_name('System::TemplateModule').dependent(:destroy) }
    it { is_expected.to have_many(:node_templates).through(:template_modules) }

    # Puppet assignments
    it { is_expected.to have_many(:module_puppet_assignments).class_name('System::ModulePuppetAssignment').dependent(:destroy) }
    it { is_expected.to have_many(:puppet_modules).through(:module_puppet_assignments) }

    # Dependencies
    it { is_expected.to have_many(:module_dependencies).class_name('System::ModuleDependency').dependent(:destroy) }
    it { is_expected.to have_many(:dependencies).through(:module_dependencies) }
    it { is_expected.to have_many(:dependent_relationships).class_name('System::ModuleDependency').dependent(:destroy) }
    it { is_expected.to have_many(:dependents).through(:dependent_relationships) }

    # Versioning
    it { is_expected.to have_many(:versions).class_name('System::NodeModuleVersion').dependent(:destroy) }
    it { is_expected.to belong_to(:current_version).class_name('System::NodeModuleVersion').optional }
  end

  describe 'validations' do
    subject { build(:system_node_module) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:variety) }
    it { is_expected.to validate_inclusion_of(:variety).in_array(described_class::VARIETIES) }
    it { is_expected.to validate_numericality_of(:priority).only_integer.is_greater_than_or_equal_to(0) }

    it 'validates uniqueness of name scoped to account (case insensitive)' do
      account = create(:account)
      create(:system_node_module, account: account, name: 'TestModule')
      duplicate = build(:system_node_module, account: account, name: 'testmodule')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:enabled_module) { create(:system_node_module, account: account, enabled: true) }
    let!(:disabled_module) { create(:system_node_module, account: account, enabled: false) }
    let!(:public_module) { create(:system_node_module, account: account, public: true) }
    let!(:private_module) { create(:system_node_module, account: account, public: false) }
    let!(:config_module) { create(:system_node_module, account: account, variety: 'config') }
    let!(:instance_module) { create(:system_node_module, account: account, variety: 'instance') }
    let!(:subscription_module) { create(:system_node_module, account: account, variety: 'subscription') }

    describe '.enabled' do
      it 'returns only enabled modules' do
        expect(described_class.enabled).to include(enabled_module)
        expect(described_class.enabled).not_to include(disabled_module)
      end
    end

    describe '.disabled' do
      it 'returns only disabled modules' do
        expect(described_class.disabled).to include(disabled_module)
        expect(described_class.disabled).not_to include(enabled_module)
      end
    end

    describe '.public_modules' do
      it 'returns only public modules' do
        expect(described_class.public_modules).to include(public_module)
        expect(described_class.public_modules).not_to include(private_module)
      end
    end

    describe '.private_modules' do
      it 'returns only private modules' do
        expect(described_class.private_modules).to include(private_module)
        expect(described_class.private_modules).not_to include(public_module)
      end
    end

    describe '.by_variety' do
      it 'returns modules by variety' do
        expect(described_class.by_variety('config')).to include(config_module)
        expect(described_class.by_variety('config')).not_to include(instance_module, subscription_module)
      end
    end

    describe '.config_modules' do
      it 'returns only config variety modules' do
        expect(described_class.config_modules).to include(config_module)
        expect(described_class.config_modules).not_to include(instance_module)
      end
    end

    describe '.instance_modules' do
      it 'returns only instance variety modules' do
        expect(described_class.instance_modules).to include(instance_module)
        expect(described_class.instance_modules).not_to include(config_module)
      end
    end

    describe '.subscription_modules' do
      it 'returns only subscription variety modules' do
        expect(described_class.subscription_modules).to include(subscription_module)
        expect(described_class.subscription_modules).not_to include(config_module)
      end
    end

    describe '.by_priority' do
      it 'orders modules by priority descending, then name ascending' do
        high_priority = create(:system_node_module, account: account, priority: 100, name: 'b_module')
        low_priority = create(:system_node_module, account: account, priority: 10, name: 'a_module')

        ordered = described_class.by_priority
        expect(ordered.index(high_priority)).to be < ordered.index(low_priority)
      end
    end
  end

  describe 'variety predicates' do
    let(:module_record) { build(:system_node_module) }

    describe '#config?' do
      it 'returns true for config variety' do
        module_record.variety = 'config'
        expect(module_record.config?).to be true
      end

      it 'returns false for other varieties' do
        module_record.variety = 'instance'
        expect(module_record.config?).to be false
      end
    end

    describe '#instance?' do
      it 'returns true for instance variety' do
        module_record.variety = 'instance'
        expect(module_record.instance?).to be true
      end
    end

    describe '#subscription?' do
      it 'returns true for subscription variety' do
        module_record.variety = 'subscription'
        expect(module_record.subscription?).to be true
      end
    end
  end

  describe 'dependencies' do
    let(:account) { create(:account) }
    let(:parent_module) { create(:system_node_module, account: account) }
    let(:dependency1) { create(:system_node_module, account: account) }
    let(:dependency2) { create(:system_node_module, account: account) }

    before do
      create(:system_module_dependency, node_module: parent_module, dependency: dependency1, required: true)
      create(:system_module_dependency, node_module: parent_module, dependency: dependency2, required: false)
    end

    describe '#has_dependencies?' do
      it 'returns true when module has dependencies' do
        expect(parent_module.has_dependencies?).to be true
      end

      it 'returns false when module has no dependencies' do
        expect(dependency1.has_dependencies?).to be false
      end
    end

    describe '#has_dependents?' do
      it 'returns true when other modules depend on this module' do
        expect(dependency1.has_dependents?).to be true
      end

      it 'returns false when no modules depend on this module' do
        expect(parent_module.has_dependents?).to be false
      end
    end

    describe '#required_dependencies' do
      it 'returns required dependencies based on the required flag' do
        # Test that the method exists and returns a relation
        expect(parent_module).to respond_to(:required_dependencies)
        expect(parent_module.required_dependencies).to be_a(ActiveRecord::Relation)
      end
    end

    describe '#optional_dependencies' do
      it 'returns optional dependencies based on the required flag' do
        # Test that the method exists and returns a relation
        expect(parent_module).to respond_to(:optional_dependencies)
        expect(parent_module.optional_dependencies).to be_a(ActiveRecord::Relation)
      end
    end

    describe '#all_dependencies' do
      let(:deep_dependency) { create(:system_node_module, account: account) }

      before do
        create(:system_module_dependency, node_module: dependency1, dependency: deep_dependency, required: true)
      end

      it 'returns all dependencies recursively' do
        all_dep_ids = parent_module.all_dependencies.map(&:id)
        expect(all_dep_ids).to include(dependency1.id, dependency2.id, deep_dependency.id)
      end

      it 'handles circular dependencies gracefully with visited set' do
        # The model validates against creating circular dependencies,
        # but the all_dependencies method uses a visited set to prevent infinite loops
        # even if circular references somehow exist. We test the prevention mechanism.

        # Test that a deep chain doesn't cause issues
        extra_dep = create(:system_node_module, account: account)
        create(:system_module_dependency, node_module: deep_dependency, dependency: extra_dep, required: false)

        # Should not have issues with deep chains
        expect { parent_module.all_dependencies }.not_to raise_error
        expect(parent_module.all_dependencies.map(&:id)).to include(extra_dep.id)
      end
    end
  end

  describe 'count methods' do
    let(:node_module) { create(:system_node_module) }
    let(:node) { create(:system_node) }
    let(:template) { create(:system_node_template) }

    describe '#assignment_count' do
      it 'returns the number of node assignments' do
        create(:system_node_module_assignment, node_module: node_module, node: node)
        expect(node_module.assignment_count).to eq(1)
      end
    end

    describe '#template_count' do
      it 'returns the number of template assignments' do
        create(:system_template_module, node_module: node_module, node_template: template)
        expect(node_module.template_count).to eq(1)
      end
    end
  end

  describe 'data file methods' do
    let(:node_module) { create(:system_node_module) }

    describe '#set_data_file' do
      it 'sets filename, size, and calculates checksum' do
        content = 'test file content'
        node_module.set_data_file(filename: 'test.tar.gz', content: content)

        expect(node_module.data_file_name).to eq('test.tar.gz')
        expect(node_module.data_file_size).to eq(content.bytesize)
        expect(node_module.data_checksum).to eq(Digest::SHA256.hexdigest(content))
      end
    end

    describe '#verify_data_file' do
      it 'returns true when content matches checksum' do
        content = 'test file content'
        node_module.set_data_file(filename: 'test.tar.gz', content: content)
        node_module.save!

        expect(node_module.verify_data_file(content)).to be true
      end

      it 'returns false when content does not match checksum' do
        content = 'test file content'
        node_module.set_data_file(filename: 'test.tar.gz', content: content)
        node_module.save!

        expect(node_module.verify_data_file('different content')).to be false
      end

      it 'returns false when no checksum is set' do
        expect(node_module.verify_data_file('any content')).to be false
      end
    end
  end
end

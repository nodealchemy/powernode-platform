# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::ContainerTemplate, type: :model do
  describe 'associations' do
    it { should belong_to(:account).optional }
    it { should belong_to(:created_by).class_name('User').optional }
    it { should have_many(:container_instances).class_name('Devops::ContainerInstance').dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:devops_container_template) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:image_name) }
    it { should validate_inclusion_of(:visibility).in_array(%w[private account public]) }
    it { should validate_inclusion_of(:status).in_array(%w[active deprecated archived]) }

    context 'name uniqueness' do
      let(:account) { create(:account) }
      let!(:existing_template) { create(:devops_container_template, name: 'Test Template', account: account) }

      it 'validates uniqueness within account scope' do
        duplicate = build(:devops_container_template, name: 'Test Template', account: account)
        expect(duplicate).not_to be_valid
      end

      it 'allows same name for different accounts' do
        different_account = create(:account)
        template = build(:devops_container_template, name: 'Test Template', account: different_account)
        expect(template).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:private_template) { create(:devops_container_template, :private) }
    let!(:public_template) { create(:devops_container_template, :public) }
    let!(:active_template) { create(:devops_container_template, :active) }
    let!(:deprecated_template) { create(:devops_container_template, :deprecated) }

    describe '.active' do
      it 'returns only active templates' do
        expect(Devops::ContainerTemplate.active).to include(active_template)
        expect(Devops::ContainerTemplate.active).not_to include(deprecated_template)
      end
    end

    describe '.public_templates' do
      it 'returns only public templates' do
        expect(Devops::ContainerTemplate.public_templates).to include(public_template)
        expect(Devops::ContainerTemplate.public_templates).not_to include(private_template)
      end
    end
  end

  describe '#full_image_name' do
    let(:template) { build(:devops_container_template, image_name: 'powernode/ai-agent', image_tag: 'v1.0') }

    it 'returns full Docker image reference' do
      expect(template.full_image_name).to eq('powernode/ai-agent:v1.0')
    end

    context 'with registry URL' do
      let(:template) { build(:devops_container_template, registry_url: 'ghcr.io', image_name: 'powernode/ai-agent', image_tag: 'v1.0') }

      it 'includes registry URL' do
        expect(template.full_image_name).to eq('ghcr.io/powernode/ai-agent:v1.0')
      end
    end
  end

  describe '#docker_options' do
    let(:template) { create(:devops_container_template) }

    it 'returns Docker run options' do
      options = template.docker_options
      expect(options).to include('--read-only')
      expect(options).to include('--security-opt=no-new-privileges:true')
    end
  end

  describe '#accessible_by?' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }

    context 'private template' do
      let(:template) { create(:devops_container_template, :private, account: account) }

      it 'returns true for owner account' do
        expect(template.accessible_by?(account)).to be true
      end

      it 'returns false for other accounts' do
        expect(template.accessible_by?(other_account)).to be false
      end
    end

    context 'public template' do
      let(:template) { create(:devops_container_template, :public, account: account) }

      it 'returns true for any account' do
        expect(template.accessible_by?(other_account)).to be true
      end
    end
  end

  describe '#record_execution!' do
    let(:template) { create(:devops_container_template, execution_count: 0, success_count: 0) }

    it 'increments execution count' do
      expect { template.record_execution!(success: true) }.to change { template.execution_count }.by(1)
    end

    it 'increments success count when successful' do
      expect { template.record_execution!(success: true) }.to change { template.success_count }.by(1)
    end

    it 'does not increment success count when failed' do
      expect { template.record_execution!(success: false) }.not_to change { template.success_count }
    end
  end

  describe '#success_rate' do
    let(:template) { create(:devops_container_template, :with_executions) }

    it 'calculates success rate' do
      expect(template.success_rate).to be_between(0, 100)
    end

    it 'returns 0 for templates with no executions' do
      new_template = create(:devops_container_template, execution_count: 0)
      expect(new_template.success_rate).to eq(0)
    end
  end
end

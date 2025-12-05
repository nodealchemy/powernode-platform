# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowTemplate, type: :model do
  subject(:template) { build(:ai_workflow_template) }

  describe 'associations' do
    it { is_expected.to have_many(:installations).class_name('AiWorkflowTemplateInstallation').dependent(:destroy) }
    it { is_expected.to have_many(:workflows).class_name('AiWorkflow').dependent(:nullify) }
    it { is_expected.to have_many(:accounts).through(:installations) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_presence_of(:template_version) }
    it { is_expected.to validate_presence_of(:configuration) }

    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:template_version) }
    it { is_expected.to validate_inclusion_of(:category).in_array(%w[content_generation data_processing customer_support automation analytics integration]) }

    context 'template_version format validation' do
      it 'accepts valid semantic versions' do
        valid_versions = ['1.0.0', '2.1.3', '10.20.30', '1.0.0-beta', '2.0.0-rc.1']
        
        valid_versions.each do |version|
          template = build(:ai_workflow_template, template_version: version)
          expect(template).to be_valid, "Expected '#{version}' to be valid"
        end
      end

      it 'rejects invalid version formats' do
        invalid_versions = ['1.0', 'v1.0.0', '1.0.0.0', 'invalid', '']
        
        invalid_versions.each do |version|
          template = build(:ai_workflow_template, template_version: version)
          expect(template).not_to be_valid, "Expected '#{version}' to be invalid"
          expect(template.errors[:template_version]).to be_present
        end
      end
    end

    context 'configuration validation' do
      it 'validates configuration is a hash' do
        template = build(:ai_workflow_template, configuration: 'not a hash')
        expect(template).not_to be_valid
        expect(template.errors[:configuration]).to include('must be a hash')
      end

      it 'validates required configuration fields' do
        template = build(:ai_workflow_template, configuration: {})
        expect(template).not_to be_valid
        expect(template.errors[:configuration]).to include('must contain required fields: nodes, variables, metadata')
      end

      it 'validates nodes structure in configuration' do
        invalid_config = {
          nodes: 'invalid',
          variables: [],
          metadata: {}
        }
        
        template = build(:ai_workflow_template, configuration: invalid_config)
        expect(template).not_to be_valid
        expect(template.errors[:configuration]).to include('nodes must be an array')
      end

      it 'accepts valid configuration structure' do
        valid_config = {
          nodes: [
            {
              id: 'node_1',
              type: 'ai_agent',
              name: 'Content Generator',
              configuration: { model: 'gpt-4', temperature: 0.7 }
            }
          ],
          variables: [
            {
              name: 'topic',
              type: 'string',
              required: true,
              description: 'Content topic'
            }
          ],
          metadata: {
            difficulty: 'beginner',
            estimated_runtime: '5 minutes'
          }
        }
        
        template = build(:ai_workflow_template, configuration: valid_config)
        expect(template).to be_valid
      end
    end

    context 'tag validation' do
      it 'validates tags is an array when present' do
        template = build(:ai_workflow_template, tags: 'not an array')
        expect(template).not_to be_valid
        expect(template.errors[:tags]).to include('must be an array')
      end

      it 'validates individual tag format' do
        template = build(:ai_workflow_template, tags: ['valid-tag', 'INVALID TAG!', 'another-valid'])
        expect(template).not_to be_valid
        expect(template.errors[:tags]).to include('contains invalid tag format')
      end

      it 'accepts valid tag arrays' do
        template = build(:ai_workflow_template, tags: ['ai', 'content-generation', 'automation'])
        expect(template).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:published_template) { create(:ai_workflow_template, is_published: true) }
    let!(:draft_template) { create(:ai_workflow_template, is_published: false) }
    let!(:featured_template) { create(:ai_workflow_template, is_featured: true) }
    let!(:content_template) { create(:ai_workflow_template, :content_generation) }
    let!(:data_template) { create(:ai_workflow_template, :data_processing) }

    describe '.published' do
      it 'returns only published templates' do
        expect(described_class.published).to include(published_template)
        expect(described_class.published).not_to include(draft_template)
      end
    end

    describe '.featured' do
      it 'returns only featured templates' do
        expect(described_class.featured).to include(featured_template)
      end
    end

    describe '.by_category' do
      it 'filters templates by category' do
        expect(described_class.by_category('content_generation')).to include(content_template)
        expect(described_class.by_category('content_generation')).not_to include(data_template)
      end
    end

    describe '.search' do
      let!(:searchable_template) { create(:ai_workflow_template, 
                                         name: 'Blog Post Generator',
                                         description: 'Creates engaging blog content') }

      it 'searches by name and description' do
        results = described_class.search('blog')
        expect(results).to include(searchable_template)
      end

      it 'searches by tags' do
        tagged_template = create(:ai_workflow_template, tags: ['seo', 'marketing'])
        results = described_class.search('seo')
        expect(results).to include(tagged_template)
      end
    end

    describe '.popular' do
      let!(:popular_template) { create(:ai_workflow_template) }
      
      before do
        create_list(:ai_workflow_template_installation, 10, ai_workflow_template: popular_template)
      end

      it 'orders templates by installation count' do
        popular_templates = described_class.popular
        expect(popular_templates.first).to eq(popular_template)
      end
    end

    describe '.compatible_version' do
      let!(:v1_template) { create(:ai_workflow_template, template_version: '1.0.0') }
      let!(:v2_template) { create(:ai_workflow_template, name: 'Different Template', template_version: '2.0.0') }

      it 'finds templates compatible with version range' do
        compatible = described_class.compatible_version('>=1.0.0 <2.0.0')
        expect(compatible).to include(v1_template)
        expect(compatible).not_to include(v2_template)
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation' do
      it 'normalizes name and category' do
        template = build(:ai_workflow_template, 
                        name: '  Blog Generator  ',
                        category: '  CONTENT_GENERATION  ')
        template.valid?
        
        expect(template.name).to eq('Blog Generator')
        expect(template.category).to eq('content_generation')
      end

      it 'generates slug from name' do
        template = build(:ai_workflow_template, name: 'Advanced Blog Generator v2')
        template.valid?
        
        expect(template.slug).to eq('advanced-blog-generator-v2')
      end

      it 'ensures unique slug' do
        existing = create(:ai_workflow_template, name: 'Test Template')
        duplicate = build(:ai_workflow_template, name: 'Test Template')
        duplicate.valid?
        
        expect(duplicate.slug).to match(/^test-template-\d+$/)
      end
    end

    describe 'after_create' do
      it 'creates initial version entry' do
        expect {
          create(:ai_workflow_template)
        }.to change { AiWorkflowTemplateVersion.count }.by(1)
      end
    end

    describe 'after_update' do
      it 'creates new version when configuration changes' do
        template = create(:ai_workflow_template)
        
        expect {
          template.update!(configuration: { nodes: [], variables: [], metadata: { updated: true } })
        }.to change { template.versions.count }.by(1)
      end

      it 'does not create version for non-configuration changes' do
        template = create(:ai_workflow_template)
        
        expect {
          template.update!(description: 'Updated description')
        }.not_to change { template.versions.count }
      end
    end
  end

  describe 'instance methods' do
    describe '#install_for_account!' do
      let(:template) { create(:ai_workflow_template, :published) }
      let(:account) { create(:account) }

      it 'creates installation record' do
        expect {
          installation = template.install_for_account!(account)
          expect(installation.account).to eq(account)
          expect(installation.ai_workflow_template).to eq(template)
        }.to change { template.installations.count }.by(1)
      end

      it 'creates workflow from template' do
        expect {
          template.install_for_account!(account)
        }.to change { account.ai_workflows.count }.by(1)
        
        workflow = account.ai_workflows.last
        expect(workflow.name).to include(template.name)
        expect(workflow.template_id).to eq(template.id)
      end

      it 'allows customization during installation' do
        customizations = {
          workflow_name: 'My Custom Workflow',
          variables: { topic: 'Custom Topic' }
        }
        
        installation = template.install_for_account!(account, customizations)
        workflow = installation.created_workflow
        
        expect(workflow.name).to eq('My Custom Workflow')
        expect(workflow.input_variables['topic']).to eq('Custom Topic')
      end

      it 'prevents duplicate installations' do
        template.install_for_account!(account)
        
        expect {
          template.install_for_account!(account)
        }.to raise_error(StandardError, /already installed/i)
      end

      it 'raises error for unpublished templates' do
        draft_template = create(:ai_workflow_template, is_published: false)
        
        expect {
          draft_template.install_for_account!(account)
        }.to raise_error(StandardError, /not published/i)
      end
    end

    describe '#create_workflow_from_template' do
      let(:template) { create(:ai_workflow_template, :content_generation) }
      let(:account) { create(:account) }

      it 'creates workflow with template configuration' do
        workflow = template.create_workflow_from_template(account)
        
        expect(workflow.account).to eq(account)
        expect(workflow.template_id).to eq(template.id)
        expect(workflow.name).to include(template.name)
      end

      it 'applies customizations' do
        customizations = {
          workflow_name: 'Custom Blog Generator',
          input_variables: { style: 'formal' }
        }
        
        workflow = template.create_workflow_from_template(account, customizations)
        
        expect(workflow.name).to eq('Custom Blog Generator')
        expect(workflow.input_variables['style']).to eq('formal')
      end

      it 'validates required variables are provided' do
        template.configuration[:variables] = [
          { name: 'required_var', type: 'string', required: true }
        ]
        template.save!
        
        expect {
          template.create_workflow_from_template(account)
        }.to raise_error(StandardError, /required variables/i)
      end
    end

    describe '#installation_count' do
      let(:template) { create(:ai_workflow_template) }

      it 'returns count of successful installations' do
        create_list(:ai_workflow_template_installation, 3, ai_workflow_template: template)
        expect(template.installation_count).to eq(3)
      end

      it 'caches count for performance' do
        create_list(:ai_workflow_template_installation, 5, ai_workflow_template: template)
        
        expect(template).to receive(:installations).once.and_call_original
        2.times { template.installation_count }
      end
    end

    describe '#average_rating' do
      let(:template) { create(:ai_workflow_template) }

      before do
        create(:ai_workflow_template_installation, ai_workflow_template: template, rating: 4)
        create(:ai_workflow_template_installation, ai_workflow_template: template, rating: 5)
        create(:ai_workflow_template_installation, ai_workflow_template: template, rating: 3)
      end

      it 'calculates average rating from installations' do
        expect(template.average_rating).to eq(4.0)
      end

      it 'returns nil when no ratings exist' do
        no_ratings_template = create(:ai_workflow_template)
        expect(no_ratings_template.average_rating).to be_nil
      end
    end

    describe '#required_variables' do
      let(:template) { create(:ai_workflow_template) }

      before do
        template.configuration[:variables] = [
          { name: 'topic', type: 'string', required: true },
          { name: 'style', type: 'string', required: false },
          { name: 'length', type: 'integer', required: true }
        ]
      end

      it 'returns only required variables' do
        required = template.required_variables
        expect(required.map { |v| v[:name] }).to contain_exactly('topic', 'length')
      end
    end

    describe '#compatible_with_account?' do
      let(:template) { create(:ai_workflow_template) }
      let(:account) { create(:account) }

      it 'returns true for basic compatibility' do
        expect(template.compatible_with_account?(account)).to be true
      end

      it 'checks account tier compatibility' do
        template.requirements = { min_tier: 'premium' }
        basic_account = create(:account, tier: 'basic')
        premium_account = create(:account, tier: 'premium')
        
        expect(template.compatible_with_account?(basic_account)).to be false
        expect(template.compatible_with_account?(premium_account)).to be true
      end

      it 'checks feature requirements' do
        template.requirements = { features: ['ai_agents', 'webhooks'] }
        limited_account = create(:account, enabled_features: ['ai_agents'])
        full_account = create(:account, enabled_features: ['ai_agents', 'webhooks'])
        
        expect(template.compatible_with_account?(limited_account)).to be false
        expect(template.compatible_with_account?(full_account)).to be true
      end
    end

    describe '#duplicate_template' do
      let(:template) { create(:ai_workflow_template, :content_generation) }

      it 'creates copy with new version' do
        duplicate = template.duplicate_template(
          name: 'Enhanced Version',
          template_version: '2.0.0'
        )
        
        expect(duplicate.name).to eq('Enhanced Version')
        expect(duplicate.template_version).to eq('2.0.0')
        expect(duplicate.configuration).to eq(template.configuration)
        expect(duplicate.is_published).to be false
      end

      it 'preserves configuration and metadata' do
        duplicate = template.duplicate_template(template_version: '1.1.0')
        
        expect(duplicate.configuration).to eq(template.configuration)
        expect(duplicate.category).to eq(template.category)
        expect(duplicate.tags).to eq(template.tags)
      end
    end

    describe '#publish!' do
      let(:template) { create(:ai_workflow_template, is_published: false) }

      it 'publishes template when valid' do
        template.publish!
        expect(template.reload.is_published).to be true
        expect(template.published_at).to be_within(1.second).of(Time.current)
      end

      it 'validates template before publishing' do
        template.configuration = { invalid: 'config' }
        
        expect {
          template.publish!
        }.to raise_error(StandardError, /cannot publish invalid template/i)
      end

      it 'creates publication log entry' do
        expect {
          template.publish!
        }.to change { AiWorkflowExecutionLog.count }.by(1)
        
        log = AiWorkflowExecutionLog.last
        expect(log.message).to include('Template published')
      end
    end

    describe '#unpublish!' do
      let(:template) { create(:ai_workflow_template, is_published: true) }

      it 'unpublishes template' do
        template.unpublish!
        expect(template.reload.is_published).to be false
      end

      it 'prevents new installations' do
        account = create(:account)
        template.unpublish!
        
        expect {
          template.install_for_account!(account)
        }.to raise_error(StandardError, /not published/i)
      end
    end

    describe '#template_summary' do
      let(:template) { create(:ai_workflow_template, :content_generation) }

      before do
        create_list(:ai_workflow_template_installation, 5, ai_workflow_template: template)
      end

      it 'returns comprehensive template information' do
        summary = template.template_summary
        
        expect(summary).to include(
          :id,
          :name,
          :description,
          :category,
          :template_version,
          :installation_count,
          :average_rating,
          :is_published,
          :is_featured,
          :tags,
          :required_variables
        )
        
        expect(summary[:installation_count]).to eq(5)
        expect(summary[:category]).to eq('content_generation')
      end
    end
  end

  describe 'class methods' do
    describe '.create_from_workflow' do
      let(:workflow) { create(:ai_workflow, :with_simple_chain) }

      it 'creates template from existing workflow' do
        template = described_class.create_from_workflow(
          workflow,
          name: 'Generated Template',
          description: 'Template created from workflow',
          category: 'automation'
        )
        
        expect(template.name).to eq('Generated Template')
        expect(template.category).to eq('automation')
        expect(template.configuration[:nodes]).not_to be_empty
      end

      it 'extracts variables from workflow' do
        workflow.input_variables = { topic: 'test', style: 'formal' }
        workflow.save!
        
        template = described_class.create_from_workflow(workflow, 
          name: 'Test Template',
          category: 'content_generation')
        
        expect(template.configuration[:variables]).to include(
          hash_including(name: 'topic'),
          hash_including(name: 'style')
        )
      end
    end

    describe '.trending' do
      before do
        popular_template = create(:ai_workflow_template)
        create_list(:ai_workflow_template_installation, 10, 
                   ai_workflow_template: popular_template,
                   created_at: 1.week.ago)
        
        recent_template = create(:ai_workflow_template)
        create_list(:ai_workflow_template_installation, 5,
                   ai_workflow_template: recent_template,
                   created_at: 1.day.ago)
      end

      it 'returns templates trending by recent installations' do
        trending = described_class.trending
        expect(trending.first.installation_count).to be >= 5
      end
    end

    describe '.recommend_for_account' do
      let(:account) { create(:account) }

      before do
        # Create templates with different characteristics
        create(:ai_workflow_template, :content_generation, tags: ['marketing'])
        create(:ai_workflow_template, :data_processing, tags: ['analytics'])
        
        # Simulate account preferences
        account.update!(preferences: { categories: ['content_generation'], tags: ['marketing'] })
      end

      it 'recommends templates based on account preferences' do
        recommendations = described_class.recommend_for_account(account)
        expect(recommendations.map(&:category)).to include('content_generation')
      end
    end

    describe '.validate_template_configuration' do
      it 'validates complete template configuration' do
        valid_config = {
          nodes: [{ id: 'test', type: 'ai_agent', name: 'Test' }],
          variables: [{ name: 'var1', type: 'string' }],
          metadata: { version: '1.0' }
        }
        
        expect(described_class.validate_template_configuration(valid_config)).to be true
      end

      it 'rejects invalid configurations' do
        invalid_config = { nodes: 'invalid' }
        expect(described_class.validate_template_configuration(invalid_config)).to be false
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'large template configurations' do
      it 'handles templates with many nodes' do
        large_config = {
          nodes: Array.new(50) { |i| 
            { id: "node_#{i}", type: 'ai_agent', name: "Node #{i}" }
          },
          variables: [],
          metadata: {}
        }
        
        template = build(:ai_workflow_template, configuration: large_config)
        expect(template).to be_valid
        expect(template.configuration[:nodes].size).to eq(50)
      end

      it 'handles complex variable configurations' do
        complex_variables = Array.new(20) { |i|
          {
            name: "var_#{i}",
            type: 'object',
            required: i.even?,
            validation_rules: {
              properties: {
                nested_field: { type: 'string', min_length: 5 }
              }
            }
          }
        }
        
        template = build(:ai_workflow_template, 
                        configuration: { 
                          nodes: [], 
                          variables: complex_variables, 
                          metadata: {} 
                        })
        expect(template).to be_valid
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode in template content' do
        unicode_template = build(:ai_workflow_template,
                                 name: '智能内容生成器 🤖',
                                 description: 'Générateur de contenu avec émojis 🚀',
                                 tags: ['中文', 'français', 'العربية'])
        
        expect(unicode_template).to be_valid
        expect(unicode_template.save!).to be true
        expect(unicode_template.reload.name).to eq('智能内容生成器 🤖')
      end
    end

    describe 'concurrent installation handling' do
      it 'prevents race conditions during simultaneous installations' do
        template = create(:ai_workflow_template, :published)
        account = create(:account)
        
        # Simulate concurrent installation attempts
        threads = 3.times.map do
          Thread.new do
            begin
              template.install_for_account!(account)
            rescue StandardError
              # Expected - only one should succeed
            end
          end
        end
        
        threads.each(&:join)
        
        # Should only have one installation
        expect(template.installations.where(account: account).count).to eq(1)
      end
    end

    describe 'query performance with large datasets' do
      before do
        create_list(:ai_workflow_template, 100, :published)
        create_list(:ai_workflow_template, 50, is_published: false)
      end

      it 'efficiently searches templates' do
        expect {
          described_class.published
                        .by_category('content_generation')
                        .search('generator')
                        .includes(:installations)
                        .limit(20)
                        .to_a
        }.not_to exceed_query_limit(3)
      end

      it 'efficiently calculates popular templates' do
        expect {
          described_class.popular.limit(10).to_a
        }.not_to exceed_query_limit(2)
      end
    end

    describe 'version compatibility edge cases' do
      it 'handles complex version constraints' do
        template = create(:ai_workflow_template, template_version: '1.2.3-beta.1')
        
        expect(template.template_version).to eq('1.2.3-beta.1')
        expect { template.save! }.not_to raise_error
      end

      it 'compares versions correctly' do
        v1 = create(:ai_workflow_template, name: 'Template A', template_version: '1.0.0')
        v2 = create(:ai_workflow_template, name: 'Template A', template_version: '1.0.1')
        v3 = create(:ai_workflow_template, name: 'Template A', template_version: '2.0.0')
        
        latest = described_class.where(name: 'Template A')
                               .order(Arel.sql("string_to_array(template_version, '.')::int[] DESC"))
                               .first
        
        expect(latest).to eq(v3)
      end
    end
  end
end
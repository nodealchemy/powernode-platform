# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowTemplate, type: :model do
  subject(:template) { build(:ai_workflow_template) }

  describe 'associations' do
    it { is_expected.to have_many(:ai_workflow_template_installations).dependent(:destroy) }
    it { is_expected.to have_many(:installed_workflows).through(:ai_workflow_template_installations).source(:ai_workflow) }
    it { is_expected.to have_many(:installing_accounts).through(:ai_workflow_template_installations).source(:account) }
    it { is_expected.to have_many(:installations).class_name('AiWorkflowTemplateInstallation') }
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to belong_to(:created_by_user).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_presence_of(:workflow_definition) }
    it { is_expected.to validate_presence_of(:difficulty_level) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_length_of(:category).is_at_most(100) }

    it 'validates uniqueness of slug' do
      # The model generates unique slugs automatically via callback
      create(:ai_workflow_template, name: 'Test Template')
      # Same name gets a unique slug suffix
      duplicate = create(:ai_workflow_template, name: 'Test Template')
      expect(duplicate.slug).to match(/^test-template-\d+$/)
    end

    it 'validates inclusion of difficulty_level' do
      valid_levels = %w[beginner intermediate advanced expert]

      valid_levels.each do |level|
        tmpl = build(:ai_workflow_template, difficulty_level: level)
        expect(tmpl).to be_valid, "Expected #{level} to be valid"
      end
    end

    it 'rejects invalid difficulty_level' do
      tmpl = build(:ai_workflow_template, difficulty_level: 'invalid')
      expect(tmpl).not_to be_valid
      expect(tmpl.errors[:difficulty_level]).to be_present
    end

    context 'version format validation' do
      it 'accepts valid semantic versions' do
        valid_versions = %w[1.0.0 2.5.1 10.20.30 0.1.0]

        valid_versions.each do |version|
          tmpl = build(:ai_workflow_template, version: version)
          expect(tmpl).to be_valid, "Expected '#{version}' to be valid"
        end
      end

      it 'rejects invalid version formats' do
        invalid_versions = %w[1.0 v1.0.0 1.0.0-beta]

        invalid_versions.each do |version|
          tmpl = build(:ai_workflow_template, version: version)
          expect(tmpl).not_to be_valid, "Expected '#{version}' to be invalid"
          expect(tmpl.errors[:version]).to be_present
        end
      end
    end

    context 'slug format validation' do
      it 'accepts valid slugs' do
        valid_slugs = %w[my-template template_123 simple-template-name]

        valid_slugs.each do |slug|
          tmpl = build(:ai_workflow_template, slug: slug)
          expect(tmpl).to be_valid, "Expected '#{slug}' to be valid"
        end
      end

      it 'generates valid slug from name' do
        # The callback normalizes names into valid slugs
        tmpl = build(:ai_workflow_template, name: 'My Template!', slug: nil)
        tmpl.valid?
        expect(tmpl.slug).to match(/^[a-z0-9\-_]+$/)
      end
    end

    context 'workflow_definition validation' do
      it 'validates workflow_definition is a hash' do
        tmpl = build(:ai_workflow_template)
        tmpl.workflow_definition = 'not a hash'
        expect(tmpl).not_to be_valid
        expect(tmpl.errors[:workflow_definition]).to include('must be a hash')
      end

      it 'validates required workflow_definition fields' do
        tmpl = build(:ai_workflow_template, workflow_definition: { 'some' => 'data' })
        expect(tmpl).not_to be_valid
        expect(tmpl.errors[:workflow_definition]).to include("must contain 'nodes' key")
        expect(tmpl.errors[:workflow_definition]).to include("must contain 'edges' key")
      end

      it 'validates nodes structure in workflow_definition' do
        tmpl = build(:ai_workflow_template, workflow_definition: {
          'nodes' => [{ 'invalid' => 'node' }],
          'edges' => []
        })
        expect(tmpl).not_to be_valid
        expect(tmpl.errors[:workflow_definition]).to be_present
      end

      it 'accepts valid workflow_definition structure' do
        tmpl = build(:ai_workflow_template, workflow_definition: {
          'nodes' => [
            { 'node_id' => 'start', 'node_type' => 'start' },
            { 'node_id' => 'end', 'node_type' => 'end' }
          ],
          'edges' => [
            { 'source_node_id' => 'start', 'target_node_id' => 'end' }
          ]
        })
        expect(tmpl).to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.published' do
      let!(:published_template) { create(:ai_workflow_template, published_at: 1.day.ago) }
      let!(:unpublished_template) { create(:ai_workflow_template, published_at: nil) }

      it 'returns only published templates' do
        expect(described_class.published).to include(published_template)
        expect(described_class.published).not_to include(unpublished_template)
      end
    end

    describe '.featured' do
      let!(:featured_template) { create(:ai_workflow_template, is_featured: true) }
      let!(:regular_template) { create(:ai_workflow_template, is_featured: false) }

      it 'returns only featured templates' do
        expect(described_class.featured).to include(featured_template)
        expect(described_class.featured).not_to include(regular_template)
      end
    end

    describe '.public_templates' do
      let!(:public_template) { create(:ai_workflow_template, is_public: true) }
      let!(:private_template) { create(:ai_workflow_template, is_public: false) }

      it 'returns only public templates' do
        expect(described_class.public_templates).to include(public_template)
        expect(described_class.public_templates).not_to include(private_template)
      end
    end

    describe '.by_category' do
      let!(:content_template) { create(:ai_workflow_template, category: 'content_generation') }
      let!(:data_template) { create(:ai_workflow_template, category: 'data_processing') }

      it 'filters templates by category' do
        expect(described_class.by_category('content_generation')).to include(content_template)
        expect(described_class.by_category('content_generation')).not_to include(data_template)
      end
    end

    describe '.by_difficulty' do
      let!(:beginner_template) { create(:ai_workflow_template, difficulty_level: 'beginner') }
      let!(:advanced_template) { create(:ai_workflow_template, difficulty_level: 'advanced') }

      it 'filters templates by difficulty level' do
        expect(described_class.by_difficulty('beginner')).to include(beginner_template)
        expect(described_class.by_difficulty('beginner')).not_to include(advanced_template)
      end
    end

    describe '.popular' do
      let!(:popular_template) { create(:ai_workflow_template, usage_count: 100) }
      let!(:unpopular_template) { create(:ai_workflow_template, usage_count: 5) }

      it 'orders templates by usage count descending' do
        results = described_class.popular
        expect(results.first).to eq(popular_template)
        expect(results.last).to eq(unpopular_template)
      end
    end

    describe '.search_by_text' do
      let!(:matching_template) { create(:ai_workflow_template, name: 'AI Blog Generator', description: 'Generate blogs') }
      let!(:non_matching_template) { create(:ai_workflow_template, name: 'Data Pipeline', description: 'Process data') }

      it 'searches by name and description' do
        expect(described_class.search_by_text('Blog')).to include(matching_template)
        expect(described_class.search_by_text('Blog')).not_to include(non_matching_template)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates slug from name' do
        tmpl = build(:ai_workflow_template, name: 'My Test Template', slug: nil)
        tmpl.valid?
        expect(tmpl.slug).to eq('my-test-template')
      end

      it 'normalizes tags' do
        tmpl = build(:ai_workflow_template, tags: ['AI', 'AUTOMATION', 'ai'])
        tmpl.valid?
        expect(tmpl.tags).to eq(['ai', 'automation'])
      end

      it 'ensures unique slug' do
        create(:ai_workflow_template, name: 'My Template', slug: 'my-template')
        tmpl = build(:ai_workflow_template, name: 'My Template', slug: nil)
        tmpl.valid?
        expect(tmpl.slug).to match(/^my-template-\d+$/)
      end
    end
  end

  describe 'instance methods' do
    describe '#published?' do
      it 'returns true when published_at is set' do
        tmpl = create(:ai_workflow_template, published_at: 1.day.ago)
        expect(tmpl.published?).to be true
      end

      it 'returns false when published_at is nil' do
        tmpl = create(:ai_workflow_template, published_at: nil)
        expect(tmpl.published?).to be false
      end
    end

    describe '#public?' do
      it 'returns true when is_public is true' do
        tmpl = create(:ai_workflow_template, is_public: true)
        expect(tmpl.public?).to be true
      end

      it 'returns false when is_public is false' do
        tmpl = create(:ai_workflow_template, is_public: false)
        expect(tmpl.public?).to be false
      end
    end

    describe '#featured?' do
      it 'returns true when is_featured is true' do
        tmpl = create(:ai_workflow_template, is_featured: true)
        expect(tmpl.featured?).to be true
      end
    end

    describe '#available_for_installation?' do
      it 'returns true when published and public' do
        tmpl = create(:ai_workflow_template, published_at: 1.day.ago, is_public: true)
        expect(tmpl.available_for_installation?).to be true
      end

      it 'returns false when not published' do
        tmpl = create(:ai_workflow_template, published_at: nil, is_public: true)
        expect(tmpl.available_for_installation?).to be false
      end
    end

    describe '#visibility' do
      it 'returns public for public templates' do
        tmpl = build(:ai_workflow_template, is_public: true)
        expect(tmpl.visibility).to eq('public')
      end

      it 'returns private for private templates' do
        tmpl = build(:ai_workflow_template, is_public: false)
        expect(tmpl.visibility).to eq('private')
      end
    end

    describe '#visibility=' do
      it 'sets is_public to true for public visibility' do
        tmpl = build(:ai_workflow_template)
        tmpl.visibility = 'public'
        expect(tmpl.is_public).to be true
      end

      it 'sets is_public to false for private visibility' do
        tmpl = build(:ai_workflow_template)
        tmpl.visibility = 'private'
        expect(tmpl.is_public).to be false
      end
    end

    describe '#workflow_nodes' do
      it 'returns nodes from workflow_definition' do
        nodes = [{ 'node_id' => 'start', 'node_type' => 'start' }]
        tmpl = build(:ai_workflow_template, workflow_definition: { 'nodes' => nodes, 'edges' => [] })
        expect(tmpl.workflow_nodes).to eq(nodes)
      end

      it 'returns empty array when nodes not present' do
        tmpl = build(:ai_workflow_template, workflow_definition: { 'edges' => [] })
        expect(tmpl.workflow_nodes).to eq([])
      end
    end

    describe '#workflow_edges' do
      it 'returns edges from workflow_definition' do
        edges = [{ 'source_node_id' => 'a', 'target_node_id' => 'b' }]
        tmpl = build(:ai_workflow_template, workflow_definition: { 'nodes' => [], 'edges' => edges })
        expect(tmpl.workflow_edges).to eq(edges)
      end
    end

    describe '#node_count' do
      it 'returns the number of nodes' do
        tmpl = build(:ai_workflow_template)
        expect(tmpl.node_count).to eq(tmpl.workflow_nodes.size)
      end
    end

    describe '#has_ai_agents?' do
      it 'returns true when ai_agent nodes exist' do
        tmpl = build(:ai_workflow_template, workflow_definition: {
          'nodes' => [
            { 'node_id' => 'ai', 'node_type' => 'ai_agent' }
          ],
          'edges' => []
        })
        expect(tmpl.has_ai_agents?).to be true
      end

      it 'returns false when no ai_agent nodes' do
        tmpl = build(:ai_workflow_template)
        expect(tmpl.has_ai_agents?).to be false
      end
    end

    describe '#complexity_score' do
      it 'calculates complexity based on nodes and edges' do
        tmpl = build(:ai_workflow_template)
        score = tmpl.complexity_score
        expect(score).to be >= 0
      end

      it 'gives higher score for ai_agent nodes' do
        simple_tmpl = build(:ai_workflow_template, workflow_definition: {
          'nodes' => [
            { 'node_id' => 'start', 'node_type' => 'start' }
          ],
          'edges' => []
        })

        ai_tmpl = build(:ai_workflow_template, workflow_definition: {
          'nodes' => [
            { 'node_id' => 'ai', 'node_type' => 'ai_agent' }
          ],
          'edges' => []
        })

        expect(ai_tmpl.complexity_score).to be > simple_tmpl.complexity_score
      end
    end

    describe '#publish!' do
      it 'sets published_at when not published' do
        tmpl = create(:ai_workflow_template, published_at: nil)
        tmpl.publish!
        expect(tmpl.reload.published_at).to be_present
      end

      it 'returns false when already published' do
        tmpl = create(:ai_workflow_template, published_at: 1.day.ago)
        expect(tmpl.publish!).to be false
      end
    end

    describe '#unpublish!' do
      it 'clears published_at when published' do
        tmpl = create(:ai_workflow_template, published_at: 1.day.ago, is_public: true, is_featured: true)
        tmpl.unpublish!
        tmpl.reload
        expect(tmpl.published_at).to be_nil
        expect(tmpl.is_public).to be false
        expect(tmpl.is_featured).to be false
      end

      it 'returns false when not published' do
        tmpl = create(:ai_workflow_template, published_at: nil)
        expect(tmpl.unpublish!).to be false
      end
    end

    describe '#feature!' do
      it 'sets is_featured when public and published' do
        tmpl = create(:ai_workflow_template, is_public: true, published_at: 1.day.ago)
        tmpl.feature!
        expect(tmpl.reload.is_featured).to be true
      end

      it 'returns false when not public' do
        tmpl = create(:ai_workflow_template, is_public: false, published_at: 1.day.ago)
        expect(tmpl.feature!).to be false
      end
    end

    describe '#next_version' do
      let(:tmpl) { build(:ai_workflow_template, version: '1.2.3') }

      it 'increments patch version by default' do
        expect(tmpl.next_version).to eq('1.2.4')
      end

      it 'increments minor version' do
        expect(tmpl.next_version('minor')).to eq('1.3.0')
      end

      it 'increments major version' do
        expect(tmpl.next_version('major')).to eq('2.0.0')
      end
    end

    describe '#add_rating' do
      it 'updates rating and rating_count' do
        tmpl = create(:ai_workflow_template, rating: 4.0, rating_count: 10)
        tmpl.add_rating(5)
        tmpl.reload
        expect(tmpl.rating_count).to eq(11)
      end

      it 'returns false for invalid rating' do
        tmpl = create(:ai_workflow_template)
        expect(tmpl.add_rating(6)).to be false
        expect(tmpl.add_rating(0)).to be false
      end
    end

    describe '#can_install?' do
      let(:account) { create(:account) }

      it 'returns true for public templates' do
        tmpl = build(:ai_workflow_template, is_public: true)
        expect(tmpl.can_install?(account)).to be true
      end

      it 'returns true for account-owned private templates' do
        tmpl = build(:ai_workflow_template, is_public: false, account: account)
        expect(tmpl.can_install?(account)).to be true
      end

      it 'returns false for other private templates' do
        other_account = create(:account)
        tmpl = build(:ai_workflow_template, is_public: false, account: other_account)
        expect(tmpl.can_install?(account)).to be false
      end
    end

    describe '#installed_by_account?' do
      let(:account) { create(:account) }
      let(:template) { create(:ai_workflow_template) }

      it 'returns false when not installed' do
        expect(template.installed_by_account?(account)).to be false
      end
    end

    describe '#export_definition' do
      let(:template) { create(:ai_workflow_template, tags: ['ai', 'automation']) }

      it 'returns exportable hash' do
        export = template.export_definition
        expect(export).to include(:template, :workflow, :variables, :metadata)
        expect(export[:template]).to include(:name, :description, :category, :version)
      end
    end

    describe '#to_param' do
      it 'returns the slug' do
        tmpl = build(:ai_workflow_template, slug: 'my-template')
        expect(tmpl.to_param).to eq('my-template')
      end
    end
  end

  describe 'edge cases' do
    describe 'unicode handling' do
      it 'handles unicode in template content' do
        tmpl = build(:ai_workflow_template,
                     name: 'テンプレート Template',
                     description: 'Description with émojis 🎉')
        expect(tmpl).to be_valid
      end
    end

    describe 'empty workflow_definition' do
      it 'requires nodes and edges keys' do
        tmpl = build(:ai_workflow_template, workflow_definition: {})
        expect(tmpl).not_to be_valid
      end
    end

    describe 'tag handling' do
      it 'handles empty tags array' do
        tmpl = build(:ai_workflow_template, tags: [])
        expect(tmpl).to be_valid
        expect(tmpl.tags).to eq([])
      end

      it 'deduplicates and downcases tags' do
        tmpl = build(:ai_workflow_template, tags: ['AI', 'ai', 'Automation'])
        tmpl.valid?
        expect(tmpl.tags).to eq(['ai', 'automation'])
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::MarketplaceController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }
  let(:worker) { create(:worker, account: account) }

  # Permission-based users
  let(:workflow_read_user) { create(:user, account: account, permissions: [ 'ai.workflows.read' ]) }
  let(:workflow_manage_user) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.create', 'ai.workflows.update', 'ai.workflows.delete', 'ai.workflows.manage' ]) }

  # Test data
  let(:workflow) { create(:ai_workflow, account: account, name: 'Source Workflow') }
  let(:template) { create(:ai_workflow_template, is_public: true, account: account, created_by_user: workflow_manage_user) }
  let(:private_template) { create(:ai_workflow_template, is_public: false) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # TEMPLATES - CRUD
  # =============================================================================

  describe 'GET #index' do
    let!(:public_template1) { create(:ai_workflow_template, is_public: true, category: 'automation', usage_count: 10) }
    let!(:public_template2) { create(:ai_workflow_template, is_public: true, category: 'data_processing', usage_count: 5) }
    let!(:private_template) { create(:ai_workflow_template, is_public: false) }

    it 'returns public templates without authentication' do
      get :index

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['items'].length).to be >= 2
    end

    it 'includes pagination' do
      get :index, params: { page: 1, per_page: 1 }

      json = JSON.parse(response.body)
      expect(json['data']['pagination']).to include(
        'current_page' => 1,
        'per_page' => 1
      )
    end

    it 'filters by category' do
      get :index, params: { category: 'automation' }

      json = JSON.parse(response.body)
      categories = json['data']['items'].map { |t| t['category'] }.uniq
      expect(categories).to eq([ 'automation' ])
    end

    it 'filters by tags' do
      tagged_template = create(:ai_workflow_template, is_public: true, tags: [ 'test', 'automation' ])

      get :index, params: { tags: 'test' }

      json = JSON.parse(response.body)
      template_ids = json['data']['items'].map { |t| t['id'] }
      expect(template_ids).to include(tagged_template.id)
    end

    it 'filters by featured status' do
      featured_template = create(:ai_workflow_template, is_public: true, is_featured: true)

      get :index, params: { is_featured: 'true' }

      json = JSON.parse(response.body)
      templates = json['data']['items']
      expect(templates.all? { |t| t['is_featured'] }).to be true
    end

    it 'searches by query' do
      searchable_template = create(:ai_workflow_template, is_public: true, name: 'Special Workflow Template')

      get :index, params: { q: 'Special' }

      json = JSON.parse(response.body)
      template_ids = json['data']['items'].map { |t| t['id'] }
      expect(template_ids).to include(searchable_template.id)
    end

    it 'sorts by popularity' do
      get :index, params: { sort_by: 'popular' }

      json = JSON.parse(response.body)
      install_counts = json['data']['items'].map { |t| t['install_count'] }
      expect(install_counts).to eq(install_counts.sort.reverse)
    end

    it 'sorts by rating' do
      get :index, params: { sort_by: 'rating' }

      expect(response).to have_http_status(:success)
    end

    it 'sorts by recent' do
      get :index, params: { sort_by: 'recent' }

      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET #template_show' do
    it 'returns template details for public template' do
      get :show, params: { id: template.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['template']['id']).to eq(template.id)
    end

    it 'includes template data and configuration schema' do
      get :show, params: { id: template.id }

      json = JSON.parse(response.body)
      template_data = json['data']['template']
      expect(template_data).to include(
        'template_data',
        'configuration_schema'
      )
    end

    it 'includes permissions info' do
      sign_in user

      get :show, params: { id: template.id }

      json = JSON.parse(response.body)
      expect(json['data']['template']).to include('can_edit', 'can_install', 'can_delete', 'can_publish')
    end

    it 'returns not found for nonexistent template' do
      get :show, params: { id: 'nonexistent' }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #template_create' do
    before { sign_in workflow_manage_user }

    let(:valid_template_params) do
      {
        template: {
          name: 'New Template',
          description: 'A new workflow template',
          category: 'automation',
          is_public: false,
          version: '1.0.0',
          difficulty_level: 'intermediate',
          tags: [ 'test', 'automation' ],
          template_data: { nodes: [], edges: [] },
          configuration_schema: { type: 'object' }
        }
      }
    end

    it 'creates a new template' do
      expect {
        post :create, params: valid_template_params
      }.to change(Ai::WorkflowTemplate, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['template']['name']).to eq('New Template')
    end

    it 'assigns template to current account and user' do
      post :create, params: valid_template_params

      template = Ai::WorkflowTemplate.last
      expect(template.account_id).to eq(account.id)
      expect(template.created_by_user_id).to eq(workflow_manage_user.id)
    end

    it 'returns validation errors for invalid data' do
      invalid_params = valid_template_params.deep_dup
      invalid_params[:template][:name] = ''

      post :create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      post :create, params: valid_template_params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires create permission' do
      sign_in workflow_read_user

      post :create, params: valid_template_params

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH #template_update' do
    before { sign_in workflow_manage_user }

    it 'updates the template' do
      patch :update, params: {
        id: template.id,
        template: { description: 'Updated description' }
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['template']['description']).to eq('Updated description')
      expect(template.reload.description).to eq('Updated description')
    end

    it 'prevents unauthorized users from updating' do
      other_user = create(:user, account: account, permissions: [ 'ai.workflows.update' ])
      other_template = create(:ai_workflow_template, created_by_user: other_user)

      sign_in other_user

      patch :update, params: {
        id: template.id,
        template: { description: 'Unauthorized update' }
      }

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires update permission' do
      sign_in workflow_read_user

      patch :update, params: {
        id: template.id,
        template: { description: 'Updated' }
      }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE #template_destroy' do
    before { sign_in workflow_manage_user }

    it 'deletes the template' do
      deletable_template = create(:ai_workflow_template, account: account, created_by_user: workflow_manage_user)
      expect {
        delete :destroy, params: { id: deletable_template.id }
      }.to change(Ai::WorkflowTemplate, :count).by(-1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['message']).to include('deleted successfully')
    end

    it 'prevents deletion of templates with active installations' do
      allow_any_instance_of(Ai::WorkflowTemplate).to receive(:can_delete?).and_return(false)

      delete :destroy, params: { id: template.id }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'requires delete permission' do
      sign_in workflow_read_user

      delete :destroy, params: { id: template.id }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # =============================================================================
  # TEMPLATE CUSTOM ACTIONS
  # =============================================================================

  describe 'POST #create_from_workflow' do
    before do
      sign_in workflow_manage_user
      # Create nodes and edges for the workflow
      create(:ai_workflow_node, workflow: workflow)
      create(:ai_workflow_edge, workflow: workflow)
    end

    it 'creates template from existing workflow' do
      expect {
        post :create_from_workflow, params: {
          workflow_id: workflow.id,
          name: 'Template from Workflow',
          category: 'automation'
        }
      }.to change(Ai::WorkflowTemplate, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['template']['name']).to eq('Template from Workflow')
      # source_workflow_id is stored in the template's metadata, not as a direct serialized field
      created_template = Ai::WorkflowTemplate.last
      expect(created_template.metadata['source_workflow_id']).to eq(workflow.id)
    end

    it 'extracts workflow structure into workflow_definition' do
      post :create_from_workflow, params: {
        workflow_id: workflow.id,
        name: 'Template from Workflow'
      }

      template = Ai::WorkflowTemplate.last
      expect(template.workflow_definition).to include('nodes', 'edges')
    end

    it 'calculates metadata including complexity score' do
      post :create_from_workflow, params: {
        workflow_id: workflow.id,
        name: 'Template from Workflow'
      }

      template = Ai::WorkflowTemplate.last
      expect(template.metadata).to include('node_count', 'edge_count', 'complexity_score')
    end

    it 'returns not found for nonexistent workflow' do
      post :create_from_workflow, params: {
        workflow_id: 'nonexistent',
        name: 'Template'
      }

      expect(response).to have_http_status(:not_found)
    end

    it 'requires create permission' do
      sign_in workflow_read_user

      post :create_from_workflow, params: {
        workflow_id: workflow.id,
        name: 'Template'
      }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST #publish' do
    before { sign_in workflow_manage_user }

    it 'publishes the template' do
      # Create an unpublished template owned by the user
      unpublished_template = create(:ai_workflow_template, is_public: false, account: account, created_by_user: workflow_manage_user)
      allow_any_instance_of(Ai::WorkflowTemplate).to receive(:publish!).and_return(true)

      post :publish, params: { id: unpublished_template.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['message']).to include('published successfully')
    end

    it 'prevents unauthorized publishing' do
      allow_any_instance_of(Ai::WorkflowTemplate).to receive(:can_publish?).and_return(false)

      post :publish, params: { id: template.id }

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires update permission' do
      sign_in workflow_read_user

      post :publish, params: { id: template.id }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET #validate_template' do
    it 'validates template structure' do
      get :validate_template, params: { id: template.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['validation']).to include(
        'valid',
        'errors',
        'warnings',
        'suggestions'
      )
    end

    it 'provides suggestions for improvement' do
      template_without_tags = create(:ai_workflow_template, is_public: true, metadata: { tags: [] })

      get :validate_template, params: { id: template_without_tags.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      suggestions = json['data']['validation']['suggestions']
      expect(suggestions).to be_an(Array)
    end
  end


  # =============================================================================
  # WORKER CONTEXT
  # =============================================================================

  describe 'worker authentication' do
    before do
      # Set WORKER_TOKEN environment variable for worker authentication
      ENV['WORKER_TOKEN'] = worker.auth_token
      @request.headers['X-Worker-Token'] = worker.auth_token
    end

    after do
      # Clean up environment variable
      ENV.delete('WORKER_TOKEN')
    end

    it 'allows workers to access all endpoints' do
      get :index

      expect(response).to have_http_status(:success)
    end

    it 'bypasses permission checks for workers' do
      post :create_from_workflow, params: {
        workflow_id: workflow.id,
        name: 'Worker Template'
      }

      expect(response).to have_http_status(:success)
    end
  end

  # =============================================================================
  # HELPER METHODS
  # =============================================================================
  # NOTE: This spec uses the global auth_helpers.rb sign_in method
  # which properly generates JWT tokens using Security::JwtService with correct secret
end

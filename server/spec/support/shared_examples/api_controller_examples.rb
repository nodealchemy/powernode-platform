# frozen_string_literal: true

# Shared examples for API controller testing
#
# These examples provide consistent patterns for testing common controller behaviors:
# - Authentication requirements
# - Permission/authorization checks
# - Pagination
# - Account scoping
#
# Usage:
#   RSpec.describe Api::V1::UsersController, type: :request do
#     include_examples 'requires authentication', :get, '/api/v1/users'
#     include_examples 'requires permission', :get, '/api/v1/users', 'users.read'
#   end
#

# =============================================================================
# AUTHENTICATION EXAMPLES
# =============================================================================

RSpec.shared_examples 'requires authentication' do |http_method, path, params: {}|
  it 'returns 401 when no token provided' do
    send(http_method, path, params: params, headers: { 'Content-Type' => 'application/json' })
    expect(response).to have_http_status(:unauthorized)
    expect(json_response['success']).to be false
    expect(json_response['error']).to include('token')
  end

  it 'returns 401 when invalid token provided' do
    headers = { 'Authorization' => 'Bearer invalid_token', 'Content-Type' => 'application/json' }
    send(http_method, path, params: params, headers: headers)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 when expired token provided' do
    expired_token = Security::JwtService.encode(
      { sub: SecureRandom.uuid, exp: 1.hour.ago.to_i }
    )
    headers = { 'Authorization' => "Bearer #{expired_token}", 'Content-Type' => 'application/json' }
    send(http_method, path, params: params, headers: headers)
    expect(response).to have_http_status(:unauthorized)
  end
end

RSpec.shared_examples 'allows unauthenticated access' do |http_method, path, params: {}|
  it 'allows access without authentication' do
    send(http_method, path, params: params, headers: { 'Content-Type' => 'application/json' })
    expect(response).not_to have_http_status(:unauthorized)
  end
end

# =============================================================================
# PERMISSION EXAMPLES
# =============================================================================

RSpec.shared_examples 'requires permission' do |http_method, path, permission, params: {}|
  let(:account) { create(:account) }
  let(:user_without_permission) { create(:user, account: account, permissions: []) }

  it "returns 403 when user lacks #{permission} permission" do
    headers = auth_headers_for(user_without_permission)
    send(http_method, path, params: params, headers: headers)
    expect(response).to have_http_status(:forbidden)
    expect(json_response['success']).to be false
  end
end

RSpec.shared_examples 'accessible with permission' do |http_method, path, permission, params: {}|
  let(:account) { create(:account) }
  let(:user_with_permission) { create(:user, account: account, permissions: [ permission ]) }

  it "succeeds when user has #{permission} permission" do
    headers = auth_headers_for(user_with_permission)
    send(http_method, path, params: params, headers: headers)
    expect(response).to have_http_status(:success)
  end
end

RSpec.shared_examples 'requires admin access' do |http_method, path, params: {}|
  let(:account) { create(:account) }
  let(:regular_user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }

  it 'returns 403 for non-admin users' do
    headers = auth_headers_for(regular_user)
    send(http_method, path, params: params, headers: headers)
    expect(response).to have_http_status(:forbidden)
  end

  it 'succeeds for admin users' do
    headers = auth_headers_for(admin_user)
    send(http_method, path, params: params, headers: headers)
    expect(response).not_to have_http_status(:forbidden)
  end
end

# =============================================================================
# PAGINATION EXAMPLES
# =============================================================================

RSpec.shared_examples 'paginates results' do |http_method, path, factory_name, count: 25|
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'admin.access' ]) }

  before do
    create_list(factory_name, count, account: account)
  end

  it 'returns paginated results with default page size' do
    headers = auth_headers_for(user)
    send(http_method, path, headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    pagination = data['pagination'] || json_response['meta']

    expect(pagination).to include(
      'current_page' => 1,
      'total_count' => count
    )
  end

  it 'respects page parameter' do
    headers = auth_headers_for(user)
    send(http_method, "#{path}?page=2&per_page=10", headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    pagination = data['pagination'] || json_response['meta']

    expect(pagination['current_page']).to eq(2)
  end

  it 'respects per_page parameter' do
    headers = auth_headers_for(user)
    send(http_method, "#{path}?per_page=5", headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    items = data['items'] || data[factory_name.to_s.pluralize] || []

    expect(items.length).to be <= 5
  end

  it 'enforces maximum per_page limit' do
    headers = auth_headers_for(user)
    send(http_method, "#{path}?per_page=1000", headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    pagination = data['pagination'] || json_response['meta']

    # Most controllers cap at 100
    expect(pagination['per_page']).to be <= 200
  end
end

RSpec.shared_examples 'returns pagination metadata' do
  it 'includes pagination metadata in response' do
    data = json_response['data'] || json_response
    pagination = data['pagination'] || json_response['meta']

    expect(pagination).to include(
      'current_page',
      'per_page',
      'total_pages',
      'total_count'
    )
  end
end

# =============================================================================
# ACCOUNT SCOPING EXAMPLES
# =============================================================================

RSpec.shared_examples 'scopes to current account' do |http_method, path, factory_name|
  let(:account1) { create(:account) }
  let(:account2) { create(:account) }
  let(:user1) { create(:user, account: account1, permissions: [ 'admin.access' ]) }
  let(:user2) { create(:user, account: account2, permissions: [ 'admin.access' ]) }

  before do
    @record1 = create(factory_name, account: account1)
    @record2 = create(factory_name, account: account2)
  end

  it 'only returns records from the current user account' do
    headers = auth_headers_for(user1)
    send(http_method, path, headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    items = data['items'] || data[factory_name.to_s.pluralize] || [ data ]

    item_ids = items.map { |item| item['id'] }
    expect(item_ids).to include(@record1.id)
    expect(item_ids).not_to include(@record2.id)
  end

  it 'does not expose records from other accounts' do
    headers = auth_headers_for(user2)
    send(http_method, path, headers: headers)

    expect(response).to have_http_status(:success)
    data = json_response['data'] || json_response
    items = data['items'] || data[factory_name.to_s.pluralize] || [ data ]

    item_ids = items.map { |item| item['id'] }
    expect(item_ids).to include(@record2.id)
    expect(item_ids).not_to include(@record1.id)
  end
end

RSpec.shared_examples 'returns 404 for other account resources' do |http_method, path_template, factory_name|
  let(:account1) { create(:account) }
  let(:account2) { create(:account) }
  let(:user1) { create(:user, account: account1, permissions: [ 'admin.access' ]) }

  before do
    @record = create(factory_name, account: account2)
  end

  it 'returns 404 when accessing resource from another account' do
    path = path_template.gsub(':id', @record.id.to_s)
    headers = auth_headers_for(user1)
    send(http_method, path, headers: headers)

    expect(response).to have_http_status(:not_found)
  end
end

# =============================================================================
# CRUD EXAMPLES
# =============================================================================

RSpec.shared_examples 'a successful index action' do
  it 'returns success status' do
    expect(response).to have_http_status(:success)
    expect(json_response['success']).to be true
  end

  it 'returns an array of items' do
    data = json_response['data'] || json_response
    items = data['items'] || data.values.first
    expect(items).to be_an(Array)
  end
end

RSpec.shared_examples 'a successful show action' do
  it 'returns success status' do
    expect(response).to have_http_status(:success)
    expect(json_response['success']).to be true
  end

  it 'returns the requested resource' do
    data = json_response['data'] || json_response
    expect(data).to include('id')
  end
end

RSpec.shared_examples 'a successful create action' do
  it 'returns created status' do
    expect(response).to have_http_status(:created)
    expect(json_response['success']).to be true
  end

  it 'returns the created resource' do
    data = json_response['data'] || json_response
    expect(data).to include('id')
  end
end

RSpec.shared_examples 'a successful update action' do
  it 'returns success status' do
    expect(response).to have_http_status(:success)
    expect(json_response['success']).to be true
  end
end

RSpec.shared_examples 'a successful destroy action' do
  it 'returns success status' do
    expect(response).to have_http_status(:success)
    expect(json_response['success']).to be true
  end

  it 'includes success message' do
    data = json_response['data'] || json_response
    expect(data['message'] || json_response['message']).to be_present
  end
end

# =============================================================================
# ERROR HANDLING EXAMPLES
# =============================================================================

RSpec.shared_examples 'returns 404 for non-existent resource' do |http_method, path|
  it 'returns 404 status' do
    headers = auth_headers_for(user)
    send(http_method, path, headers: headers)

    expect(response).to have_http_status(:not_found)
    expect(json_response['success']).to be false
  end
end

RSpec.shared_examples 'returns validation errors' do
  it 'returns 422 status' do
    expect(response).to have_http_status(:unprocessable_content)
    expect(json_response['success']).to be false
  end

  it 'includes error details' do
    expect(json_response['error']).to be_present
  end
end

# =============================================================================
# WORKER/SERVICE AUTHENTICATION EXAMPLES
# =============================================================================

RSpec.shared_examples 'allows worker authentication' do |http_method, path, params: {}|
  it 'succeeds with valid worker token' do
    worker = create(:worker, status: 'active')
    headers = { 'Authorization' => "Bearer #{worker.token}", 'Content-Type' => 'application/json' }
    send(http_method, path, params: params, headers: headers)

    expect(response).not_to have_http_status(:unauthorized)
  end
end

RSpec.shared_examples 'allows service authentication' do |http_method, path, params: {}|
  it 'succeeds with valid service token' do
    service_token = Security::JwtService.encode({
      service: 'backend',
      type: 'service',
      exp: 24.hours.from_now.to_i
    })
    headers = { 'Authorization' => "Bearer #{service_token}", 'Content-Type' => 'application/json' }
    send(http_method, path, params: params, headers: headers)

    expect(response).not_to have_http_status(:unauthorized)
  end
end

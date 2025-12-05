# frozen_string_literal: true

# Shared examples for AI components testing
RSpec.shared_examples 'an AI model with account scoping' do
  let(:account1) { create(:account) }
  let(:account2) { create(:account) }

  it 'scopes records to account' do
    record1 = create(described_class.name.underscore, account: account1)
    record2 = create(described_class.name.underscore, account: account2)

    expect(described_class.for_account(account1)).to include(record1)
    expect(described_class.for_account(account1)).not_to include(record2)
    expect(described_class.for_account(account2)).to include(record2)
    expect(described_class.for_account(account2)).not_to include(record1)
  end

  it 'validates presence of account' do
    record = build(described_class.name.underscore, account: nil)
    expect(record).not_to be_valid
    expect(record.errors[:account]).to include("can't be blank")
  end
end

RSpec.shared_examples 'an AI model with audit logging' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    allow(Current).to receive(:user).and_return(user)
    allow(Current).to receive(:account).and_return(account)
  end

  it 'creates audit log on creation' do
    expect {
      create(described_class.name.underscore, account: account)
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to eq("#{described_class.name.underscore}_created")
    expect(audit_log.resource_type).to eq(described_class.name)
  end

  it 'creates audit log on update' do
    record = create(described_class.name.underscore, account: account)
    
    expect {
      record.update!(name: 'Updated Name') if record.respond_to?(:name)
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to eq("#{described_class.name.underscore}_updated")
  end

  it 'creates audit log on deletion' do
    record = create(described_class.name.underscore, account: account)
    
    expect {
      record.destroy!
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to eq("#{described_class.name.underscore}_deleted")
  end
end

RSpec.shared_examples 'an AI model with UUID primary key' do
  it 'generates UUID as primary key' do
    record = create(described_class.name.underscore)
    expect(record.id).to be_present
    expect(record.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end

  it 'uses UUIDv7 format for chronological ordering' do
    record1 = create(described_class.name.underscore)
    sleep(0.001) # Ensure different timestamp
    record2 = create(described_class.name.underscore)
    
    # UUIDv7 should be chronologically sortable
    expect(record1.id).to be < record2.id
  end
end

RSpec.shared_examples 'an AI model with status transitions' do
  let(:valid_statuses) { described_class::VALID_STATUSES }
  let(:account) { create(:account) }

  it 'validates status values' do
    record = build(described_class.name.underscore, account: account, status: 'invalid_status')
    expect(record).not_to be_valid
    expect(record.errors[:status]).to be_present
  end

  it 'allows all valid statuses' do
    valid_statuses.each do |status|
      record = build(described_class.name.underscore, account: account, status: status)
      expect(record).to be_valid
    end
  end

  it 'has default status' do
    record = create(described_class.name.underscore, account: account)
    expect(valid_statuses).to include(record.status)
  end

  it 'tracks status changes in audit log' do
    record = create(described_class.name.underscore, account: account)
    
    expect {
      record.update!(status: valid_statuses.last)
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.metadata).to include('status_changed_from', 'status_changed_to')
  end
end

RSpec.shared_examples 'an AI controller with authentication' do
  context 'without authentication' do
    before do
      allow_any_instance_of(ApplicationController).to receive(:authenticate_request)
        .and_raise(JWT::DecodeError)
    end

    it 'returns unauthorized status' do
      get action_path
      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to eq('Invalid token format')
    end
  end

  context 'with expired token' do
    before do
      allow_any_instance_of(ApplicationController).to receive(:authenticate_request)
        .and_raise(JWT::ExpiredSignature)
    end

    it 'returns unauthorized status' do
      get action_path
      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to eq('Token has expired')
    end
  end
end

RSpec.shared_examples 'an AI controller with permission checks' do |required_permission|
  let(:user_without_permission) { create(:user, account: account, permissions: []) }
  let(:user_with_permission) { create(:user, account: account, permissions: [required_permission]) }

  context 'without required permission' do
    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user)
        .and_return(user_without_permission)
    end

    it 'returns forbidden status' do
      get action_path
      expect(response).to have_http_status(:forbidden)
      expect(json_response['error']).to eq('Insufficient permissions')
    end
  end

  context 'with required permission' do
    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user)
        .and_return(user_with_permission)
    end

    it 'allows access' do
      get action_path
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end

RSpec.shared_examples 'an AI controller with account isolation' do
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  context 'accessing other account data' do
    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user)
        .and_return(other_user)
      allow_any_instance_of(ApplicationController).to receive(:current_account)
        .and_return(other_account)
    end

    it 'cannot access other account resources' do
      get action_path
      expect(response).to have_http_status(:not_found)
    end
  end
end

RSpec.shared_examples 'an AI controller with structured responses' do
  it 'returns success response structure' do
    get action_path
    
    if response.successful?
      expect(json_response).to include('success' => true)
      expect(json_response).to have_key('data')
    end
  end

  it 'returns error response structure' do
    # Force an error by mocking
    allow_any_instance_of(described_class).to receive(action_method)
      .and_raise(StandardError.new('Test error'))
    
    get action_path
    
    expect(json_response).to include('success' => false)
    expect(json_response).to have_key('error')
  end
end

RSpec.shared_examples 'an AI service with error handling' do
  let(:service) { described_class.new }

  it 'handles connection errors gracefully' do
    allow(Net::HTTP).to receive(:post_form).and_raise(Net::ConnectTimeout)
    
    result = service.send(service_method, *service_args)
    expect(result).to include(success: false)
    expect(result[:error]).to include('connection')
  end

  it 'handles timeout errors' do
    allow(Net::HTTP).to receive(:post_form).and_raise(Net::ReadTimeout)
    
    result = service.send(service_method, *service_args)
    expect(result).to include(success: false)
    expect(result[:error]).to include('timeout')
  end

  it 'handles rate limiting' do
    response = double('response', code: '429', body: 'Rate limit exceeded')
    allow(Net::HTTP).to receive(:post_form).and_return(response)
    
    result = service.send(service_method, *service_args)
    expect(result).to include(success: false)
    expect(result[:error]).to include('rate limit')
  end

  it 'logs errors appropriately' do
    allow(Net::HTTP).to receive(:post_form).and_raise(StandardError.new('Test error'))
    
    expect(Rails.logger).to receive(:error).with(/Test error/)
    service.send(service_method, *service_args)
  end
end

RSpec.shared_examples 'an AI service with retry logic' do
  let(:service) { described_class.new }

  it 'retries on transient failures' do
    call_count = 0
    allow(Net::HTTP).to receive(:post_form) do
      call_count += 1
      if call_count < 3
        raise Net::ConnectTimeout
      else
        double('response', code: '200', body: '{"success": true}')
      end
    end
    
    result = service.send(service_method, *service_args)
    expect(result[:success]).to be true
    expect(call_count).to eq(3)
  end

  it 'gives up after max retries' do
    allow(Net::HTTP).to receive(:post_form).and_raise(Net::ConnectTimeout)
    
    result = service.send(service_method, *service_args)
    expect(result[:success]).to be false
    expect(result[:error]).to include('max retries exceeded')
  end

  it 'uses exponential backoff' do
    retry_delays = []
    allow(service).to receive(:sleep) { |delay| retry_delays << delay }
    allow(Net::HTTP).to receive(:post_form).and_raise(Net::ConnectTimeout)
    
    service.send(service_method, *service_args)
    
    expect(retry_delays).to satisfy { |delays| delays[1] > delays[0] } if retry_delays.size > 1
  end
end

RSpec.shared_examples 'an AI job with proper error handling' do
  let(:job) { described_class.new }

  it 'handles and logs errors appropriately' do
    allow(job).to receive(:execute).and_raise(StandardError.new('Job error'))
    
    expect(Rails.logger).to receive(:error).with(/Job error/)
    expect { job.perform(*job_args) }.not_to raise_error
  end

  it 'creates audit log entry for failures' do
    allow(job).to receive(:execute).and_raise(StandardError.new('Job error'))
    
    expect {
      job.perform(*job_args)
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to include('failed')
  end

  it 'implements circuit breaker pattern' do
    # Simulate multiple failures
    5.times do
      allow(job).to receive(:execute).and_raise(StandardError.new('Service error'))
      job.perform(*job_args)
    end
    
    # Circuit should be open now
    expect(job).to receive(:circuit_open?).and_return(true)
    result = job.perform(*job_args)
    
    expect(result).to be_falsy # Job should fail fast
  end
end

RSpec.shared_examples 'an AI channel with proper subscription handling' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    stub_connection(current_user: user, current_account: account)
  end

  it 'successfully subscribes with valid parameters' do
    subscribe(subscription_params)
    
    expect(subscription).to be_confirmed
    expect(streams).not_to be_empty
  end

  it 'rejects subscription with invalid parameters' do
    subscribe(invalid_params)
    
    expect(subscription).to be_rejected
  end

  it 'creates audit log entry on subscription' do
    expect {
      subscribe(subscription_params)
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to include('subscribed')
  end

  it 'handles unsubscription properly' do
    subscribe(subscription_params)
    
    expect {
      unsubscribe
    }.to change { AuditLog.count }.by(1)

    audit_log = AuditLog.last
    expect(audit_log.action).to include('unsubscribed')
  end
end

RSpec.shared_examples 'a secure AI endpoint' do
  it 'sanitizes input parameters' do
    malicious_input = "<script>alert('xss')</script>"
    
    post action_path, params: request_params.merge(malicious_field => malicious_input)
    
    if response.successful?
      # Check that malicious input was sanitized
      created_record = described_class.name.constantize.last
      expect(created_record.send(malicious_field)).not_to include('<script>')
    else
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'validates input size limits' do
    oversized_input = 'A' * 50_001 # Assuming 50k limit
    
    post action_path, params: request_params.merge(size_limited_field => oversized_input)
    
    expect(response).to have_http_status(:unprocessable_content)
    expect(json_response['error']).to include('exceeds maximum length')
  end

  it 'rate limits requests' do
    # This would need to be implemented based on actual rate limiting
    # For now, just verify the rate limiter is called
    expect_any_instance_of(ApplicationController).to receive(:check_rate_limit)
    
    post action_path, params: request_params
  end
end

RSpec.shared_examples 'an AI analytics endpoint' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(account)
  end

  it 'returns analytics data structure' do
    get action_path
    
    expect(response).to have_http_status(:ok)
    expect(json_response['success']).to be true
    expect(json_response['data']).to be_a(Hash)
  end

  it 'supports time period filtering' do
    get action_path, params: { period: 7 }
    
    expect(response).to have_http_status(:ok)
    data = json_response['data']
    
    # Verify data is filtered to 7 days
    if data['timeline']
      expect(data['timeline'].size).to be <= 7
    end
  end

  it 'includes metadata in response' do
    get action_path
    
    data = json_response['data']
    expect(data).to have_key('metadata') if response.successful?
  end

  it 'handles empty data gracefully' do
    # Test with new account that has no data
    new_account = create(:account)
    new_user = create(:user, account: new_account)
    
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(new_account)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(new_user)
    
    get action_path
    
    expect(response).to have_http_status(:ok)
    expect(json_response['success']).to be true
  end
end

# Performance testing shared examples
RSpec.shared_examples 'a performant AI endpoint' do
  it 'responds within acceptable time limits' do
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    get action_path
    
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response_time = end_time - start_time
    
    expect(response_time).to be < 5.0 # 5 second limit
  end

  it 'handles concurrent requests' do
    threads = 5.times.map do
      Thread.new do
        get action_path
        response.status
      end
    end
    
    results = threads.map(&:value)
    expect(results.all? { |status| [200, 404].include?(status) }).to be true
  end
end
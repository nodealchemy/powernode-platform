# Backend Test Engineer Specialist Guide

## Role & Responsibilities

The Backend Test Engineer specializes in creating comprehensive test suites for API endpoints, business logic, and data integrity for Powernode's Rails 8 subscription platform.

### Core Responsibilities
- Writing RSpec tests for models and controllers
- Creating integration tests for API endpoints
- Testing payment processing and webhooks
- Implementing test factories and fixtures
- Setting up continuous testing workflows

### Key Focus Areas
- Comprehensive test coverage for subscription business logic
- TDD practices and red-green-refactor cycles
- Robust payment processing test scenarios
- API contract testing and validation
- Performance and load testing strategies

## Backend Testing Architecture Standards

### 1. RSpec Configuration (MANDATORY)

#### RSpec Setup and Configuration
```ruby
# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  
  add_group 'Models', 'app/models'
  add_group 'Controllers', 'app/controllers'
  add_group 'Services', 'app/services'
  add_group 'Jobs', 'app/jobs'
  
  minimum_coverage 90
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true
  
  # Use documentation format for focused specs
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end

# spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'factory_bot_rails'
require 'shoulda/matchers'
require 'database_cleaner/active_record'
require 'webmock/rspec'
require 'vcr'

# Prevent HTTP requests during testing
WebMock.disable_net_connect!(allow_localhost: true, allow: ['chromedriver.storage.googleapis.com'])

# VCR configuration for external API testing
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.ignore_localhost = true
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }
end

Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_path = "#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Factory Bot configuration
  config.include FactoryBot::Syntax::Methods

  # Database cleaner configuration
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # Authentication helpers
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :controller

  # Time travel helpers
  config.around(:each, :time_travel) do |example|
    travel_to Time.zone.parse('2024-01-15 10:00:00') do
      example.run
    end
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

### 2. Factory Bot Setup (MANDATORY)

#### Model Factories
```ruby
# spec/factories/accounts.rb
FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    sequence(:subdomain) { |n| "account#{n}" }
    status { 'active' }
    
    trait :with_subscription do
      after(:create) do |account|
        create(:subscription, account: account)
      end
    end
    
    trait :suspended do
      status { 'suspended' }
      suspended_at { 1.day.ago }
    end
    
    trait :with_users do |account|
      after(:create) do |account|
        create_list(:user, 2, account: account)
      end
    end
  end
end

# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    password { 'SecurePassword123!' }
    email_verified { true }
    email_verified_at { 1.day.ago }
    
    trait :admin do
      after(:create) do |user|
        admin_role = create(:role, name: 'system.admin')
        create(:user_role, user: user, role: admin_role)
      end
    end
    
    trait :account_manager do
      after(:create) do |user|
        manager_role = create(:role, name: 'account.manager')
        create(:user_role, user: user, role: manager_role)
      end
    end
    
    trait :unverified do
      email_verified { false }
      email_verified_at { nil }
    end
    
    trait :suspended do
      status { 'suspended' }
      suspended_at { 1.day.ago }
    end
  end
end

# spec/factories/subscriptions.rb
FactoryBot.define do
  factory :subscription do
    association :account
    association :plan
    status { 'active' }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month }
    next_billing_date { Time.current.end_of_month }
    
    trait :monthly do
      association :plan, :monthly
    end
    
    trait :annual do
      association :plan, :annual
    end
    
    trait :past_due do
      status { 'past_due' }
      became_past_due_at { 3.days.ago }
    end
    
    trait :cancelled do
      status { 'cancelled' }
      cancelled_at { 1.day.ago }
      cancellation_reason { 'user_requested' }
    end
    
    trait :with_payments do
      after(:create) do |subscription|
        create_list(:payment, 3, :succeeded, subscription: subscription)
      end
    end
  end
end

# spec/factories/plans.rb
FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    sequence(:slug) { |n| "plan-#{n}" }
    description { "A great subscription plan" }
    price_cents { 2999 } # $29.99
    currency { 'USD' }
    billing_interval { 'month' }
    trial_days { 7 }
    
    trait :monthly do
      billing_interval { 'month' }
      price_cents { 2999 }
    end
    
    trait :annual do
      billing_interval { 'year' }
      price_cents { 29999 } # $299.99
    end
    
    trait :free do
      price_cents { 0 }
      name { 'Free Plan' }
    end
    
    trait :with_features do
      after(:create) do |plan|
        plan.update!(features: {
          'api_calls' => 10000,
          'storage_gb' => 100,
          'team_members' => 10
        })
      end
    end
  end
end

# spec/factories/payments.rb
FactoryBot.define do
  factory :payment do
    association :subscription
    association :payment_method
    amount_cents { 2999 }
    currency { 'USD' }
    status { 'pending' }
    
    trait :succeeded do
      status { 'succeeded' }
      processed_at { Time.current }
      stripe_payment_intent_id { "pi_#{SecureRandom.hex(12)}" }
    end
    
    trait :failed do
      status { 'failed' }
      processed_at { Time.current }
      failure_reason { 'insufficient_funds' }
    end
    
    trait :refunded do
      status { 'succeeded' }
      refunded_amount_cents { 2999 }
      refunded_at { Time.current }
    end
  end
end
```

### 3. Model Testing Standards (MANDATORY)

#### Model Test Examples
```ruby
# spec/models/subscription_spec.rb
require 'rails_helper'

RSpec.describe Subscription, type: :model do
  subject(:subscription) { build(:subscription) }

  # Association tests
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:plan) }
    it { should have_many(:payments).dependent(:destroy) }
    it { should have_many(:invoices).dependent(:destroy) }
    it { should have_many(:subscription_changes).dependent(:destroy) }
  end

  # Validation tests
  describe 'validations' do
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending active past_due cancelled suspended expired]) }
    it { should validate_presence_of(:current_period_start) }
    it { should validate_presence_of(:current_period_end) }
    
    it 'validates that current_period_end is after current_period_start' do
      subscription.current_period_start = 1.day.from_now
      subscription.current_period_end = Time.current
      expect(subscription).to be_invalid
      expect(subscription.errors[:current_period_end]).to include('must be after start date')
    end
  end

  # Scope tests
  describe 'scopes' do
    let!(:active_subscription) { create(:subscription, status: 'active') }
    let!(:cancelled_subscription) { create(:subscription, status: 'cancelled') }
    let!(:past_due_subscription) { create(:subscription, status: 'past_due') }

    describe '.active' do
      it 'returns only active subscriptions' do
        expect(Subscription.active).to contain_exactly(active_subscription)
      end
    end

    describe '.renewable' do
      it 'returns subscriptions that can be renewed' do
        expect(Subscription.renewable).to contain_exactly(active_subscription, past_due_subscription)
      end
    end

    describe '.due_for_renewal' do
      let!(:due_subscription) { create(:subscription, next_billing_date: 1.day.ago) }
      
      it 'returns subscriptions due for renewal' do
        expect(Subscription.due_for_renewal).to include(due_subscription)
      end
    end
  end

  # State machine tests
  describe 'state transitions' do
    context 'when activating a pending subscription' do
      let(:subscription) { create(:subscription, status: 'pending') }

      it 'transitions to active status' do
        expect { subscription.activate! }.to change(subscription, :status).from('pending').to('active')
      end

      it 'sets billing cycle dates' do
        subscription.activate!
        expect(subscription.current_period_start).to be_within(1.second).of(Time.current)
        expect(subscription.current_period_end).to be > subscription.current_period_start
      end

      it 'schedules next billing' do
        expect(WorkerJobService).to receive(:enqueue_billing_job).with(
          'subscription_renewal',
          hash_including(subscription_id: subscription.id)
        )
        subscription.activate!
      end
    end

    context 'when marking subscription as past due' do
      let(:subscription) { create(:subscription, :active) }

      it 'transitions to past_due status' do
        expect { subscription.mark_past_due! }.to change(subscription, :status).from('active').to('past_due')
      end

      it 'starts dunning process' do
        expect(WorkerJobService).to receive(:enqueue_billing_job).with(
          'dunning_process_start',
          hash_including(subscription_id: subscription.id)
        )
        subscription.mark_past_due!
      end
    end

    context 'when cancelling subscription' do
      let(:subscription) { create(:subscription, :active) }

      it 'transitions to cancelled status' do
        expect { subscription.cancel! }.to change(subscription, :status).from('active').to('cancelled')
      end

      it 'sets cancellation timestamp' do
        subscription.cancel!
        expect(subscription.cancelled_at).to be_within(1.second).of(Time.current)
      end

      it 'cancels scheduled billing' do
        expect(WorkerJobService).to receive(:cancel_billing_job).with(
          'subscription_renewal',
          subscription_id: subscription.id
        )
        subscription.cancel!
      end
    end
  end

  # Instance method tests
  describe '#days_until_renewal' do
    it 'returns correct days when next billing date is in future' do
      subscription.next_billing_date = 3.days.from_now
      expect(subscription.days_until_renewal).to eq(3)
    end

    it 'returns 0 when next billing date is in past' do
      subscription.next_billing_date = 2.days.ago
      expect(subscription.days_until_renewal).to eq(0)
    end
  end

  describe '#current_billing_cycle' do
    let(:subscription) do
      create(:subscription, 
        current_period_start: 10.days.ago,
        current_period_end: 20.days.from_now
      )
    end

    it 'returns correct billing cycle information' do
      cycle = subscription.current_billing_cycle
      
      expect(cycle[:start]).to eq(subscription.current_period_start)
      expect(cycle[:end]).to eq(subscription.current_period_end)
      expect(cycle[:days_total]).to eq(30)
      expect(cycle[:days_remaining]).to eq(20)
    end
  end

  describe '#prorated_amount_for_upgrade' do
    let(:subscription) { create(:subscription, :monthly) }
    let(:new_plan) { create(:plan, price_cents: 4999) }

    it 'delegates to proration calculator service' do
      expect(ProrationCalculatorService).to receive(:call).with(
        subscription: subscription,
        new_plan: new_plan,
        change_date: Time.current
      ).and_return(double(result: 1500))

      expect(subscription.prorated_amount_for_upgrade(new_plan)).to eq(1500)
    end
  end
end

# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  # Password security tests
  describe 'password security' do
    let(:user) { build(:user) }

    context 'with valid password' do
      it 'accepts strong password' do
        user.password = 'StrongPassword123!'
        expect(user).to be_valid
      end
    end

    context 'with weak password' do
      it 'rejects password shorter than 12 characters' do
        user.password = 'Short1!'
        expect(user).to be_invalid
        expect(user.errors[:password]).to include('must be at least 12 characters')
      end

      it 'rejects password without uppercase letter' do
        user.password = 'lowercase123!'
        expect(user).to be_invalid
      end

      it 'rejects password without special character' do
        user.password = 'NoSpecialChar123'
        expect(user).to be_invalid
      end
    end

    it 'stores password history' do
      user.save!
      expect { user.update!(password: 'NewPassword123!') }.to change(PasswordHistory, :count).by(1)
    end

    it 'prevents password reuse' do
      user.save!
      old_password = user.password
      
      user.update!(password: 'NewPassword123!')
      user.password = old_password
      
      expect(user).to be_invalid
      expect(user.errors[:password]).to include('cannot be reused')
    end
  end

  # Permission system tests
  describe '#permissions' do
    let(:user) { create(:user) }
    let(:role) { create(:role, name: 'account.manager') }
    let(:permission1) { create(:permission, name: 'users.read', resource: 'users', action: 'read') }
    let(:permission2) { create(:permission, name: 'users.write', resource: 'users', action: 'write') }

    before do
      create(:role_permission, role: role, permission: permission1)
      create(:role_permission, role: role, permission: permission2)
      create(:user_role, user: user, role: role)
    end

    it 'returns all permissions from user roles' do
      expect(user.permissions).to contain_exactly('users.read', 'users.write')
    end

    it 'handles users with no roles' do
      user_without_roles = create(:user)
      expect(user_without_roles.permissions).to be_empty
    end
  end

  # Email verification tests
  describe 'email verification' do
    let(:user) { create(:user, :unverified) }

    describe '#generate_email_verification_token' do
      it 'generates a secure token' do
        user.generate_email_verification_token
        expect(user.email_verification_token).to be_present
        expect(user.email_verification_expires_at).to be > Time.current
      end
    end

    describe '#verify_email!' do
      before { user.generate_email_verification_token }

      it 'marks email as verified' do
        user.verify_email!
        expect(user.email_verified).to be true
        expect(user.email_verified_at).to be_within(1.second).of(Time.current)
        expect(user.email_verification_token).to be_nil
      end
    end
  end
end
```

### 4. Controller and Request Testing (MANDATORY)

#### API Controller Tests
```ruby
# spec/requests/api/v1/subscriptions_spec.rb
require 'rails_helper'

RSpec.describe 'Api::V1::Subscriptions', type: :request do
  let(:account) { create(:account, :with_subscription) }
  let(:user) { create(:user, account: account) }
  let(:subscription) { account.subscriptions.first }
  
  before { sign_in(user) }

  describe 'GET /api/v1/subscriptions' do
    let!(:subscriptions) { create_list(:subscription, 3, account: account) }

    it 'returns list of subscriptions' do
      get '/api/v1/subscriptions'
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']).to be_an(Array)
      expect(json_response['data'].size).to eq(4) # 3 created + 1 from account trait
    end

    it 'includes subscription details' do
      get '/api/v1/subscriptions'
      
      subscription_data = json_response['data'].first
      expect(subscription_data).to include(
        'id',
        'status',
        'plan',
        'current_period',
        'created_at',
        'updated_at'
      )
    end

    it 'supports pagination' do
      get '/api/v1/subscriptions', params: { page: 1, per_page: 2 }
      
      expect(json_response['data'].size).to eq(2)
      expect(json_response['meta']['pagination']).to include(
        'current_page' => 1,
        'per_page' => 2,
        'total_count' => 4
      )
    end

    context 'without authentication' do
      before { sign_out }

      it 'returns unauthorized' do
        get '/api/v1/subscriptions'
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/subscriptions/:id' do
    it 'returns subscription details' do
      get "/api/v1/subscriptions/#{subscription.id}"
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['id']).to eq(subscription.id)
    end

    it 'includes detailed subscription information' do
      get "/api/v1/subscriptions/#{subscription.id}"
      
      data = json_response['data']
      expect(data).to include(
        'payment_methods',
        'recent_payments',
        'next_billing_date'
      )
    end

    context 'with non-existent subscription' do
      it 'returns not found' do
        get '/api/v1/subscriptions/non-existent-id'
        
        expect(response).to have_http_status(:not_found)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Subscription not found')
      end
    end

    context 'with subscription from different account' do
      let(:other_subscription) { create(:subscription) }

      it 'returns not found' do
        get "/api/v1/subscriptions/#{other_subscription.id}"
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/subscriptions' do
    let(:plan) { create(:plan) }
    let(:payment_method) { create(:payment_method, account: account) }
    
    let(:valid_params) do
      {
        subscription: {
          plan_id: plan.id,
          payment_method_id: payment_method.id
        }
      }
    end

    context 'with valid parameters' do
      it 'creates a new subscription' do
        expect do
          post '/api/v1/subscriptions', params: valid_params
        end.to change(Subscription, :count).by(1)
      end

      it 'returns created subscription' do
        post '/api/v1/subscriptions', params: valid_params
        
        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
        expect(json_response['data']['plan']['id']).to eq(plan.id)
      end

      it 'delegates to subscription creation service' do
        expect(SubscriptionCreationService).to receive(:call).with(
          account: account,
          plan: plan,
          payment_method_id: payment_method.id
        ).and_return(double(success?: true, data: { subscription: subscription }))

        post '/api/v1/subscriptions', params: valid_params
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors for missing plan' do
        post '/api/v1/subscriptions', params: { 
          subscription: { payment_method_id: payment_method.id } 
        }
        
        expect(response).to have_http_status(:bad_request)
        expect(json_response['success']).to be false
        expect(json_response['details']).to include('Plan ID is required')
      end

      it 'returns validation errors for invalid plan' do
        post '/api/v1/subscriptions', params: {
          subscription: {
            plan_id: 'invalid-id',
            payment_method_id: payment_method.id
          }
        }
        
        expect(response).to have_http_status(:bad_request)
        expect(json_response['details']).to include('Invalid plan ID')
      end
    end

    context 'when subscription creation fails' do
      before do
        allow(SubscriptionCreationService).to receive(:call).and_return(
          double(success?: false, error: 'Payment failed', details: { code: 'payment_error' })
        )
      end

      it 'returns service error' do
        post '/api/v1/subscriptions', params: valid_params
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Payment failed')
      end
    end
  end

  describe 'PATCH /api/v1/subscriptions/:id' do
    let(:new_plan) { create(:plan, price_cents: 4999) }
    
    let(:update_params) do
      {
        subscription: {
          plan_id: new_plan.id
        }
      }
    end

    context 'with valid plan change' do
      it 'updates the subscription' do
        patch "/api/v1/subscriptions/#{subscription.id}", params: update_params
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end

      it 'delegates to subscription update service' do
        expect(SubscriptionUpdateService).to receive(:call).with(
          subscription: subscription,
          new_plan: new_plan
        ).and_return(double(success?: true))

        patch "/api/v1/subscriptions/#{subscription.id}", params: update_params
      end
    end

    context 'when update service fails' do
      before do
        allow(SubscriptionUpdateService).to receive(:call).and_return(
          double(success?: false, error: 'Proration failed', details: {})
        )
      end

      it 'returns service error' do
        patch "/api/v1/subscriptions/#{subscription.id}", params: update_params
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('Proration failed')
      end
    end
  end

  describe 'DELETE /api/v1/subscriptions/:id' do
    context 'with valid cancellation' do
      it 'cancels the subscription' do
        delete "/api/v1/subscriptions/#{subscription.id}"
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']).to include('cancelled_at')
      end

      it 'delegates to subscription cancellation service' do
        expect(SubscriptionCancellationService).to receive(:call).with(
          subscription: subscription
        ).and_return(double(success?: true))

        delete "/api/v1/subscriptions/#{subscription.id}"
      end
    end
  end
end
```

### 5. Service Testing Standards (MANDATORY)

#### Service Class Tests
```ruby
# spec/services/subscription_lifecycle_service_spec.rb
require 'rails_helper'

RSpec.describe SubscriptionLifecycleService, type: :service do
  subject(:service) { described_class.new(subscription: subscription, action: action) }
  
  let(:subscription) { create(:subscription) }
  let(:action) { 'activate' }

  describe 'validations' do
    it { should validate_presence_of(:subscription) }
    it { should validate_presence_of(:action) }
    it { should validate_inclusion_of(:action).in_array(%w[activate cancel suspend reactivate upgrade downgrade]) }
  end

  describe '#call' do
    context 'with activate action' do
      let(:subscription) { create(:subscription, status: 'pending') }
      let(:action) { 'activate' }

      context 'when subscription can be activated' do
        it 'returns success result' do
          result = service.call
          
          expect(result.success?).to be true
          expect(result.data).to include(:subscription)
        end

        it 'activates the subscription' do
          expect { service.call }.to change(subscription, :status).from('pending').to('active')
        end

        it 'schedules welcome notification' do
          expect(WorkerJobService).to receive(:enqueue_billing_job).with(
            'subscription_activated_notification',
            hash_including(subscription_id: subscription.id)
          )
          
          service.call
        end

        context 'when subscription requires activation invoice' do
          let(:subscription) { create(:subscription, :pending, plan: create(:plan, price_cents: 2999)) }

          it 'creates activation invoice' do
            expect(InvoiceGenerationService).to receive(:call).with(
              subscription: subscription,
              invoice_type: 'activation',
              due_date: Time.current
            )
            
            service.call
          end
        end
      end

      context 'when subscription cannot be activated' do
        let(:subscription) { create(:subscription, status: 'cancelled') }

        it 'returns failure result' do
          result = service.call
          
          expect(result.success?).to be false
          expect(result.error).to include('Cannot activate subscription')
        end
      end
    end

    context 'with cancel action' do
      let(:subscription) { create(:subscription, :active) }
      let(:action) { 'cancel' }
      let(:metadata) { { cancellation_type: 'immediate', reason: 'user_requested' } }

      before { service.metadata = metadata }

      context 'with immediate cancellation' do
        it 'cancels subscription immediately' do
          expect { service.call }.to change(subscription, :status).from('active').to('cancelled')
        end

        it 'calculates refund amount' do
          expect(service).to receive(:calculate_refund_amount).and_return(1000)
          
          result = service.call
          expect(result.data[:refund_amount_cents]).to eq(1000)
        end

        context 'when refund is due' do
          before do
            allow(service).to receive(:calculate_refund_amount).and_return(1500)
          end

          it 'enqueues refund processing' do
            expect(WorkerJobService).to receive(:enqueue_billing_job).with(
              'process_refund',
              hash_including(
                subscription_id: subscription.id,
                refund_amount_cents: 1500
              )
            )
            
            service.call
          end
        end
      end

      context 'with end-of-period cancellation' do
        let(:metadata) { { cancellation_type: 'end_of_period', reason: 'user_requested' } }

        it 'schedules cancellation for end of period' do
          result = service.call
          
          expect(subscription.reload.cancellation_scheduled).to be true
          expect(subscription.cancellation_date).to eq(subscription.current_period_end)
          expect(result.data[:cancellation_scheduled_for]).to be_present
        end

        it 'enqueues scheduled cancellation job' do
          expect(WorkerJobService).to receive(:enqueue_billing_job).with(
            'scheduled_cancellation',
            hash_including(
              subscription_id: subscription.id,
              scheduled_for: subscription.current_period_end.iso8601
            )
          )
          
          service.call
        end
      end
    end

    context 'with upgrade action' do
      let(:action) { 'upgrade' }
      let(:new_plan) { create(:plan, price_cents: 4999) }
      let(:metadata) { { new_plan_id: new_plan.id } }

      before { service.metadata = metadata }

      it 'delegates to subscription plan change service' do
        expect(SubscriptionPlanChangeService).to receive(:call).with(
          subscription: subscription,
          new_plan: new_plan,
          change_type: 'upgrade',
          effective_date: Time.current
        ).and_return(double(success?: true, data: { updated: true }))

        result = service.call
        expect(result.success?).to be true
      end
    end

    context 'with invalid action' do
      let(:action) { 'invalid_action' }

      it 'returns validation failure' do
        result = service.call
        
        expect(result.success?).to be false
        expect(result.error).to eq('Invalid parameters')
        expect(result.details).to include('Action is not included in the list')
      end
    end
  end

  describe '#calculate_refund_amount' do
    let(:subscription) do
      create(:subscription, 
        :active,
        current_period_start: 30.days.ago,
        current_period_end: Time.current,
        plan: create(:plan, price_cents: 3000)
      )
    end

    context 'when subscription period has ended' do
      it 'returns zero refund' do
        refund = service.send(:calculate_refund_amount)
        expect(refund).to eq(0)
      end
    end

    context 'when subscription has remaining time' do
      let(:subscription) do
        create(:subscription,
          :active,
          current_period_start: 10.days.ago,
          current_period_end: 20.days.from_now,
          plan: create(:plan, price_cents: 3000)
        )
      end

      it 'calculates prorated refund' do
        # 20 days remaining out of 30 total = 2/3 refund
        expected_refund = (3000 * 20 / 30).round
        refund = service.send(:calculate_refund_amount)
        expect(refund).to eq(expected_refund)
      end
    end
  end
end
```

### 6. Payment and Webhook Testing (MANDATORY)

#### Payment Processing Tests
```ruby
# spec/services/stripe_service_spec.rb
require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:service) { described_class.new }
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }

  before do
    Stripe.api_key = 'sk_test_123'
  end

  describe '#create_customer', :vcr do
    context 'with valid account' do
      it 'creates customer in Stripe' do
        VCR.use_cassette('stripe/create_customer_success') do
          result = service.create_customer(account)
          
          expect(result).to be_a(Stripe::Customer)
          expect(result.email).to eq(account.primary_email)
          expect(account.reload.stripe_customer_id).to be_present
        end
      end
    end

    context 'when Stripe API fails' do
      it 'raises StripeServiceError' do
        VCR.use_cassette('stripe/create_customer_failure') do
          expect { service.create_customer(account) }.to raise_error(
            StripeService::StripeServiceError,
            /Failed to create customer/
          )
        end
      end
    end
  end

  describe '#process_payment' do
    let(:subscription) { create(:subscription, account: account, plan: plan) }
    let(:payment_method) { create(:payment_method, account: account) }

    before do
      account.update!(stripe_customer_id: 'cus_test123')
      subscription.update!(default_payment_method: payment_method)
    end

    context 'with valid payment' do
      it 'processes payment successfully', :vcr do
        VCR.use_cassette('stripe/payment_success') do
          payment_intent = service.process_payment(subscription, 2999)
          
          expect(payment_intent.status).to eq('succeeded')
          expect(Payment.count).to eq(1)
          
          payment = Payment.last
          expect(payment.subscription).to eq(subscription)
          expect(payment.amount_cents).to eq(2999)
          expect(payment.status).to eq('succeeded')
        end
      end
    end

    context 'when payment fails' do
      it 'raises StripeServiceError', :vcr do
        VCR.use_cassette('stripe/payment_failure') do
          expect { service.process_payment(subscription, 2999) }.to raise_error(
            StripeService::StripeServiceError,
            /Payment processing failed/
          )
        end
      end
    end
  end

  describe '#update_subscription' do
    let(:subscription) { create(:subscription, stripe_subscription_id: 'sub_test123') }
    let(:new_plan) { create(:plan, stripe_price_id: 'price_new123') }

    it 'updates subscription in Stripe', :vcr do
      VCR.use_cassette('stripe/update_subscription') do
        result = service.update_subscription(subscription, new_plan)
        
        expect(result).to be_a(Stripe::Subscription)
        expect(result.items.data.first.price.id).to eq(new_plan.stripe_price_id)
      end
    end
  end
end

# spec/controllers/webhooks/stripe_controller_spec.rb
require 'rails_helper'

RSpec.describe Webhooks::StripeController, type: :controller do
  let(:webhook_secret) { 'whsec_test123' }
  let(:payload) { { test: 'data' }.to_json }
  let(:signature) { 'test_signature' }

  before do
    Rails.configuration.stripe = { webhook_secret: webhook_secret }
  end

  describe 'POST #handle' do
    before do
      request.headers['Stripe-Signature'] = signature
    end

    context 'with valid webhook signature' do
      let(:stripe_event) do
        double('Stripe::Event',
          id: 'evt_test123',
          type: 'payment_intent.succeeded',
          created: Time.current.to_i,
          livemode: false,
          data: double(object: double(id: 'pi_test123'))
        )
      end

      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_return(stripe_event)
      end

      it 'processes webhook successfully' do
        post :handle, body: payload
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['received']).to be true
      end

      it 'creates audit log entry' do
        expect do
          post :handle, body: payload
        end.to change(AuditLog, :count).by(1)
        
        audit_log = AuditLog.last
        expect(audit_log.action).to eq('webhook_received')
        expect(audit_log.resource_type).to eq('Stripe')
      end

      context 'with payment_intent.succeeded event' do
        it 'handles payment success' do
          expect(controller).to receive(:handle_payment_succeeded)
          post :handle, body: payload
        end
      end

      context 'with payment_intent.payment_failed event' do
        let(:stripe_event) do
          double('Stripe::Event', type: 'payment_intent.payment_failed', data: double(object: double(id: 'pi_test123')))
        end

        it 'handles payment failure' do
          expect(controller).to receive(:handle_payment_failed)
          post :handle, body: payload
        end
      end
    end

    context 'with invalid webhook signature' do
      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(
          Stripe::SignatureVerificationError.new('Invalid signature', signature)
        )
      end

      it 'returns bad request' do
        post :handle, body: payload
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to eq('Invalid signature')
      end
    end

    context 'with malformed JSON payload' do
      let(:payload) { 'invalid json' }

      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError)
      end

      it 'returns bad request' do
        post :handle, body: payload
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to eq('Invalid payload')
      end
    end
  end

  describe '#handle_payment_succeeded' do
    let(:payment_intent) { double('PaymentIntent', id: 'pi_test123', metadata: { subscription_id: '123' }) }
    let(:payment) { create(:payment, stripe_payment_intent_id: 'pi_test123', status: 'pending') }
    let(:stripe_event) { double('Event', data: double(object: payment_intent)) }

    before do
      controller.instance_variable_set(:@event, stripe_event)
    end

    it 'updates payment status to succeeded' do
      expect { controller.send(:handle_payment_succeeded) }.to change { payment.reload.status }.to('succeeded')
    end

    it 'enqueues post-processing job' do
      expect(WorkerJobService).to receive(:enqueue_billing_job).with(
        'payment_succeeded',
        hash_including(payment_id: payment.id)
      )
      
      controller.send(:handle_payment_succeeded)
    end
  end
end
```

## Development Commands

### Backend Testing Workflow
```bash
# Run all tests
bundle exec rspec

# Run specific test types
bundle exec rspec spec/models/
bundle exec rspec spec/requests/
bundle exec rspec spec/services/

# Run tests with coverage
COVERAGE=true bundle exec rspec

# Run tests for specific file
bundle exec rspec spec/models/subscription_spec.rb

# Run focused tests
bundle exec rspec spec/models/subscription_spec.rb:45

# Generate test documentation
bundle exec rspec --format documentation

# Run tests in parallel
bundle exec parallel_rspec spec/

# Performance profiling
bundle exec rspec --profile 10
```

### Test Database Management
```bash
# Prepare test database
RAILS_ENV=test rails db:create db:migrate

# Reset test database
RAILS_ENV=test rails db:drop db:create db:migrate

# Load schema without migrations
RAILS_ENV=test rails db:schema:load
```

## Integration Points

### Backend Test Engineer Coordinates With:
- **Data Modeler**: Model validation testing, database constraint testing
- **API Developer**: API contract testing, endpoint validation
- **Payment Integration Specialist**: Payment flow testing, webhook validation
- **Billing Engine Developer**: Service layer testing, business logic validation
- **Security Specialist**: Security testing, authentication/authorization testing

## Quick Reference

### Test Categories
- **Unit Tests**: Models, services, utilities (90%+ coverage)
- **Integration Tests**: API endpoints, controller actions
- **System Tests**: Full user workflows, payment processing
- **Performance Tests**: Load testing, database query performance

### Common Test Patterns
```ruby
# Model testing pattern
RSpec.describe Model, type: :model do
  it { should belong_to(:association) }
  it { should validate_presence_of(:field) }
  
  describe '#method' do
    it 'returns expected result' do
      expect(subject.method).to eq(expected)
    end
  end
end

# Request testing pattern
RSpec.describe 'API Endpoint', type: :request do
  before { sign_in(user) }
  
  it 'returns success response' do
    get '/api/v1/resource'
    expect(response).to have_http_status(:ok)
    expect(json_response['success']).to be true
  end
end

# Service testing pattern
RSpec.describe Service, type: :service do
  describe '#call' do
    context 'with valid params' do
      it 'returns success result' do
        result = service.call
        expect(result.success?).to be true
      end
    end
  end
end
```

**ALWAYS REFERENCE TODO.md FOR CURRENT TASKS AND PRIORITIES**
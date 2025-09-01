# Rails Architect Specialist Guide

## Role & Responsibilities

The Rails Architect specializes in Rails 8 API setup, configuration, and architectural decisions for Powernode's subscription platform.

### Core Responsibilities
- Setting up Rails 8 API-only applications
- Configuring database connections and migrations
- Designing RESTful API endpoints
- Setting up middleware and security configurations
- Implementing authentication systems (JWT)

### Key Focus Areas
- Rails conventions and best practices
- API-only architecture patterns
- Security configuration and middleware
- Database configuration and optimization
- Authentication and authorization systems

## Rails 8 API Architecture Standards

### 1. Standard Controller Pattern (MANDATORY)

**Pattern**: Consistent API Controller Architecture
```ruby
# Standard controller structure following platform conventions
class Api::V1::[Resource]Controller < ApplicationController
  # Include relevant concerns for functionality
  include [Resource]Serialization
  
  # Set resource for actions that need it
  before_action :set_resource, only: [:show, :update, :destroy]
  
  # Permission-based authorization (NOT role-based)
  before_action -> { require_permission('[resource].view') }, only: [:index, :show]
  before_action -> { require_permission('[resource].create') }, only: [:create]
  before_action -> { require_permission('[resource].update') }, only: [:update]
  before_action -> { require_permission('[resource].delete') }, only: [:destroy]
  
  # Standard CRUD operations
  def index
    resources = current_account.[resources].includes(:associated_models)
    
    # Use ApiResponse concern method
    render_success(resources.map { |resource| [resource]_data(resource) })
  end
  
  def show
    # Use ApiResponse concern method  
    render_success([resource]_data(@[resource]))
  end
  
  def create
    @[resource] = current_account.[resources].build([resource]_params)
    
    if @[resource].save
      # Use ApiResponse concern method for 201 Created response
      render_created([resource]_data(@[resource]))
    else
      # Use ApiResponse concern method for validation errors
      render_validation_error(@[resource].errors)
    end
  end
  
  private
  
  def set_[resource]
    @[resource] = current_account.[resources].find(params[:id])
  end
  
  def [resource]_params
    params.require(:[resource]).permit(:attribute1, :attribute2)
  end
end
```

**Key Standards**:
- **Namespace**: All API controllers in `Api::V1` module
- **Inheritance**: Inherit from `ApplicationController`
- **Concerns**: Include serialization and other modular functionality
- **Permissions**: Use `require_permission()` with lambda syntax
- **Response Format**: Consistent `{success, data, error, message}` structure
- **Error Handling**: Structured error responses with details
- **Resource Scoping**: Always scope to `current_account`

### 2. Authentication & Authorization Pattern (CRITICAL)

**Pattern**: Permission-Based Access Control System
```ruby
# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account
  end

  private

  def authenticate_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    return render_unauthorized("Access token required") unless header

    begin
      payload = JwtService.decode(header)
      
      # Handle different token types
      if payload[:type] == 'impersonation'
        handle_impersonation_token(payload)
      else
        handle_regular_token(payload)
      end

      return render_unauthorized("User inactive") unless @current_user.active?
      return render_unauthorized("Account suspended") unless @current_account.active?

    rescue JWT::DecodeError => e
      Rails.logger.warn "JWT decode error: #{e.message}"
      render_unauthorized("Invalid access token")
    rescue JWT::ExpiredSignature
      render_unauthorized("Access token expired")
    end
  end

  def require_permission(permission)
    return render_unauthorized("Permission required") unless current_user
    
    unless current_user.has_permission?(permission)
      Rails.logger.warn "Permission denied: User #{current_user.id} lacks '#{permission}'"
      render_forbidden("Insufficient permissions")
    end
  end

  def render_unauthorized(message = "Unauthorized")
    render json: {
      success: false,
      error: message,
      code: "UNAUTHORIZED"
    }, status: :unauthorized
  end

  def render_forbidden(message = "Forbidden")
    render json: {
      success: false,
      error: message,
      code: "FORBIDDEN"
    }, status: :forbidden
  end

  private

  def handle_regular_token(payload)
    @current_user = User.find(payload[:user_id])
    @current_account = @current_user.account
  rescue ActiveRecord::RecordNotFound
    render_unauthorized("User not found")
  end

  def handle_impersonation_token(payload)
    impersonator = User.find(payload[:impersonator_id])
    impersonated = User.find(payload[:impersonated_user_id])
    
    # Verify impersonation session is still valid
    session = ImpersonationSession.active
                                  .find_by(
                                    impersonator: impersonator,
                                    impersonated_user: impersonated
                                  )
    
    return render_unauthorized("Impersonation session invalid") unless session
    
    @current_user = impersonated
    @current_account = impersonated.account
    @impersonator = impersonator
  rescue ActiveRecord::RecordNotFound
    render_unauthorized("Impersonation users not found")
  end
end
```

**Authentication Features**:
- **JWT Token Validation**: Decode and validate access tokens
- **Impersonation Support**: Handle admin impersonation tokens
- **Permission Checking**: `require_permission()` method for granular access
- **User/Account Context**: Set `current_user` and `current_account`
- **Error Handling**: Consistent unauthorized/forbidden responses

**Permission System Standards**:
- **Format**: `resource.action` (e.g., `users.view`, `billing.manage`)
- **Frontend Rule**: NEVER use roles for access control, only permissions
- **Backend Rule**: Roles assign permissions, controllers check permissions
- **Granularity**: Specific permissions for each action

### 3. Application Configuration (MANDATORY)

#### Rails API-Only Setup
```ruby
# config/application.rb
module Powernode
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    
    # CORS configuration
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          credentials: false
      end
    end
    
    # Rate limiting
    config.middleware.use Rack::Attack
    
    # Custom middleware
    config.middleware.use PciSecurityHeaders
    config.middleware.use AuditLoggingMiddleware
  end
end
```

#### Environment Configuration
```ruby
# config/environments/development.rb
Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true
  
  # Action Cable configuration
  config.action_cable.url = "ws://localhost:3000/cable"
  config.action_cable.allowed_request_origins = [/http:\/\/*/, /https:\/\/*/]
  
  # Logging configuration
  config.log_level = :debug
  config.log_tags = [:request_id, :remote_ip]
end

# config/environments/production.rb
Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  
  # Force SSL and security headers
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path =~ /health/ } } }
  
  # Action Cable for production
  config.action_cable.url = "wss://api.powernode.com/cable"
  config.action_cable.allowed_request_origins = ["https://app.powernode.com"]
  
  # Logging
  config.log_level = :info
  config.log_tags = [:request_id, :remote_ip, :subdomain]
end
```

### 4. Standardized Error Handling Pattern (MANDATORY)

**Pattern**: ApplicationController Error Handling
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Authentication
  include ApiResponse  # CRITICAL: Standard API response concern

  # ApiResponse concern handles all exception responses automatically
  # No manual rescue_from needed - concern provides:
  # - ActiveRecord::RecordNotFound → render_not_found
  # - ActiveRecord::RecordInvalid → render_validation_error  
  # - StandardError → render_internal_error

  # Standard pagination parameters helper
  def pagination_params
    {
      page: [ params[:page]&.to_i || 1, 1 ].max,
      per_page: [ [ params[:per_page]&.to_i || 20, 1 ].max, 100 ].min
    }
  end
end
```

#### ApiResponse Concern Benefits
- **Consistent Response Format**: All endpoints use standardized JSON structure
- **Automatic Error Handling**: Built-in exception rescue and formatting
- **HTTP Status Codes**: Proper status codes for different response types  
- **Pagination Support**: Built-in paginated response helper
- **Extensible**: Easy to add new response patterns

### 5. API Response Examples

  def render_internal_error(exception)
    Rails.logger.error "Internal error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n") if Rails.env.development?

    render json: {
      success: false,
      error: "Internal server error",
      message: Rails.env.development? ? exception.message : "Something went wrong",
      code: "INTERNAL_ERROR"
    }, status: :internal_server_error
  end

  # Pagination helper
  def pagination_params
    {
      page: [params[:page]&.to_i || 1, 1].max,
      per_page: [[params[:per_page]&.to_i || 20, 1].max, 100].min
    }
  end
end
```

**Error Response Standards**:
- **Success Field**: Always include `success: false` for errors
- **Error Field**: Primary error message for user display
- **Details Field**: Array of detailed errors (for validation errors)
- **Code Field**: Machine-readable error code for frontend handling
- **Message Field**: Additional context or technical details
- **HTTP Status**: Appropriate semantic HTTP status codes

### 5. Controller Concern Pattern (RECOMMENDED)

**Pattern**: Reusable Controller Functionality
```ruby
# app/controllers/concerns/user_serialization.rb
module UserSerialization
  extend ActiveSupport::Concern

  private

  def user_data(user, include_roles: false, include_permissions: true)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      status: user.status,
      email_verified: user.email_verified?,
      last_sign_in_at: user.last_sign_in_at,
      permissions: include_permissions ? user.all_permissions : nil,
      roles: include_roles ? user.roles.map(&:name) : nil,
      created_at: user.created_at,
      updated_at: user.updated_at
    }.compact
  end

  def users_data(users, **options)
    users.map { |user| user_data(user, **options) }
  end
end

# Usage in controllers
class Api::V1::UsersController < ApplicationController
  include UserSerialization
  
  def index
    users = current_account.users.includes(:roles)
    render json: {
      success: true,
      data: users_data(users, include_roles: true)
    }, status: :ok
  end
end
```

**Concern Benefits**:
- **DRY Principle**: Avoid code duplication across controllers
- **Consistency**: Standardized data serialization
- **Maintainability**: Centralized serialization logic
- **Testing**: Easier to test serialization logic

### 6. Database Configuration (MANDATORY)

#### Database Setup
```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: <%= ENV['DATABASE_USERNAME'] %>
  password: <%= ENV['DATABASE_PASSWORD'] %>
  host: <%= ENV['DATABASE_HOST'] %>
  port: <%= ENV['DATABASE_PORT'] %>

development:
  <<: *default
  database: powernode_development

test:
  <<: *default
  database: powernode_test

production:
  <<: *default
  database: powernode_production
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
```

#### Database Initializers
```ruby
# config/initializers/uuid_primary_keys.rb
Rails.application.config.generators do |g|
  g.orm :active_record, primary_key_type: :uuid
end

# Enable PostgreSQL extensions
ActiveSupport.on_load(:active_record) do
  connection.execute("CREATE EXTENSION IF NOT EXISTS 'uuid-ossp'")
  connection.execute("CREATE EXTENSION IF NOT EXISTS 'pgcrypto'")
end
```

### 3. Controller Architecture (MANDATORY)

#### Base Controller Pattern
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Authentication
  include RateLimiting
  include AuditLogging
  include UserSerialization
  
  before_action :authenticate_request
  before_action :set_current_user
  around_action :log_request
  
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from StandardError, with: :internal_server_error
  
  private
  
  def not_found(exception)
    render json: {
      success: false,
      error: "Record not found",
      details: exception.message
    }, status: :not_found
  end
  
  def unprocessable_entity(exception)
    render json: {
      success: false,
      error: "Validation failed",
      details: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end
  
  def internal_server_error(exception)
    Rails.logger.error "Internal Server Error: #{exception.message}"
    render json: {
      success: false,
      error: "Internal server error"
    }, status: :internal_server_error
  end
end
```

#### API Versioning Pattern
```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ApplicationController
  before_action :set_api_version
  
  private
  
  def set_api_version
    response.headers['API-Version'] = 'v1'
  end
end

# Example API controller
class Api::V1::SubscriptionsController < Api::V1::BaseController
  before_action :set_subscription, only: [:show, :update, :destroy]
  
  def index
    subscriptions = current_user.account.subscriptions
                                .includes(:plan, :payments)
                                .page(params[:page])
                                .per(params[:per_page] || 20)
    
    render json: {
      success: true,
      data: subscriptions.map { |s| subscription_data(s) },
      pagination: pagination_data(subscriptions)
    }
  end
  
  def show
    render json: {
      success: true,
      data: subscription_data(@subscription)
    }
  end
  
  def create
    subscription = current_user.account.subscriptions.build(subscription_params)
    
    if subscription.save
      render json: {
        success: true,
        data: subscription_data(subscription),
        message: "Subscription created successfully"
      }, status: :created
    else
      render json: {
        success: false,
        error: "Failed to create subscription",
        details: subscription.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  private
  
  def set_subscription
    @subscription = current_user.account.subscriptions.find(params[:id])
  end
  
  def subscription_params
    params.require(:subscription).permit(:plan_id, :status)
  end
  
  def subscription_data(subscription)
    {
      id: subscription.id,
      status: subscription.status,
      plan: {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price: subscription.plan.price.format
      },
      current_period_start: subscription.current_period_start&.iso8601,
      current_period_end: subscription.current_period_end&.iso8601,
      created_at: subscription.created_at.iso8601,
      updated_at: subscription.updated_at.iso8601
    }
  end
end
```

### 4. Authentication Architecture (MANDATORY)

#### JWT Authentication Implementation
```ruby
# app/services/jwt_service.rb
class JwtService
  SECRET_KEY = Rails.application.secrets.secret_key_base

  def self.encode(payload, exp = 15.minutes.from_now)
    payload[:exp] = exp.to_i
    JWT.encode(payload, SECRET_KEY, 'HS256')
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: 'HS256' })[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end

# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern
  
  included do
    attr_reader :current_user
  end
  
  private
  
  def authenticate_request
    header = request.headers['Authorization']
    header = header.split(' ').last if header
    
    begin
      @decoded = JwtService.decode(header)
      @current_user = User.find(@decoded[:user_id]) if @decoded
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
      @current_user = nil
    end
    
    render_unauthorized unless @current_user
  end
  
  def set_current_user
    Current.user = @current_user if @current_user
  end
  
  def render_unauthorized
    render json: {
      success: false,
      error: 'Unauthorized access'
    }, status: :unauthorized
  end
end
```

#### Authentication Controllers
```ruby
# app/controllers/api/v1/auth_controller.rb
class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_request, only: [:login, :register, :forgot_password]
  
  def login
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      if user.email_verified?
        token = JwtService.encode(user_id: user.id)
        refresh_token = generate_refresh_token(user)
        
        render json: {
          success: true,
          data: {
            token: token,
            refresh_token: refresh_token,
            user: user_data(user)
          },
          message: "Login successful"
        }
      else
        render json: {
          success: false,
          error: "Please verify your email before logging in"
        }, status: :unauthorized
      end
    else
      render json: {
        success: false,
        error: "Invalid email or password"
      }, status: :unauthorized
    end
  end
  
  def register
    user = User.new(registration_params)
    user.account = Account.create!(name: "#{user.email} Account")
    
    if user.save
      UserMailer.email_verification(user).deliver_now
      render json: {
        success: true,
        message: "Registration successful. Please check your email to verify your account.",
        data: { email: user.email }
      }, status: :created
    else
      render json: {
        success: false,
        error: "Registration failed",
        details: user.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  private
  
  def registration_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name)
  end
  
  def generate_refresh_token(user)
    JwtService.encode({ user_id: user.id, type: 'refresh' }, 7.days.from_now)
  end
end
```

### 5. Middleware Configuration (MANDATORY)

#### Security Middleware
```ruby
# app/middleware/pci_security_headers.rb
class PciSecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    # PCI DSS required security headers
    headers['X-Frame-Options'] = 'DENY'
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    headers['Content-Security-Policy'] = "default-src 'self'"
    headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    
    [status, headers, response]
  end
end

# app/middleware/audit_logging_middleware.rb
class AuditLoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    start_time = Time.current
    
    status, headers, response = @app.call(env)
    
    # Log API requests for audit trail
    if request.path.start_with?('/api/')
      AuditLoggingService.log_request(
        path: request.path,
        method: request.method,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        status: status,
        duration: Time.current - start_time
      )
    end
    
    [status, headers, response]
  end
end
```

#### Rate Limiting Configuration
```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle all requests by IP (60 requests per minute)
  throttle('req/ip', limit: 60, period: 1.minute) do |req|
    req.ip
  end
  
  # Throttle login attempts by IP (5 attempts per minute)
  throttle('login/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/api/v1/auth/login' && req.post?
  end
  
  # Throttle API requests by user (1000 requests per hour)
  throttle('api/user', limit: 1000, period: 1.hour) do |req|
    if req.path.start_with?('/api/') && req.env['current_user']
      req.env['current_user'].id
    end
  end
  
  # Block known malicious IPs
  blocklist('malicious-ips') do |req|
    Rails.cache.read("blocked_ip:#{req.ip}")
  end
end
```

### 6. WebSocket Configuration (MANDATORY)

#### Action Cable Setup
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token]
      
      if token && (decoded = JwtService.decode(token))
        User.find(decoded[:user_id])
      else
        reject_unauthorized_connection
      end
    rescue ActiveRecord::RecordNotFound
      reject_unauthorized_connection
    end
  end
end

# app/channels/application_cable/channel.rb
module ApplicationCable
  class Channel < ActionCable::Channel::Base
    protected
    
    def current_account
      current_user&.account
    end
  end
end
```

#### Subscription Channel Example
```ruby
# app/channels/subscription_channel.rb
class SubscriptionChannel < ApplicationCable::Channel
  def subscribed
    stream_from "subscription_#{current_account.id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
```

### 7. Routing Configuration (MANDATORY)

#### API Routes Structure
```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Health check endpoints
  get '/health', to: 'health#show'
  get '/health/deep', to: 'health#deep'
  
  # WebSocket cable
  mount ActionCable.server => '/cable'
  
  # API versioning
  namespace :api do
    namespace :v1 do
      # Authentication
      post '/auth/login', to: 'auth#login'
      post '/auth/register', to: 'auth#register'
      post '/auth/refresh', to: 'auth#refresh'
      delete '/auth/logout', to: 'auth#logout'
      post '/auth/forgot_password', to: 'auth#forgot_password'
      post '/auth/reset_password', to: 'auth#reset_password'
      
      # User management
      resources :users, only: [:show, :update, :destroy] do
        member do
          put :change_password
          post :verify_email
          post :resend_verification
        end
      end
      
      # Account management
      resource :account, only: [:show, :update]
      
      # Subscriptions and billing
      resources :subscriptions do
        resources :payments, only: [:index, :show]
        resources :invoices, only: [:index, :show]
      end
      
      # Plans
      resources :plans, only: [:index, :show]
      
      # Administrative endpoints
      namespace :admin do
        resources :accounts
        resources :users
        resources :subscriptions
        resources :analytics, only: [:index]
      end
    end
  end
  
  # Webhook endpoints
  namespace :webhooks do
    post '/stripe', to: 'stripe#handle'
    post '/paypal', to: 'paypal#handle'
  end
end
```

### 8. Service Layer Architecture (MANDATORY)

#### Service Pattern Implementation
```ruby
# app/services/base_service.rb
class BaseService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  
  def self.call(*args, **kwargs)
    new(*args, **kwargs).call
  end
  
  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end
  
  protected
  
  def success(data = {}, message = nil)
    ServiceResult.new(success: true, data: data, message: message)
  end
  
  def failure(error, details = {})
    ServiceResult.new(success: false, error: error, details: details)
  end
end

# Service result object
class ServiceResult
  attr_reader :data, :error, :message, :details
  
  def initialize(success:, data: {}, error: nil, message: nil, details: {})
    @success = success
    @data = data
    @error = error
    @message = message
    @details = details
  end
  
  def success?
    @success
  end
  
  def failure?
    !@success
  end
end

# Example service implementation
class SubscriptionCreationService < BaseService
  attribute :account, Account
  attribute :plan, Plan
  attribute :payment_method_id, String
  
  validates :account, :plan, presence: true
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    
    ActiveRecord::Base.transaction do
      subscription = create_subscription
      setup_billing
      send_welcome_email
      
      success(subscription: subscription_data(subscription))
    end
  rescue StandardError => e
    Rails.logger.error "Subscription creation failed: #{e.message}"
    failure("Subscription creation failed", { error: e.message })
  end
  
  private
  
  def create_subscription
    account.subscriptions.create!(
      plan: plan,
      status: 'active',
      current_period_start: Time.current,
      current_period_end: 1.month.from_now
    )
  end
  
  def setup_billing
    # Delegate to payment service or background job
    BillingService.call(subscription: @subscription, payment_method_id: payment_method_id)
  end
  
  def send_welcome_email
    UserMailer.subscription_welcome(@subscription.account.users.first, @subscription).deliver_later
  end
end
```

### 9. Error Handling & Logging (MANDATORY)

#### Structured Error Handling
```ruby
# app/controllers/concerns/error_handling.rb
module ErrorHandling
  extend ActiveSupport::Concern
  
  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_invalid_record
    rescue_from JWT::DecodeError, with: :handle_unauthorized
  end
  
  private
  
  def handle_standard_error(exception)
    Rails.logger.error "#{exception.class}: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    render json: {
      success: false,
      error: "Internal server error"
    }, status: :internal_server_error
  end
  
  def handle_not_found(exception)
    render json: {
      success: false,
      error: "Record not found",
      details: exception.message
    }, status: :not_found
  end
  
  def handle_invalid_record(exception)
    render json: {
      success: false,
      error: "Validation failed",
      details: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end
  
  def handle_unauthorized(exception)
    render json: {
      success: false,
      error: "Unauthorized access"
    }, status: :unauthorized
  end
end
```

#### Logging Configuration
```ruby
# config/initializers/logging.rb
Rails.application.configure do
  config.log_formatter = proc do |severity, datetime, progname, msg|
    {
      timestamp: datetime.iso8601,
      level: severity,
      program: progname,
      message: msg,
      request_id: Thread.current[:request_id]
    }.to_json + "\n"
  end
  
  config.log_tags = [
    :request_id,
    -> request { request.remote_ip },
    -> request { Current.user&.id }
  ]
end
```

### 10. Background Job Integration (MANDATORY)

#### Sidekiq Configuration
```ruby
# config/initializers/sidekiq.rb
require 'sidekiq/web'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  config.queues = %w[critical high default low]
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

# Sidekiq Web UI authentication
Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [ENV['SIDEKIQ_USERNAME'], ENV['SIDEKIQ_PASSWORD']]
end
```

#### Background Job Integration
```ruby
# app/services/worker_job_service.rb
class WorkerJobService
  class WorkerServiceError < StandardError; end
  
  def self.enqueue_billing_job(job_type, job_data)
    begin
      response = worker_api_client.post('/jobs', {
        job_type: job_type,
        job_data: job_data,
        queue: 'billing',
        retry: true
      })
      
      unless response.success?
        raise WorkerServiceError, "Failed to enqueue job: #{response.error}"
      end
      
      Rails.logger.info "Successfully enqueued #{job_type} job: #{job_data[:id]}"
      response.data
    rescue => e
      Rails.logger.error "Worker service error: #{e.message}"
      raise WorkerServiceError, e.message
    end
  end
  
  private
  
  def self.worker_api_client
    @worker_api_client ||= WorkerApiClient.new(
      base_url: ENV['WORKER_API_URL'],
      token: ENV['WORKER_API_TOKEN']
    )
  end
end
```

## Development Commands

### Rails Application Management
```bash
# Generate new Rails API application
rails new powernode --api --database=postgresql --skip-test

# Generate controllers, models, migrations
rails generate controller Api::V1::Subscriptions
rails generate model Subscription account:references plan:references
rails generate migration AddIndexToSubscriptions

# Database operations
rails db:create db:migrate db:seed
rails db:rollback STEP=1
rails db:reset

# Server management
rails server -p 3000
rails console
```

### Testing Commands
```bash
# Run backend tests
bundle exec rspec
bundle exec rspec spec/controllers/
bundle exec rspec spec/models/

# Generate test files
rails generate rspec:controller Api::V1::Subscriptions
rails generate rspec:model Subscription
```

## Integration Points

### Rails Architect Coordinates With:
- **Data Modeler**: Database configuration, migration setup
- **API Developer**: Controller patterns, routing configuration
- **Payment Integration Specialist**: Webhook endpoints, security headers
- **Backend Job Engineer**: Sidekiq integration, job delegation
- **Security Specialist**: Middleware configuration, authentication
- **DevOps Engineer**: Environment configuration, deployment setup

## Quick Reference

### Controller Template
```ruby
class Api::V1::ResourcesController < Api::V1::BaseController
  before_action :set_resource, only: [:show, :update, :destroy]
  
  def index
    resources = current_user.account.resources.page(params[:page])
    render json: { success: true, data: resources.map { |r| resource_data(r) } }
  end
  
  def show
    render json: { success: true, data: resource_data(@resource) }
  end
  
  def create
    resource = current_user.account.resources.build(resource_params)
    
    if resource.save
      render json: { success: true, data: resource_data(resource) }, status: :created
    else
      render json: { success: false, error: "Creation failed", details: resource.errors.full_messages }, status: :unprocessable_content
    end
  end
  
  private
  
  def set_resource
    @resource = current_user.account.resources.find(params[:id])
  end
  
  def resource_params
    params.require(:resource).permit(:name, :status)
  end
  
  def resource_data(resource)
    { id: resource.id, name: resource.name, status: resource.status, created_at: resource.created_at.iso8601 }
  end
end
```

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**
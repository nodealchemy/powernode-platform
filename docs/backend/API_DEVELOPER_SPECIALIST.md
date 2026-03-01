---
Last Updated: 2026-02-28
Platform Version: 0.3.1
---

# API Developer Specialist Guide

## Related References

For common patterns used across multiple specialists, see these consolidated references:
- **[API Response Standards](../platform/API_RESPONSE_STANDARDS.md)** - Unified response format documentation
- **[Permission System Reference](../platform/PERMISSION_SYSTEM_REFERENCE.md)** - Backend/frontend permission patterns

## Role & Responsibilities

The API Developer specializes in creating RESTful API endpoints with proper serialization, error handling, and documentation for Powernode's subscription platform.

### Core Responsibilities
- Implementing CRUD API endpoints
- Handling API versioning and serialization
- Implementing proper error handling
- Adding API documentation
- Optimizing API performance

### Key Focus Areas
- RESTful design principles and conventions
- JSON API serialization patterns
- Comprehensive error handling and validation
- API performance optimization
- Security best practices for API endpoints

## API Development Standards

### 1. Standard API Response Format (CRITICAL)

#### Mandatory Response Structure
All API endpoints MUST use the standardized `ApiResponse` concern for consistent response formatting:

```ruby
# Success Response Format
{
  success: true,
  data: object_or_array,           # Required: actual response data
  meta?: { pagination: {...} }     # Optional: metadata (pagination, etc.)
}

# Error Response Format  
{
  success: false,
  error: "Primary error message",  # Required: user-friendly error
  code?: "ERROR_CODE",            # Optional: machine-readable code
  details?: { errors: [...] }     # Optional: detailed error info
}
```

#### Using ApiResponse Concern (MANDATORY)
All controllers inherit from `ApplicationController` which includes `ApiResponse` concern:

```ruby
class Api::V1::UsersController < ApplicationController
  # ApiResponse concern is automatically included

  def index
    users = current_account.users.page(pagination_params[:page])
                                .per(pagination_params[:per_page])
    
    # Use standardized response methods
    render_paginated(users, serializer: UserSerializer)
  end

  def show
    user = current_account.users.find(params[:id])
    render_success(UserSerializer.new(user).as_json)
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end

  def create
    user = current_account.users.build(user_params)
    
    if user.save
      render_created(UserSerializer.new(user).as_json)
    else
      render_validation_error(user.errors)
    end
  end

  def update  
    user = current_account.users.find(params[:id])
    
    if user.update(user_params)
      render_success(UserSerializer.new(user).as_json)
    else
      render_validation_error(user.errors)
    end
  end

  def destroy
    user = current_account.users.find(params[:id])
    user.destroy!
    render_no_content
  end

  private

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name)
  end
end
```

#### ApiResponse Methods Reference
```ruby
# Success responses
render_success(data = nil, status: :ok, meta: nil)
render_created(data = nil, location: nil)
render_no_content

# Error responses  
render_error(message, status: :bad_request, code: nil, details: nil)
render_validation_error(errors)
render_not_found(resource = "Resource")
render_unauthorized(message = "Authentication required")
render_forbidden(message = "Access denied")
render_internal_error(message = "Internal server error", exception: nil)

# Specialized responses
render_paginated(collection, serializer: nil)
render_bulk_response(successful = [], failed = [])
```

**CRITICAL**: Always use `ApiResponse` concern methods. Never manually create `render json:` responses. Frontend code depends on consistent `success` boolean and `data` structure.

### 2. Controller Architecture (MANDATORY)

#### Base API Controller Pattern
```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ApplicationController
  include Authentication
  include ErrorHandling
  include RateLimiting
  include Pagination
  
  before_action :set_api_version
  before_action :authenticate_request
  around_action :log_api_request
  
  protected
  
  def set_api_version
    response.headers['API-Version'] = 'v1'
    response.headers['Content-Type'] = 'application/json'
  end
  
  def success_response(data, message = nil, status = :ok)
    render json: {
      success: true,
      data: data,
      message: message,
      meta: response_meta
    }.compact, status: status
  end
  
  def error_response(error, details = {}, status = :bad_request)
    render json: {
      success: false,
      error: error,
      details: details,
      meta: response_meta
    }, status: status
  end
  
  def response_meta
    {
      timestamp: Time.current.iso8601,
      api_version: 'v1',
      request_id: request.request_id
    }
  end
  
  def paginate_collection(collection, per_page: 20)
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || per_page, 100].min
    
    collection.page(page).per(per_page)
  end
  
  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value,
      has_next: collection.next_page.present?,
      has_prev: collection.prev_page.present?
    }
  end
end
```

#### Standard CRUD Controller Implementation
```ruby
# app/controllers/api/v1/subscriptions_controller.rb
class Api::V1::SubscriptionsController < Api::V1::BaseController
  before_action :set_subscription, only: [:show, :update, :destroy]
  before_action :validate_subscription_params, only: [:create, :update]
  
  # GET /api/v1/subscriptions
  def index
    subscriptions = current_user.account
                               .subscriptions
                               .includes(:plan, :payments, :invoices)
                               .order(created_at: :desc)
    
    paginated = paginate_collection(subscriptions)
    
    success_response(
      paginated.map { |sub| subscription_data(sub) },
      "Retrieved #{paginated.count} subscriptions",
      :ok
    ).tap do |response|
      response[:meta][:pagination] = pagination_meta(paginated)
    end
  end
  
  # GET /api/v1/subscriptions/:id
  def show
    success_response(
      subscription_data(@subscription, include_details: true),
      "Subscription retrieved successfully"
    )
  end
  
  # POST /api/v1/subscriptions
  def create
    service_result = SubscriptionCreationService.call(
      account: current_user.account,
      plan: Plan.find(subscription_params[:plan_id]),
      payment_method_id: subscription_params[:payment_method_id]
    )
    
    if service_result.success?
      success_response(
        service_result.data[:subscription],
        "Subscription created successfully",
        :created
      )
    else
      error_response(
        service_result.error,
        service_result.details,
        :unprocessable_entity
      )
    end
  end
  
  # PATCH/PUT /api/v1/subscriptions/:id
  def update
    if @subscription.update(subscription_update_params)
      # Delegate complex updates to service layer
      if subscription_params[:plan_id] && subscription_params[:plan_id] != @subscription.plan_id
        service_result = SubscriptionUpdateService.call(
          subscription: @subscription,
          new_plan: Plan.find(subscription_params[:plan_id])
        )
        
        unless service_result.success?
          return error_response(service_result.error, service_result.details, :unprocessable_entity)
        end
      end
      
      success_response(
        subscription_data(@subscription.reload),
        "Subscription updated successfully"
      )
    else
      error_response(
        "Update failed",
        @subscription.errors.full_messages,
        :unprocessable_entity
      )
    end
  end
  
  # DELETE /api/v1/subscriptions/:id
  def destroy
    service_result = SubscriptionCancellationService.call(subscription: @subscription)
    
    if service_result.success?
      success_response(
        { cancelled_at: Time.current.iso8601 },
        "Subscription cancelled successfully"
      )
    else
      error_response(service_result.error, service_result.details, :unprocessable_entity)
    end
  end
  
  # GET /api/v1/subscriptions/:id/payments
  def payments
    payments = @subscription.payments
                           .includes(:payment_method)
                           .order(created_at: :desc)
    
    paginated = paginate_collection(payments)
    
    success_response(
      paginated.map { |payment| payment_data(payment) }
    ).tap do |response|
      response[:meta][:pagination] = pagination_meta(paginated)
    end
  end
  
  private
  
  def set_subscription
    @subscription = current_user.account.subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    error_response("Subscription not found", {}, :not_found)
  end
  
  def subscription_params
    params.require(:subscription).permit(:plan_id, :payment_method_id, :status)
  end
  
  def subscription_update_params
    params.require(:subscription).permit(:plan_id)
  end
  
  def validate_subscription_params
    return unless params[:subscription]
    
    errors = []
    
    if action_name == 'create'
      errors << "Plan ID is required" unless params[:subscription][:plan_id].present?
      errors << "Payment method ID is required" unless params[:subscription][:payment_method_id].present?
    end
    
    if params[:subscription][:plan_id].present?
      plan = Plan.find_by(id: params[:subscription][:plan_id])
      errors << "Invalid plan ID" unless plan
    end
    
    if errors.any?
      error_response("Validation failed", errors, :bad_request)
    end
  end
  
  def subscription_data(subscription, include_details: false)
    base_data = {
      id: subscription.id,
      status: subscription.status,
      plan: {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price: subscription.plan.price.format,
        billing_interval: subscription.plan.billing_interval
      },
      current_period: {
        start: subscription.current_period_start&.iso8601,
        end: subscription.current_period_end&.iso8601
      },
      created_at: subscription.created_at.iso8601,
      updated_at: subscription.updated_at.iso8601
    }
    
    if include_details
      base_data.merge!(
        payment_methods: subscription.account.payment_methods.active.map { |pm| payment_method_data(pm) },
        recent_payments: subscription.payments.recent.limit(5).map { |p| payment_data(p) },
        next_billing_date: subscription.next_billing_date&.iso8601,
        cancellation: subscription.cancelled? ? {
          cancelled_at: subscription.cancelled_at&.iso8601,
          cancellation_reason: subscription.cancellation_reason
        } : nil
      )
    end
    
    base_data.compact
  end
  
  def payment_data(payment)
    {
      id: payment.id,
      amount: payment.amount.format,
      currency: payment.currency,
      status: payment.status,
      payment_method: payment.payment_method ? payment_method_data(payment.payment_method) : nil,
      processed_at: payment.processed_at&.iso8601,
      created_at: payment.created_at.iso8601
    }.compact
  end
  
  def payment_method_data(payment_method)
    {
      id: payment_method.id,
      type: payment_method.method_type,
      display_name: payment_method.display_name,
      is_default: payment_method.account.default_payment_method_id == payment_method.id
    }
  end
end
```

### 3. Serialization Standards (CRITICAL)

#### Consistent Data Serialization Pattern
**MANDATORY**: All model data must be serialized through standardized methods, never expose raw ActiveRecord objects.

```ruby
# app/controllers/concerns/user_serialization.rb
module UserSerialization
  def user_data(user, include_roles: false)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      full_name: "#{user.first_name} #{user.last_name}".strip,
      status: user.status,
      permissions: user.all_permissions,  # Always include permissions
      roles: include_roles ? user.roles.map(&:name) : nil,
      created_at: user.created_at.iso8601,
      updated_at: user.updated_at.iso8601
    }.compact
  end
end

# app/controllers/concerns/subscription_serialization.rb
module SubscriptionSerialization
  def subscription_data(subscription, include_details: false)
    base_data = {
      id: subscription.id,
      status: subscription.status,
      plan: plan_data(subscription.plan),
      current_period: {
        start: subscription.current_period_start&.iso8601,
        end: subscription.current_period_end&.iso8601
      },
      created_at: subscription.created_at.iso8601,
      updated_at: subscription.updated_at.iso8601
    }
    
    if include_details
      base_data.merge!({
        recent_payments: subscription.payments.recent.limit(3).map { |p| payment_data(p) },
        cancellation: subscription.cancelled? ? {
          cancelled_at: subscription.cancelled_at&.iso8601,
          reason: subscription.cancellation_reason
        } : nil
      })
    end
    
    base_data.compact
  end
end
```

**Key Serialization Rules** (from platform patterns analysis):
1. **Always include `id`**: Every serialized object must have its UUID
2. **ISO8601 timestamps**: Use `timestamp.iso8601` for all datetime fields
3. **Permissions not roles**: Always include user permissions for access control
4. **Conditional details**: Use `include_details` parameter for nested data
5. **Compact responses**: Remove nil values with `.compact`
6. **Money formatting**: Use `.format` method for currency display

### 4. API Versioning Strategy (MANDATORY)

#### Version Management
```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    # Current version
    namespace :v1 do
      resources :accounts, only: [:show, :update]
      resources :users do
        member do
          put :change_password
          post :verify_email
        end
      end
      resources :subscriptions do
        member do
          post :cancel
          post :reactivate
          get :usage
        end
        resources :payments, only: [:index, :show]
        resources :invoices, only: [:index, :show]
      end
      resources :plans, only: [:index, :show]
      resources :payment_methods
      
      namespace :admin do
        resources :accounts, :users, :subscriptions, :analytics
      end
    end
    
    # Future version preparation
    namespace :v2 do
      # New endpoints for v2
    end
  end
  
  # API documentation
  get '/api/docs', to: 'api_docs#show'
  get '/api/schema', to: 'api_docs#schema'
end

# Version header handling
class Api::V1::BaseController < ApplicationController
  before_action :check_api_version
  
  private
  
  def check_api_version
    requested_version = request.headers['Accept-Version'] || 'v1'
    supported_versions = %w[v1]
    
    unless supported_versions.include?(requested_version)
      render json: {
        success: false,
        error: "Unsupported API version",
        details: {
          requested: requested_version,
          supported: supported_versions
        }
      }, status: :not_acceptable
    end
  end
end
```

### 3. Serialization Standards (MANDATORY)

#### Custom Serializer Implementation
```ruby
# app/serializers/base_serializer.rb
class BaseSerializer
  def initialize(object, options = {})
    @object = object
    @options = options
  end
  
  def as_json
    raise NotImplementedError, "Subclasses must implement #as_json"
  end
  
  def self.serialize(object, options = {})
    new(object, options).as_json
  end
  
  def self.serialize_collection(collection, options = {})
    collection.map { |item| serialize(item, options) }
  end
  
  protected
  
  def include?(association)
    return false unless @options[:include]
    @options[:include].include?(association.to_s) || @options[:include].include?(association.to_sym)
  end
  
  def format_timestamp(timestamp)
    timestamp&.iso8601
  end
  
  def format_money(money)
    {
      amount: money.cents,
      formatted: money.format,
      currency: money.currency.iso_code
    }
  end
end

# app/serializers/subscription_serializer.rb
class SubscriptionSerializer < BaseSerializer
  def as_json
    base_data = {
      id: @object.id,
      status: @object.status,
      plan: PlanSerializer.serialize(@object.plan),
      current_period: {
        start: format_timestamp(@object.current_period_start),
        end: format_timestamp(@object.current_period_end)
      },
      created_at: format_timestamp(@object.created_at),
      updated_at: format_timestamp(@object.updated_at)
    }
    
    # Conditional includes
    base_data[:account] = AccountSerializer.serialize(@object.account) if include?(:account)
    base_data[:payments] = PaymentSerializer.serialize_collection(@object.payments) if include?(:payments)
    base_data[:invoices] = InvoiceSerializer.serialize_collection(@object.invoices) if include?(:invoices)
    
    base_data.compact
  end
end

# app/serializers/plan_serializer.rb
class PlanSerializer < BaseSerializer
  def as_json
    {
      id: @object.id,
      name: @object.name,
      description: @object.description,
      price: format_money(@object.price),
      billing_interval: @object.billing_interval,
      features: @object.features,
      trial_days: @object.trial_days,
      created_at: format_timestamp(@object.created_at)
    }.tap do |data|
      data[:subscription_count] = @object.subscriptions.active.count if include?(:stats)
    end
  end
end
```

### 4. Error Handling Standards (MANDATORY)

#### Comprehensive Error Handling
```ruby
# app/controllers/concerns/error_handling.rb
module ErrorHandling
  extend ActiveSupport::Concern
  
  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
    rescue_from Pundit::NotAuthorizedError, with: :handle_unauthorized
  end
  
  private
  
  def handle_standard_error(exception)
    Rails.logger.error "API Error: #{exception.class} - #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    # Don't expose internal errors in production
    error_message = Rails.env.production? ? "Internal server error" : exception.message
    
    render json: {
      success: false,
      error: error_message,
      error_code: 'INTERNAL_ERROR',
      meta: error_meta(exception)
    }, status: :internal_server_error
  end
  
  def handle_not_found(exception)
    resource_name = extract_resource_name(exception)
    
    render json: {
      success: false,
      error: "#{resource_name} not found",
      error_code: 'RECORD_NOT_FOUND',
      details: {
        resource: resource_name,
        id: params[:id]
      },
      meta: error_meta(exception)
    }, status: :not_found
  end
  
  def handle_validation_error(exception)
    render json: {
      success: false,
      error: "Validation failed",
      error_code: 'VALIDATION_ERROR',
      details: {
        field_errors: format_validation_errors(exception.record),
        invalid_attributes: exception.record.errors.keys
      },
      meta: error_meta(exception)
    }, status: :unprocessable_entity
  end
  
  def handle_parameter_missing(exception)
    render json: {
      success: false,
      error: "Required parameter missing",
      error_code: 'PARAMETER_MISSING',
      details: {
        missing_parameter: exception.param,
        expected_format: expected_parameter_format(exception.param)
      },
      meta: error_meta(exception)
    }, status: :bad_request
  end
  
  def handle_unauthorized(exception)
    render json: {
      success: false,
      error: "Insufficient permissions",
      error_code: 'UNAUTHORIZED',
      details: {
        required_permission: exception.policy.class.name,
        action: exception.query
      },
      meta: error_meta(exception)
    }, status: :forbidden
  end
  
  def error_meta(exception)
    {
      timestamp: Time.current.iso8601,
      request_id: request.request_id,
      api_version: 'v1',
      error_id: SecureRandom.uuid
    }.tap do |meta|
      meta[:exception_class] = exception.class.name unless Rails.env.production?
    end
  end
  
  def extract_resource_name(exception)
    # Extract model name from error message
    exception.model&.humanize || 'Record'
  end
  
  def format_validation_errors(record)
    record.errors.full_messages.map do |message|
      field = record.errors.details.find { |_, details| 
        details.any? { |d| message.include?(d[:error].to_s) } 
      }&.first
      
      {
        field: field,
        message: message,
        code: record.errors.details[field]&.first&.dig(:error)
      }
    end
  end
  
  def expected_parameter_format(param)
    case param.to_s
    when 'subscription'
      { subscription: { plan_id: 'string', payment_method_id: 'string' } }
    when 'user'
      { user: { email: 'string', password: 'string', first_name: 'string', last_name: 'string' } }
    else
      "Expected #{param} parameter object"
    end
  end
end
```

### 5. API Documentation Standards (MANDATORY)

#### OpenAPI/Swagger Integration
```ruby
# app/controllers/api_docs_controller.rb
class ApiDocsController < ApplicationController
  skip_before_action :authenticate_request
  
  def show
    render json: openapi_schema
  end
  
  def schema
    render json: openapi_schema, content_type: 'application/yaml'
  end
  
  private
  
  def openapi_schema
    @openapi_schema ||= {
      openapi: '3.0.0',
      info: {
        title: 'Powernode API',
        version: 'v1',
        description: 'Subscription platform API for managing accounts, subscriptions, and billing'
      },
      servers: [
        {
          url: "#{request.protocol}#{request.host_with_port}/api/v1",
          description: Rails.env.humanize
        }
      ],
      security: [
        { bearerAuth: [] }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: 'http',
            scheme: 'bearer',
            bearerFormat: 'JWT'
          }
        },
        schemas: api_schemas,
        responses: common_responses
      },
      paths: api_paths
    }
  end
  
  def api_schemas
    {
      Subscription: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          status: { type: 'string', enum: %w[active cancelled suspended] },
          plan: { '$ref': '#/components/schemas/Plan' },
          current_period: {
            type: 'object',
            properties: {
              start: { type: 'string', format: 'date-time' },
              end: { type: 'string', format: 'date-time' }
            }
          },
          created_at: { type: 'string', format: 'date-time' },
          updated_at: { type: 'string', format: 'date-time' }
        },
        required: %w[id status plan current_period created_at updated_at]
      },
      Plan: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string' },
          description: { type: 'string' },
          price: {
            type: 'object',
            properties: {
              amount: { type: 'integer' },
              formatted: { type: 'string' },
              currency: { type: 'string' }
            }
          },
          billing_interval: { type: 'string', enum: %w[month year] }
        }
      },
      Error: {
        type: 'object',
        properties: {
          success: { type: 'boolean', enum: [false] },
          error: { type: 'string' },
          error_code: { type: 'string' },
          details: { type: 'object' },
          meta: {
            type: 'object',
            properties: {
              timestamp: { type: 'string', format: 'date-time' },
              request_id: { type: 'string' },
              api_version: { type: 'string' }
            }
          }
        },
        required: %w[success error error_code meta]
      }
    }
  end
  
  def api_paths
    {
      '/subscriptions' => {
        get: {
          summary: 'List subscriptions',
          description: 'Retrieve all subscriptions for the authenticated user\'s account',
          parameters: [
            {
              name: 'page',
              in: 'query',
              description: 'Page number for pagination',
              schema: { type: 'integer', minimum: 1, default: 1 }
            },
            {
              name: 'per_page',
              in: 'query',
              description: 'Number of items per page',
              schema: { type: 'integer', minimum: 1, maximum: 100, default: 20 }
            }
          ],
          responses: {
            '200' => {
              description: 'Successful response',
              content: {
                'application/json' => {
                  schema: {
                    type: 'object',
                    properties: {
                      success: { type: 'boolean', enum: [true] },
                      data: {
                        type: 'array',
                        items: { '$ref': '#/components/schemas/Subscription' }
                      },
                      meta: {
                        type: 'object',
                        properties: {
                          pagination: {
                            type: 'object',
                            properties: {
                              current_page: { type: 'integer' },
                              total_pages: { type: 'integer' },
                              total_count: { type: 'integer' },
                              per_page: { type: 'integer' }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            },
            '401' => { '$ref': '#/components/responses/Unauthorized' },
            '500' => { '$ref': '#/components/responses/InternalError' }
          }
        },
        post: {
          summary: 'Create subscription',
          description: 'Create a new subscription for the authenticated user\'s account',
          requestBody: {
            required: true,
            content: {
              'application/json' => {
                schema: {
                  type: 'object',
                  properties: {
                    subscription: {
                      type: 'object',
                      properties: {
                        plan_id: { type: 'string', format: 'uuid' },
                        payment_method_id: { type: 'string', format: 'uuid' }
                      },
                      required: %w[plan_id payment_method_id]
                    }
                  }
                }
              }
            }
          },
          responses: {
            '201' => {
              description: 'Subscription created successfully',
              content: {
                'application/json' => {
                  schema: {
                    type: 'object',
                    properties: {
                      success: { type: 'boolean', enum: [true] },
                      data: { '$ref': '#/components/schemas/Subscription' },
                      message: { type: 'string' }
                    }
                  }
                }
              }
            },
            '400' => { '$ref': '#/components/responses/BadRequest' },
            '422' => { '$ref': '#/components/responses/ValidationError' }
          }
        }
      }
    }
  end
  
  def common_responses
    {
      Unauthorized: {
        description: 'Authentication required',
        content: {
          'application/json' => {
            schema: { '$ref': '#/components/schemas/Error' }
          }
        }
      },
      BadRequest: {
        description: 'Bad request',
        content: {
          'application/json' => {
            schema: { '$ref': '#/components/schemas/Error' }
          }
        }
      },
      ValidationError: {
        description: 'Validation error',
        content: {
          'application/json' => {
            schema: { '$ref': '#/components/schemas/Error' }
          }
        }
      },
      InternalError: {
        description: 'Internal server error',
        content: {
          'application/json' => {
            schema: { '$ref': '#/components/schemas/Error' }
          }
        }
      }
    }
  end
end
```

### 6. Performance Optimization (MANDATORY)

#### Query Optimization
```ruby
# app/controllers/concerns/performance_optimization.rb
module PerformanceOptimization
  extend ActiveSupport::Concern
  
  included do
    around_action :measure_performance
  end
  
  private
  
  def measure_performance
    start_time = Time.current
    db_queries_start = count_db_queries
    
    yield
    
    end_time = Time.current
    db_queries_end = count_db_queries
    
    performance_data = {
      duration: ((end_time - start_time) * 1000).round(2),
      db_queries: db_queries_end - db_queries_start,
      endpoint: "#{request.method} #{request.path}"
    }
    
    # Add performance headers
    response.headers['X-Response-Time'] = "#{performance_data[:duration]}ms"
    response.headers['X-DB-Queries'] = performance_data[:db_queries].to_s
    
    # Log slow requests
    if performance_data[:duration] > 1000 # 1 second
      Rails.logger.warn "Slow API request: #{performance_data}"
    end
    
    # Log excessive DB queries
    if performance_data[:db_queries] > 10
      Rails.logger.warn "High DB query count: #{performance_data}"
    end
  end
  
  def count_db_queries
    ActiveRecord::Base.connection.query_cache.size
  end
  
  def optimize_includes(base_relation)
    # Smart includes based on requested fields
    includes = []
    
    if params[:include]&.include?('plan')
      includes << :plan
    end
    
    if params[:include]&.include?('payments')
      includes << { payments: :payment_method }
    end
    
    if params[:include]&.include?('invoices')
      includes << :invoices
    end
    
    includes.any? ? base_relation.includes(*includes) : base_relation
  end
end
```

#### Caching Strategy
```ruby
# app/controllers/concerns/api_caching.rb
module ApiCaching
  extend ActiveSupport::Concern
  
  def cache_key_for(object, version = nil)
    if object.respond_to?(:cache_key_with_version)
      object.cache_key_with_version
    else
      "#{object.class.name.downcase}/#{object.id}-#{version || object.updated_at.to_i}"
    end
  end
  
  def cached_response(cache_key, expires_in: 5.minutes)
    Rails.cache.fetch(cache_key, expires_in: expires_in) do
      yield
    end
  end
  
  def expire_cache_for(object)
    pattern = "#{object.class.name.downcase}/#{object.id}*"
    Rails.cache.delete_matched(pattern)
  end
  
  # Example usage in controller
  def show
    cache_key = cache_key_for(@subscription, params[:include]&.sort&.join('-'))
    
    cached_data = cached_response(cache_key) do
      subscription_data(@subscription, include_details: true)
    end
    
    success_response(cached_data)
  end
end
```

### 7. Security Standards (MANDATORY)

#### API Security Implementation
```ruby
# app/controllers/concerns/api_security.rb
module ApiSecurity
  extend ActiveSupport::Concern
  
  included do
    before_action :validate_content_type
    before_action :validate_request_size
    before_action :check_rate_limits
    after_action :add_security_headers
  end
  
  private
  
  def validate_content_type
    return unless request.post? || request.patch? || request.put?
    
    unless request.content_type == 'application/json'
      render json: {
        success: false,
        error: 'Invalid content type',
        details: { expected: 'application/json', received: request.content_type }
      }, status: :unsupported_media_type
    end
  end
  
  def validate_request_size
    max_size = 1.megabyte
    
    if request.content_length && request.content_length > max_size
      render json: {
        success: false,
        error: 'Request too large',
        details: { max_size: "#{max_size / 1.megabyte}MB" }
      }, status: :payload_too_large
    end
  end
  
  def check_rate_limits
    # Implement rate limiting logic
    user_id = current_user&.id || request.remote_ip
    rate_limit_key = "api_rate_limit:#{user_id}"
    
    current_requests = Rails.cache.read(rate_limit_key) || 0
    
    if current_requests >= rate_limit_per_hour
      render json: {
        success: false,
        error: 'Rate limit exceeded',
        details: {
          limit: rate_limit_per_hour,
          reset_time: 1.hour.from_now.iso8601
        }
      }, status: :too_many_requests
      return
    end
    
    Rails.cache.write(rate_limit_key, current_requests + 1, expires_in: 1.hour)
  end
  
  def add_security_headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
  end
  
  def rate_limit_per_hour
    current_user&.premium? ? 10000 : 1000
  end
end
```

## Development Commands

### API Development Workflow
```bash
# Generate API controllers
rails generate controller Api::V1::Subscriptions
rails generate controller Api::V1::Payments
rails generate controller Api::V1::Plans

# Generate serializers
rails generate serializer Subscription
rails generate serializer Payment
rails generate serializer Plan

# Test API endpoints
curl -X GET http://localhost:3000/api/v1/subscriptions \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json"

# Test API with different versions
curl -X GET http://localhost:3000/api/v1/subscriptions \
  -H "Accept-Version: v1" \
  -H "Authorization: Bearer <token>"
```

### API Testing
```bash
# Run API integration tests
bundle exec rspec spec/requests/api/v1/

# Generate API documentation
rake api:docs:generate

# Validate API responses
rake api:validate_schemas
```

## Integration Points

### API Developer Coordinates With:
- **Rails Architect**: Controller architecture, routing configuration
- **Data Modeler**: Serialization patterns, query optimization
- **Payment Integration Specialist**: Payment endpoint security
- **Security Specialist**: Authentication, rate limiting, validation
- **Backend Test Engineer**: API endpoint testing, integration tests

## Quick Reference

### Controller Template
```ruby
class Api::V1::ResourcesController < Api::V1::BaseController
  before_action :set_resource, only: [:show, :update, :destroy]
  
  def index
    resources = optimize_includes(current_user.account.resources)
    paginated = paginate_collection(resources)
    success_response(serialize_collection(paginated))
  end
  
  def show
    success_response(ResourceSerializer.serialize(@resource, include: params[:include]))
  end
  
  def create
    service_result = ResourceCreationService.call(resource_params)
    
    if service_result.success?
      success_response(service_result.data, "Created successfully", :created)
    else
      error_response(service_result.error, service_result.details, :unprocessable_entity)
    end
  end
  
  private
  
  def set_resource
    @resource = current_user.account.resources.find(params[:id])
  end
  
  def resource_params
    params.require(:resource).permit(:name, :description, :status)
  end
end
```

### Standardized Response Examples

#### Success Response
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "first_name": "John",
    "last_name": "Doe",
    "status": "active",
    "permissions": ["users.read", "billing.read"]
  },
  "message": "User retrieved successfully"
}
```

#### Error Response
```json
{
  "success": false,
  "error": "Validation failed",
  "code": "VALIDATION_ERROR",
  "details": [
    "Email can't be blank",
    "Password is too short (minimum is 12 characters)"
  ]
}
```

#### Paginated Response
```json
{
  "success": true,
  "data": [
    { "id": "uuid1", "name": "Item 1" },
    { "id": "uuid2", "name": "Item 2" }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "total_pages": 5,
      "total_count": 100,
      "per_page": 20
    }
  }
}
```

**Response Format Validation**:
```bash
# Audit response format compliance
grep -r "render json:" server/app/controllers/ | grep -c '"success":'
grep -r "success: true" server/app/controllers/ | wc -l
grep -r "success: false" server/app/controllers/ | wc -l
```

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**
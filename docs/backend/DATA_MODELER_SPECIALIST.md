# Data Modeler Specialist Guide

## Role & Responsibilities

The Data Modeler specializes in database architecture and ActiveRecord model design for Powernode's subscription platform.

### Core Responsibilities
- Designing database schema and relationships
- Creating ActiveRecord models with validations
- Implementing model associations and scopes
- Handling data migrations and versioning
- Optimizing database queries and indexes

### Key Focus Areas
- Subscription business logic: User, Subscription, Plan, Invoice, Payment models
- UUID primary key strategy implementation
- Database relationship optimization
- Data integrity and audit logging

## Database Architecture Standards

### 1. UUID Strategy (CRITICAL)
**MANDATORY**: All models use UUID primary keys.

#### Current Implementation
```ruby
# Current tables use string with limit
string :id, limit: 36, primary_key: true

# New tables should use gen_random_uuid()
string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
```

#### Database Extensions
```ruby
# Required extensions
enable_extension 'pgcrypto'
enable_extension 'uuid-ossp'
```

### 2. Standard Model Structure (CRITICAL)

#### Discovered Model Organization Pattern
**MANDATORY**: All models must follow this exact structure order discovered in platform analysis.

```ruby
class User < ApplicationRecord
  # 1. Authentication (if applicable)
  has_secure_password
  
  # 2. Concerns (modular functionality)
  include PasswordSecurity
  
  # 3. Associations
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_logs, dependent: :nullify
  
  # 4. Validations
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: %w[active inactive suspended] }
  validates :first_name, :last_name, presence: true
  
  # 5. Scopes
  scope :active, -> { where(status: 'active') }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_roles, -> { includes(:roles) }
  
  # 6. Callbacks
  before_validation :normalize_email
  after_create :send_welcome_email
  after_update :audit_changes
  
  # 7. Instance methods
  def full_name
    "#{first_name} #{last_name}".strip
  end
  
  def has_permission?(permission)
    all_permissions.include?(permission)
  end
  
  def all_permissions
    @all_permissions ||= roles.flat_map(&:permissions).map(&:name).uniq
  end
  
  private
  
  # 8. Private methods
  def normalize_email
    self.email = email&.downcase&.strip
  end
  
  def send_welcome_email
    # Implementation
  end
end
```

#### Model Concern Pattern (Discovered)
**CRITICAL**: Use concerns for cross-cutting functionality discovered in platform analysis.

```ruby
# app/models/concerns/password_security.rb
module PasswordSecurity
  extend ActiveSupport::Concern
  
  included do
    has_many :password_histories, dependent: :destroy
    validates :password, length: { minimum: 12 }, on: :create
    validates :password, confirmation: true, if: :password_changed?
    validate :password_complexity
    validate :password_not_recently_used
  end
  
  class_methods do
    def authenticate_with_lockout(email, password, max_attempts: 5)
      user = find_by(email: email&.downcase)
      return nil unless user
      
      if user.locked_out?
        return nil
      end
      
      if user.authenticate(password)
        user.reset_failed_attempts
        user
      else
        user.increment_failed_attempts(max_attempts)
        nil
      end
    end
  end
  
  def locked_out?
    failed_attempts >= 5 && last_failed_attempt > 15.minutes.ago
  end
  
  def reset_failed_attempts
    update_columns(failed_attempts: 0, last_failed_attempt: nil)
  end
  
  def increment_failed_attempts(max_attempts)
    increment!(:failed_attempts)
    update_column(:last_failed_attempt, Time.current)
    
    if failed_attempts >= max_attempts
      # Send security notification
      SecurityNotificationJob.perform_async(id, 'account_locked')
    end
  end
  
  private
  
  def password_complexity
    return unless password.present?
    
    errors = []
    errors << 'must contain at least one uppercase letter' unless password.match?(/[A-Z]/)
    errors << 'must contain at least one lowercase letter' unless password.match?(/[a-z]/)
    errors << 'must contain at least one number' unless password.match?(/\d/)
    errors << 'must contain at least one special character' unless password.match?(/[^A-Za-z0-9]/)
    
    errors.each { |error| self.errors.add(:password, error) }
  end
  
  def password_not_recently_used
    return unless password.present?
    
    recent_passwords = password_histories.order(created_at: :desc).limit(5)
    recent_passwords.each do |history|
      if BCrypt::Password.new(history.password_digest) == password
        errors.add(:password, 'cannot be one of your last 5 passwords')
        break
      end
    end
  end
end
```

### 3. Core Data Models

#### Account Model
```ruby
class Account < ApplicationRecord
  # Primary subscription entity
  has_many :users, dependent: :destroy
  has_one :subscription, dependent: :destroy
  has_many :payments, through: :subscription
  has_many :invoices, through: :subscription
  belongs_to :default_volume, class_name: 'Volume', optional: true
  
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :status, inclusion: { in: %w[active suspended cancelled] }
  
  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
end
```

#### User Model
```ruby
class User < ApplicationRecord
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_logs, dependent: :nullify
  
  validates :email, presence: true, uniqueness: true
  validates :password, length: { minimum: 12 }, allow_blank: true
  
  # Permission-based access control
  def permissions
    roles.joins(:role_permissions)
         .joins(:permissions)
         .pluck('permissions.name')
         .uniq
  end
end
```

#### Subscription Model
```ruby
class Subscription < ApplicationRecord
  belongs_to :account
  belongs_to :plan
  has_many :payments, dependent: :destroy
  has_many :invoices, dependent: :destroy
  
  validates :status, inclusion: { in: %w[active cancelled suspended] }
  validates :current_period_start, :current_period_end, presence: true
  
  scope :active, -> { where(status: 'active') }
  scope :cancelled, -> { where(status: 'cancelled') }
end
```

#### Plan Model
```ruby
class Plan < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :app_plans, dependent: :destroy
  has_many :apps, through: :app_plans
  
  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }
  validates :billing_interval, inclusion: { in: %w[month year] }
  
  monetize :price_cents
end
```

### 4. Database Migration Standards

#### Migration File Structure
```ruby
# frozen_string_literal: true

class CreateModelName < ActiveRecord::Migration[8.0]
  def change
    create_table :model_names, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      
      # Foreign keys with UUID
      t.string :account_id, limit: 36, null: false
      t.index :account_id
      
      # Standard fields
      t.string :name, null: false
      t.string :status, default: 'active'
      
      # Audit fields
      t.timestamps null: false
      
      # Constraints
      t.foreign_key :accounts, type: :string
    end
    
    add_index :model_names, :status
    add_index :model_names, :created_at
  end
end
```

#### Database Reset Commands
```bash
# Complete database reset with worker token update
cd server && rails db:drop db:create db:migrate db:seed

# Update worker token after reset
rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); 
if worker && worker.token.present?
  File.write('worker/.env', File.read('worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\"))
  puts \"✅ Updated worker/.env with system worker token: #{worker.token[0..10]}...\"
else
  puts \"❌ No system worker token found - check seeds.rb\"
end"
```

### 5. Permission System Data Model

#### Permission-Based Access Control
```ruby
class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions
  
  validates :name, presence: true, uniqueness: true
  validates :resource, presence: true
  validates :action, presence: true
  
  # Format: resource.action (e.g., users.create, billing.read)
  def full_name
    "#{resource}.#{action}"
  end
end

class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  
  validates :name, presence: true, uniqueness: true
end

class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  
  validates :user_id, uniqueness: { scope: :role_id }
end
```

### 6. Audit Logging Data Model

#### Audit Log Implementation
```ruby
class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :account
  
  validates :action, presence: true
  validates :resource_type, presence: true
  validates :details, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_resource, ->(type) { where(resource_type: type) }
  
  # JSON storage for flexible audit data
  store_accessor :details, :changes, :metadata, :ip_address
end
```

### 7. Payment & Billing Data Models

#### Payment Model
```ruby
class Payment < ApplicationRecord
  belongs_to :subscription
  belongs_to :payment_method, optional: true
  
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :status, inclusion: { in: %w[pending succeeded failed refunded] }
  
  monetize :amount_cents
  
  scope :succeeded, -> { where(status: 'succeeded') }
  scope :failed, -> { where(status: 'failed') }
end

class PaymentMethod < ApplicationRecord
  belongs_to :account
  has_many :payments, dependent: :destroy
  
  validates :provider, inclusion: { in: %w[stripe paypal] }
  validates :method_type, inclusion: { in: %w[card bank_account paypal] }
  
  scope :active, -> { where(active: true) }
end
```

#### Invoice Model
```ruby
class Invoice < ApplicationRecord
  belongs_to :subscription
  has_many :invoice_line_items, dependent: :destroy
  has_one :payment, dependent: :nullify
  
  validates :invoice_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[draft open paid void] }
  validates :total_cents, presence: true
  
  monetize :total_cents
  
  before_create :generate_invoice_number
  
  private
  
  def generate_invoice_number
    self.invoice_number = "INV-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end
end
```

### 8. Marketplace Data Models

#### App Model
```ruby
class App < ApplicationRecord
  has_many :app_plans, dependent: :destroy
  has_many :plans, through: :app_plans
  has_many :app_subscriptions, dependent: :destroy
  has_many :app_endpoints, dependent: :destroy
  has_many :app_webhooks, dependent: :destroy
  
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[draft published archived] }
  
  scope :published, -> { where(status: 'published') }
end

class AppSubscription < ApplicationRecord
  belongs_to :app
  belongs_to :account
  belongs_to :plan
  
  validates :status, inclusion: { in: %w[active cancelled suspended] }
  
  scope :active, -> { where(status: 'active') }
end
```

### 9. Worker & System Models

#### Worker Model
```ruby
class Worker < ApplicationRecord
  belongs_to :account, optional: true
  has_many :worker_activities, dependent: :destroy
  
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active inactive error] }
  
  before_create :generate_token
  
  private
  
  def generate_token
    self.token = SecureRandom.hex(32)
  end
end

class WorkerActivity < ApplicationRecord
  belongs_to :worker
  
  validates :activity_type, presence: true
  validates :status, inclusion: { in: %w[started completed failed] }
  
  scope :recent, -> { order(created_at: :desc).limit(100) }
end
```

### 10. Query Optimization Standards

#### Index Strategy
```ruby
# Performance-critical indexes
add_index :subscriptions, [:account_id, :status]
add_index :payments, [:subscription_id, :created_at]
add_index :audit_logs, [:account_id, :created_at]
add_index :users, [:account_id, :email]

# Composite indexes for common queries
add_index :user_roles, [:user_id, :role_id], unique: true
add_index :role_permissions, [:role_id, :permission_id], unique: true
```

#### Query Patterns
```ruby
# Use includes for N+1 prevention
accounts = Account.includes(:users, :subscription).active

# Use joins for filtering
users_with_permissions = User.joins(roles: :permissions)
                            .where(permissions: { name: 'users.manage' })

# Use scopes for reusable queries
recent_payments = Payment.joins(:subscription)
                         .where(subscriptions: { status: 'active' })
                         .succeeded
                         .recent
```

## Development Commands

### Database Management
```bash
# Create and migrate
rails db:create db:migrate db:seed

# Reset database with worker token update
rails db:drop db:create db:migrate db:seed && rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); if worker && worker.token.present?; File.write('worker/.env', File.read('worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\")); puts \"✅ Updated worker token\"; end"

# Generate migration
rails generate migration CreateModelName

# Check schema
rails db:schema:dump
```

### Model Validation
```bash
# Console testing
rails console
> Account.create!(name: "Test", status: "active")
> User.joins(roles: :permissions).where(permissions: { name: 'users.read' })
```

## Integration Points

### Data Modeler Coordinates With:
- **Rails Architect**: Database configuration, migration strategy
- **API Developer**: Model serialization, data validation
- **Billing Engine Developer**: Subscription lifecycle data flow
- **Payment Integration Specialist**: Payment and invoice data models
- **Backend Test Engineer**: Model testing, factory definitions
- **Analytics Engineer**: Reporting data models, KPI calculations

## Quick Reference

### Model Generation Template
```ruby
# frozen_string_literal: true

class ModelName < ApplicationRecord
  # Associations
  belongs_to :account
  has_many :related_models, dependent: :destroy
  
  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: %w[active inactive] }
  
  # Scopes
  scope :active, -> { where(status: 'active') }
  
  # Callbacks
  after_create :log_creation
  
  # Methods
  def active?
    status == 'active'
  end
  
  private
  
  def log_creation
    Rails.logger.info "#{self.class.name} created: #{id}"
  end
end
```

### Migration Template
```ruby
# frozen_string_literal: true

class CreateModelNames < ActiveRecord::Migration[8.0]
  def change
    create_table :model_names, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :account_id, limit: 36, null: false
      t.string :name, null: false
      t.string :status, default: 'active'
      t.timestamps null: false
      
      t.index :account_id
      t.index :status
      t.foreign_key :accounts, type: :string
    end
  end
end
```

### Pattern Validation Commands
```bash
# Check model structure compliance (discovered pattern)
find server/app/models -name "*.rb" -exec grep -l "# 1\. Authentication\|# 2\. Concerns\|# 3\. Associations" {} \; | wc -l

# Find models missing frozen_string_literal
grep -L "frozen_string_literal" server/app/models/**/*.rb

# Check UUID primary key usage
grep -r "string :id, limit: 36" server/db/migrate/ | wc -l

# Validate permission method implementation (critical pattern)
grep -r "def has_permission?" server/app/models/
grep -r "def all_permissions" server/app/models/

# Find concern usage in models
grep -r "include.*Security\|include.*Concern" server/app/models/ | wc -l

# Check proper association dependency declarations
grep -r "dependent: :destroy\|dependent: :nullify" server/app/models/ | wc -l

# Validate proper validation patterns
grep -r "format: { with: URI::MailTo::EMAIL_REGEXP }" server/app/models/
grep -r "inclusion: { in: %w\[" server/app/models/ | wc -l
```

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**
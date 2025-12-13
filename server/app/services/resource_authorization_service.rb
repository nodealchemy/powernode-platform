# frozen_string_literal: true

# Resource-level access control service
# Provides Pundit-style policy-based authorization for resources
class ResourceAuthorizationService
  class NotAuthorizedError < StandardError
    attr_reader :query, :record, :policy

    def initialize(options = {})
      @query = options[:query]
      @record = options[:record]
      @policy = options[:policy]

      super(build_message)
    end

    private

    def build_message
      if policy && query
        "not allowed to #{query} this #{policy.class.name.demodulize.underscore.sub(/_policy$/, '')}"
      else
        "not authorized"
      end
    end
  end

  class << self
    # Main authorization method
    # @param user [User] The user to authorize
    # @param record [Object] The resource to authorize access to
    # @param query [Symbol] The action to authorize (e.g., :show?, :update?, :destroy?)
    # @raise [NotAuthorizedError] if not authorized
    def authorize!(user, record, query = nil)
      query ||= default_query
      policy = policy_for(user, record)

      unless policy.public_send(query)
        raise NotAuthorizedError.new(
          query: query,
          record: record,
          policy: policy
        )
      end

      record
    end

    # Check authorization without raising
    def authorized?(user, record, query = nil)
      query ||= default_query
      policy = policy_for(user, record)
      policy.public_send(query)
    rescue StandardError
      false
    end

    # Get policy for a user and record
    def policy_for(user, record)
      klass = policy_class(record)
      klass.new(user, record)
    end

    # Scope records based on policy
    def policy_scope(user, scope)
      policy_scope_class = "#{scope.klass.name}Policy::Scope"
      scope_class = policy_scope_class.constantize
      scope_class.new(user, scope).resolve
    rescue NameError
      # Fall back to default scope if no specific scope defined
      DefaultPolicy::Scope.new(user, scope).resolve
    end

    private

    def policy_class(record)
      klass = if record.is_a?(Class)
                record
      elsif record.is_a?(Symbol) || record.is_a?(String)
                record.to_s.classify.constantize
      else
                record.class
      end

      "#{klass.name}Policy".constantize
    rescue NameError
      DefaultPolicy
    end

    def default_query
      :show?
    end
  end
end

# Base policy class - all policies should inherit from this
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Default to denying access
  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # Helper methods for common checks
  def admin?
    user&.has_permission?("system.admin")
  end

  def account_admin?
    user&.has_permission?("accounts.manage")
  end

  def same_account?
    return false unless user && record_account
    user.account_id == record_account.id
  end

  def owner?
    return false unless user && record
    record.respond_to?(:user_id) && record.user_id == user.id
  end

  # Base scope class
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in your scope class"
    end

    private

    def admin?
      user&.has_permission?("system.admin")
    end
  end

  private

  def record_account
    if record.respond_to?(:account)
      record.account
    elsif record.respond_to?(:account_id)
      Account.find_by(id: record.account_id)
    end
  end
end

# Default policy for resources without specific policies
class DefaultPolicy < ApplicationPolicy
  def index?
    admin? || same_account?
  end

  def show?
    admin? || (same_account? && (owner? || has_read_permission?))
  end

  def create?
    admin? || (same_account? && has_create_permission?)
  end

  def update?
    admin? || (same_account? && (owner? || has_update_permission?))
  end

  def destroy?
    admin? || (same_account? && (owner? || has_delete_permission?))
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end

  private

  def resource_name
    record.class.name.underscore.pluralize
  end

  def has_read_permission?
    user&.has_permission?("#{resource_name}.read")
  end

  def has_create_permission?
    user&.has_permission?("#{resource_name}.create")
  end

  def has_update_permission?
    user&.has_permission?("#{resource_name}.update")
  end

  def has_delete_permission?
    user&.has_permission?("#{resource_name}.delete")
  end
end

# Example resource-specific policies
class UserPolicy < ApplicationPolicy
  def index?
    admin? || user&.has_permission?("users.read")
  end

  def show?
    admin? || owner? || (same_account? && user&.has_permission?("users.read"))
  end

  def create?
    admin? || (same_account? && user&.has_permission?("users.create"))
  end

  def update?
    admin? || owner? || (same_account? && user&.has_permission?("users.update"))
  end

  def destroy?
    return false if owner? # Cannot delete self
    admin? || (same_account? && user&.has_permission?("users.delete"))
  end

  def manage_roles?
    admin? || user&.has_permission?("users.manage")
  end

  def impersonate?
    admin? && !owner? # Can only impersonate others, not self
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end

  private

  def owner?
    user && record && user.id == record.id
  end

  def same_account?
    user && record && user.account_id == record.account_id
  end
end

class SubscriptionPolicy < ApplicationPolicy
  def index?
    admin? || same_account?
  end

  def show?
    admin? || same_account?
  end

  def create?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  def update?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  def destroy?
    admin? # Only admins can delete subscriptions
  end

  def cancel?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  def pause?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  def resume?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end
end

class PaymentPolicy < ApplicationPolicy
  def index?
    admin? || (same_account? && user&.has_permission?("billing.read"))
  end

  def show?
    admin? || (same_account? && user&.has_permission?("billing.read"))
  end

  def create?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  def refund?
    admin? || (same_account? && user&.has_permission?("payments.refund"))
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.joins(:subscription).where(subscriptions: { account_id: user.account_id })
      else
        scope.none
      end
    end
  end
end

class InvoicePolicy < ApplicationPolicy
  def index?
    admin? || (same_account? && user&.has_permission?("billing.read"))
  end

  def show?
    admin? || (same_account? && user&.has_permission?("billing.read"))
  end

  def download?
    show?
  end

  def send_reminder?
    admin? || (same_account? && user&.has_permission?("billing.manage"))
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end
end

class AuditLogPolicy < ApplicationPolicy
  def index?
    admin? || user&.has_permission?("audit_logs.read")
  end

  def show?
    admin? || (same_account? && user&.has_permission?("audit_logs.read"))
  end

  def export?
    admin? || user&.has_permission?("audit_logs.export")
  end

  # Audit logs are immutable - no create, update, destroy
  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user&.has_permission?("audit_logs.read")
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end
end

class FileObjectPolicy < ApplicationPolicy
  def index?
    admin? || (same_account? && user&.has_permission?("files.read"))
  end

  def show?
    admin? || owner? || (same_account? && user&.has_permission?("files.read"))
  end

  def download?
    show?
  end

  def create?
    admin? || (same_account? && user&.has_permission?("files.upload"))
  end

  def update?
    admin? || owner? || (same_account? && user&.has_permission?("files.update"))
  end

  def destroy?
    admin? || owner? || (same_account? && user&.has_permission?("files.delete"))
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(account_id: user.account_id)
      else
        scope.none
      end
    end
  end
end

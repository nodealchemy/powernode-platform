# frozen_string_literal: true

module System
  module Base
    extend ActiveSupport::Concern

    included do
      # All System models belong to an account
      belongs_to :account

      # Default scope to current account (can be overridden)
      scope :for_account, ->(account) { where(account: account) }

      # Common scopes
      scope :enabled, -> { where(enabled: true) }
      scope :disabled, -> { where(enabled: false) }
      scope :public_access, -> { where(public: true) }
      scope :private_access, -> { where(public: false) }

      # Ordered by name for listings
      scope :ordered, -> { order(:name) }
      scope :recently_created, -> { order(created_at: :desc) }
      scope :recently_updated, -> { order(updated_at: :desc) }
    end

    class_methods do
      # Override table name to use system_ prefix
      def table_name
        "system_#{super.sub(/^system_/, '')}"
      end
    end

    # Check if the resource is enabled
    def enabled?
      enabled == true
    end

    # Check if the resource is publicly accessible
    def public?
      self[:public] == true
    end

    # Check if the resource is accessible by the given account
    def accessible_by?(account)
      return true if public?
      return false unless account

      self.account_id == account.id
    end
  end
end

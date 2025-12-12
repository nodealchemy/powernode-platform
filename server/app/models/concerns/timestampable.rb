# frozen_string_literal: true

# Concern for ensuring proper timestamp handling across all models
module Timestampable
  extend ActiveSupport::Concern

  included do
    # Validate presence of timestamps if the columns exist
    validates :created_at, presence: true, if: :has_created_at?
    validates :updated_at, presence: true, if: :has_updated_at?

    # Ensure timestamps are set before validation
    before_validation :ensure_timestamps, on: :create

    # Update updated_at on every save (in case touched wasn't called)
    before_save :update_timestamp, if: :has_updated_at?
  end

  private

  def has_created_at?
    respond_to?(:created_at) && has_attribute?(:created_at)
  end

  def has_updated_at?
    respond_to?(:updated_at) && has_attribute?(:updated_at)
  end

  def ensure_timestamps
    if has_created_at? && created_at.blank?
      self.created_at = Time.current
    end

    if has_updated_at? && updated_at.blank?
      self.updated_at = Time.current
    end
  end

  def update_timestamp
    # Only update if it hasn't been explicitly set or if it's stale
    if updated_at.blank? || (updated_at <= created_at && persisted?)
      self.updated_at = Time.current
    end
  end
end

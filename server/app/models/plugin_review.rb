# frozen_string_literal: true

# Plugin Review Model
# User reviews and ratings for plugins
class PluginReview < ApplicationRecord
  belongs_to :plugin
  belongs_to :account
  belongs_to :user

  # Validations
  validates :rating, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 5
  }
  validates :plugin_id, uniqueness: { scope: :account_id }

  # Scopes
  scope :verified, -> { where(is_verified_purchase: true) }
  scope :by_rating, ->(rating) { where(rating: rating) }
  scope :positive, -> { where("rating >= ?", 4) }
  scope :negative, -> { where("rating <= ?", 2) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :update_plugin_statistics
  after_update :update_plugin_statistics, if: :saved_change_to_rating?
  after_destroy :update_plugin_statistics

  private

  def update_plugin_statistics
    plugin.update_statistics!
  end
end

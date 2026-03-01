# frozen_string_literal: true

module Ai
  class AbTest < ApplicationRecord
    self.table_name = "ai_ab_tests"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    # Validations
    validates :test_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: %w[draft running paused completed cancelled] }
    validates :target_type, presence: true, inclusion: { in: %w[workflow agent prompt model provider] }
    validates :target_id, presence: true

    # Scopes
    scope :draft, -> { where(status: "draft") }
    scope :running, -> { where(status: "running") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :for_target, ->(type, id) { where(target_type: type, target_id: id) }
    scope :active, -> { where(status: %w[running paused]) }

    # Callbacks
    before_validation :set_test_id, on: :create

    # Methods
    def draft?
      status == "draft"
    end

    def running?
      status == "running"
    end

    def paused?
      status == "paused"
    end

    def completed?
      status == "completed"
    end

    def start!
      return false unless draft? || paused?
      return false if variants.blank? || variants.length < 2

      update!(status: "running", started_at: Time.current)
    end

    def pause!
      update!(status: "paused") if running?
    end

    def resume!
      update!(status: "running") if paused?
    end

    def complete!
      winner = determine_winner
      update!(
        status: "completed",
        ended_at: Time.current,
        winning_variant: winner,
        statistical_significance: calculate_significance
      )
    end

    def cancel!
      update!(status: "cancelled", ended_at: Time.current)
    end

    def assign_variant(identifier = nil)
      return nil unless running?
      return nil if variants.blank?

      # Deterministic assignment based on identifier or random
      if identifier.present?
        hash = Digest::MD5.hexdigest("#{test_id}-#{identifier}").to_i(16)
        index = hash % variants.length
      else
        index = select_weighted_variant
      end

      variants[index]
    end

    def record_impression!(variant_id)
      return unless running?

      increment!(:total_impressions)
      update_variant_stat(variant_id, :impressions, 1)
    end

    def record_conversion!(variant_id, value = 1)
      return unless running?

      increment!(:total_conversions)
      update_variant_stat(variant_id, :conversions, value)
    end

    def variant_results
      return {} if results.blank?

      variants.each_with_object({}) do |variant, hash|
        variant_id = variant["id"]
        stats = results[variant_id] || { impressions: 0, conversions: 0 }
        impressions = stats["impressions"] || 0
        conversions = stats["conversions"] || 0

        hash[variant_id] = {
          name: variant["name"],
          impressions: impressions,
          conversions: conversions,
          conversion_rate: impressions > 0 ? (conversions.to_f / impressions * 100).round(2) : 0
        }
      end
    end

    def has_sufficient_data?
      total_impressions >= minimum_sample_size
    end

    def minimum_sample_size
      # Minimum sample size for statistical significance
      (variants.length * 100)
    end

    private

    def set_test_id
      self.test_id ||= SecureRandom.uuid
    end

    def select_weighted_variant
      return 0 if traffic_allocation.blank?

      r = rand
      cumulative = 0

      variants.each_with_index do |variant, index|
        allocation = traffic_allocation[variant["id"]] || (1.0 / variants.length)
        cumulative += allocation
        return index if r <= cumulative
      end

      0
    end

    def update_variant_stat(variant_id, stat, value)
      current_results = results || {}
      current_results[variant_id] ||= { "impressions" => 0, "conversions" => 0 }
      current_results[variant_id][stat.to_s] = (current_results[variant_id][stat.to_s] || 0) + value
      update!(results: current_results)
    end

    def determine_winner
      return nil unless has_sufficient_data?

      best_variant = nil
      best_rate = 0

      variant_results.each do |variant_id, stats|
        if stats[:conversion_rate] > best_rate
          best_rate = stats[:conversion_rate]
          best_variant = variant_id
        end
      end

      best_variant
    end

    def calculate_significance
      return nil unless has_sufficient_data?
      return nil if variants.length != 2

      # Simple chi-squared test for 2 variants
      results_data = variant_results.values
      return nil if results_data.any? { |r| r[:impressions] < 30 }

      # Calculate expected vs observed
      total_impressions = results_data.sum { |r| r[:impressions] }
      total_conversions = results_data.sum { |r| r[:conversions] }
      expected_rate = total_conversions.to_f / total_impressions

      chi_squared = results_data.sum do |r|
        expected = r[:impressions] * expected_rate
        next 0 if expected.zero?

        ((r[:conversions] - expected) ** 2) / expected
      end

      # Convert chi-squared to approximate p-value (simplified)
      # For df=1, chi-squared > 3.84 is p < 0.05
      significance = 1 - Math.exp(-chi_squared / 2)
      (significance * 100).round(1)
    end
  end
end

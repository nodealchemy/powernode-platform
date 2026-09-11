# frozen_string_literal: true

module Ai
  # One row per PAID judge call (D5 review F-D5-1). The daily cap counts these,
  # not Ai::EvaluationResult rows: a degraded verdict is a provider round trip
  # that writes no result row, so counting results let degraded calls through
  # the cap uncounted.
  #
  # Written by Ai::Learning::EvaluationService BEFORE the judge is called, so
  # there is no call without a row, then closed with what the call produced.
  # A row left `pending` is a call that raised mid-flight, and it still counts.
  class EvaluationAttempt < ApplicationRecord
    OUTCOMES = %w[pending evaluated not_measured].freeze

    belongs_to :account

    validates :execution_id, presence: true
    validates :outcome, inclusion: { in: OUTCOMES }

    scope :since, ->(time) { where("created_at >= ?", time) }
  end
end

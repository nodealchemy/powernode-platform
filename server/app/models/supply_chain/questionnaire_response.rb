# frozen_string_literal: true

module SupplyChain
  class QuestionnaireResponse < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_questionnaire_responses"

    # ============================================
    # Constants
    # ============================================
    STATUSES = %w[pending in_progress submitted reviewed expired].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :vendor, class_name: "SupplyChain::Vendor"
    belongs_to :template, class_name: "SupplyChain::QuestionnaireTemplate"
    belongs_to :account
    belongs_to :risk_assessment, class_name: "SupplyChain::RiskAssessment", optional: true
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :access_token, presence: true, uniqueness: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :submitted, -> { where(status: "submitted") }
    scope :reviewed, -> { where(status: "reviewed") }
    scope :expired, -> { where(status: "expired") }
    scope :awaiting_response, -> { where(status: %w[pending in_progress]) }
    scope :needs_review, -> { where(status: "submitted") }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expiring_soon, ->(days = 7) { where("expires_at <= ?", days.days.from_now) }
    scope :for_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_access_token, on: :create
    before_save :sanitize_jsonb_fields
    after_save :check_expiration

    # ============================================
    # Instance Methods
    # ============================================
    def pending?
      status == "pending"
    end

    def in_progress?
      status == "in_progress"
    end

    def submitted?
      status == "submitted"
    end

    def reviewed?
      status == "reviewed"
    end

    def expired?
      status == "expired" || (expires_at.present? && expires_at < Time.current)
    end

    def awaiting_response?
      status.in?(%w[pending in_progress])
    end

    def can_edit?
      awaiting_response? && !expired?
    end

    def completion_percentage
      return 0 if template.question_count == 0

      answered_count = responses.keys.length
      ((answered_count.to_f / template.question_count) * 100).round(1)
    end

    def response_count
      responses.keys.length
    end

    def unanswered_questions
      answered_ids = responses.keys.map(&:to_s)
      template.questions.reject { |q| answered_ids.include?(q["id"]) }
    end

    def required_unanswered
      unanswered_questions.select { |q| q["required"] }
    end

    def all_required_answered?
      required_unanswered.empty?
    end

    def get_response(question_id)
      responses[question_id.to_s]
    end

    def set_response(question_id, answer)
      self.responses = responses.merge(question_id.to_s => {
        answer: answer,
        answered_at: Time.current.iso8601
      })

      if pending?
        update!(status: "in_progress", started_at: Time.current)
      else
        save!
      end
    end

    def send_to_vendor!
      update!(sent_at: Time.current)
      # Trigger notification to vendor
    end

    def start!
      update!(status: "in_progress", started_at: Time.current)
    end

    def submit!
      return false unless all_required_answered?

      calculate_scores
      update!(status: "submitted", submitted_at: Time.current)
      true
    end

    def review!(user, notes: nil)
      update!(
        status: "reviewed",
        reviewed_by: user,
        reviewed_at: Time.current,
        review_notes: notes
      )
    end

    def approve!(approved_by:, notes: nil)
      update!(
        status: "reviewed",
        reviewed_by: approved_by,
        reviewed_at: Time.current,
        review_notes: notes
      )
    end

    def reject!(rejected_by:, reason:)
      update!(
        status: "reviewed",
        reviewed_by: rejected_by,
        reviewed_at: Time.current,
        review_notes: reason,
        metadata: metadata.merge("feedback" => reason)
      )
    end

    def request_changes!(requested_by:, feedback:)
      update!(
        status: "in_progress",
        metadata: self.metadata.merge("feedback" => feedback)
      )
    end

    def feedback
      metadata["feedback"]
    end

    def calculate_scores!
      calculate_scores
      save!
    end

    def expire!
      update!(status: "expired")
    end

    def extend_deadline!(days)
      new_expiry = (expires_at || Time.current) + days.days
      update!(expires_at: new_expiry)
    end

    def days_until_expiry
      return nil unless expires_at.present?

      (expires_at.to_date - Date.current).to_i
    end

    def public_url
      # Generate a public URL for vendor to access
      # This would be configured based on your application URL
      "/questionnaires/respond/#{access_token}"
    end

    def summary
      {
        id: id,
        vendor_id: vendor_id,
        vendor_name: vendor.name,
        template_id: template_id,
        template_name: template.name,
        template_type: template.template_type,
        status: status,
        completion_percentage: completion_percentage,
        response_count: response_count,
        total_questions: template.question_count,
        overall_score: overall_score,
        sent_at: sent_at,
        started_at: started_at,
        submitted_at: submitted_at,
        reviewed_at: reviewed_at,
        expires_at: expires_at,
        days_until_expiry: days_until_expiry,
        created_at: created_at
      }
    end

    def detailed_response
      {
        summary: summary,
        template: template.full_template,
        responses: responses,
        section_scores: section_scores,
        review_notes: review_notes
      }
    end

    private

    def generate_access_token
      return if access_token.present?

      self.access_token = SecureRandom.urlsafe_base64(32)
    end

    def sanitize_jsonb_fields
      self.responses ||= {}
      self.section_scores ||= {}
      self.metadata ||= {}
    end

    def check_expiration
      return unless expires_at.present? && expires_at < Time.current && !expired?

      expire!
    end

    def calculate_scores
      return if template.sections.blank?

      section_totals = {}
      section_counts = {}

      template.sections.each do |section|
        section_totals[section["id"]] = 0
        section_counts[section["id"]] = 0
      end

      template.questions.each do |question|
        response = responses[question["id"]]
        next unless response.present?

        section_id = question["section_id"]
        score = calculate_question_score(question, response)

        if score.present?
          section_totals[section_id] += score
          section_counts[section_id] += 1
        end
      end

      # Calculate section averages
      calculated_scores = {}
      template.sections.each do |section|
        if section_counts[section["id"]] > 0
          calculated_scores[section["id"]] = (section_totals[section["id"]].to_f / section_counts[section["id"]]).round(2)
        else
          calculated_scores[section["id"]] = 0
        end
      end

      self.section_scores = calculated_scores

      # Calculate weighted overall score
      total_weight = template.sections.sum { |s| s["weight"] || 1.0 }
      weighted_sum = template.sections.sum do |s|
        weight = s["weight"] || 1.0
        (calculated_scores[s["id"]] || 0) * weight
      end

      self.overall_score = total_weight > 0 ? (weighted_sum / total_weight).round(2) : 0
    end

    def calculate_question_score(question, response)
      case question["type"]
      when "yes_no"
        response["answer"] == "yes" ? 100 : 0
      when "scale"
        max = question["max"] || 5
        ((response["answer"].to_i.to_f / max) * 100).round(2)
      when "choice"
        # Score based on predefined answer weights
        weight = question.dig("choices", response["answer"], "weight") || 0
        weight * 100
      else
        # Text responses don't contribute to score automatically
        nil
      end
    end
  end
end

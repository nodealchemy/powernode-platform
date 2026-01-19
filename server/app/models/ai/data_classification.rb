# frozen_string_literal: true

module Ai
  class DataClassification < ApplicationRecord
    self.table_name = "ai_data_classifications"

    # Associations
    belongs_to :account
    belongs_to :classified_by, class_name: "User", optional: true

    has_many :detections, class_name: "Ai::DataDetection", foreign_key: :classification_id, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :classification_level, presence: true, inclusion: {
      in: %w[public internal confidential restricted pii phi pci]
    }

    # Scopes
    scope :system, -> { where(is_system: true) }
    scope :custom, -> { where(is_system: false) }
    scope :by_level, ->(level) { where(classification_level: level) }
    scope :requiring_encryption, -> { where(requires_encryption: true) }
    scope :requiring_masking, -> { where(requires_masking: true) }
    scope :ordered_by_sensitivity, -> {
      order(Arel.sql("CASE classification_level
        WHEN 'pci' THEN 1
        WHEN 'phi' THEN 2
        WHEN 'pii' THEN 3
        WHEN 'restricted' THEN 4
        WHEN 'confidential' THEN 5
        WHEN 'internal' THEN 6
        WHEN 'public' THEN 7
        ELSE 8 END"))
    }

    # Methods
    def sensitive?
      %w[pii phi pci restricted].include?(classification_level)
    end

    def requires_special_handling?
      requires_encryption || requires_masking || requires_audit
    end

    def detect_in_text(text)
      return [] if detection_patterns.blank? || text.blank?

      matches = []
      detection_patterns.each do |pattern_config|
        pattern = pattern_config["pattern"]
        name = pattern_config["name"] || self.name

        begin
          regex = Regexp.new(pattern, Regexp::IGNORECASE)
          text.scan(regex) do |match|
            matches << {
              classification: self.name,
              level: classification_level,
              pattern_name: name,
              match: match.is_a?(Array) ? match.first : match,
              position: Regexp.last_match.begin(0)
            }
          end
        rescue RegexpError => e
          Rails.logger.warn "Invalid detection pattern '#{pattern}': #{e.message}"
        end
      end
      matches
    end

    def record_detection!(source_type:, source_id:, field_path: nil, original: nil, action: "logged", confidence: nil)
      masked = requires_masking ? mask_value(original) : nil

      detections.create!(
        account: account,
        detection_id: SecureRandom.uuid,
        source_type: source_type,
        source_id: source_id,
        field_path: field_path,
        action_taken: action,
        original_snippet: original,
        masked_snippet: masked,
        confidence_score: confidence
      )

      increment!(:detection_count)
    end

    def mask_value(value)
      return nil if value.blank?

      case classification_level
      when "pii", "phi"
        # Show first and last character only
        value.length > 2 ? "#{value[0]}#{'*' * (value.length - 2)}#{value[-1]}" : "*" * value.length
      when "pci"
        # Show last 4 digits only (for card numbers)
        value.length > 4 ? "*" * (value.length - 4) + value[-4..] : "*" * value.length
      else
        "*" * [value.length, 10].min
      end
    end

    def retention_period_days
      retention_policy["days"]&.to_i
    end
  end
end

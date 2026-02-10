# frozen_string_literal: true

module Ai
  module Security
    class PiiRedactionService
      # OWASP Agentic Security Index coverage:
      #   ASI04 - Sensitive Information Disclosure (PII/PHI detection and redaction)
      #   ASI09 - Data Leakage (output scanning, policy-based gating)

      PATTERNS = {
        email: {
          regex: /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/,
          confidence: 0.95,
          classification: "pii"
        },
        phone_us: {
          regex: /\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/,
          confidence: 0.85,
          classification: "pii"
        },
        phone_intl: {
          regex: /\b\+\d{1,3}[-.\s]?\d{1,4}[-.\s]?\d{3,4}[-.\s]?\d{3,4}\b/,
          confidence: 0.80,
          classification: "pii"
        },
        ssn: {
          regex: /\b\d{3}-\d{2}-\d{4}\b/,
          confidence: 0.95,
          classification: "pii"
        },
        credit_card: {
          regex: /\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/,
          confidence: 0.90,
          classification: "pci"
        },
        ip_address_v4: {
          regex: /\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b/,
          confidence: 0.70,
          classification: "internal"
        },
        api_key_generic: {
          regex: /\b(?:api[_-]?key|apikey|access[_-]?key)\s*[:=]\s*['"]?([A-Za-z0-9\-_]{20,})/i,
          confidence: 0.90,
          classification: "restricted"
        },
        jwt_token: {
          regex: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/,
          confidence: 0.95,
          classification: "restricted"
        },
        password_in_url: {
          regex: %r{(?:password|passwd|pwd)\s*[:=]\s*\S+}i,
          confidence: 0.85,
          classification: "restricted"
        },
        aws_access_key: {
          regex: /\b(?:AKIA|ABIA|ACCA|ASIA)[A-Z0-9]{16}\b/,
          confidence: 0.95,
          classification: "restricted"
        },
        aws_secret_key: {
          regex: /\b[A-Za-z0-9\/+=]{40}\b/,
          confidence: 0.50,
          classification: "restricted"
        },
        date_of_birth: {
          regex: /\b(?:0[1-9]|1[0-2])\/(?:0[1-9]|[12]\d|3[01])\/(?:19|20)\d{2}\b/,
          confidence: 0.70,
          classification: "pii"
        },
        medical_record: {
          regex: /\b(?:MRN|medical\s+record)\s*[:=#]?\s*\d{6,}\b/i,
          confidence: 0.85,
          classification: "phi"
        },
        private_key_header: {
          regex: /-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----/,
          confidence: 0.99,
          classification: "restricted"
        },
        bearer_token: {
          regex: /\bBearer\s+[A-Za-z0-9\-_\.]{20,}\b/i,
          confidence: 0.90,
          classification: "restricted"
        }
      }.freeze

      REDACTION_PLACEHOLDER = "[REDACTED:%{type}]"

      # Classification levels ordered by sensitivity (most sensitive first)
      SENSITIVITY_ORDER = %w[pci phi pii restricted confidential internal public].freeze

      # Minimum classification level that requires redaction per output context
      REDACTION_THRESHOLDS = {
        "public"       => "pii",
        "internal"     => "pii",
        "confidential" => "pci",
        "restricted"   => "pci",
        "pii"          => nil,
        "phi"          => nil,
        "pci"          => nil
      }.freeze

      def initialize(account:)
        @account = account
      end

      # Scan text and return detections without modifying the text.
      # Returns { detections: [...], pii_found: Boolean }
      def scan(text:, context: {})
        return { detections: [], pii_found: false } if text.blank?

        detections = run_pattern_scan(text)
        detections.concat(run_classification_scan(text))
        detections = deduplicate_detections(detections)

        { detections: detections, pii_found: detections.any? }
      end

      # Scan and redact PII, returning cleaned text and detection metadata.
      # Returns { redacted_text: String, detections_count: Integer, types_found: [...] }
      def redact(text:, context: {}, log: true)
        return { redacted_text: text, detections_count: 0, types_found: [] } if text.blank?

        detections = run_pattern_scan(text)
        detections.concat(run_classification_scan(text))
        detections = deduplicate_detections(detections)

        redacted_text = apply_redactions(text, detections)

        if log && detections.any?
          log_detections(detections, context, "masked")
        end

        {
          redacted_text: redacted_text,
          detections_count: detections.size,
          types_found: detections.map { |d| d[:type] }.uniq
        }
      end

      # Scan and redact based on data classification policies.
      # Only redacts PII types that exceed the classification level threshold.
      # Returns { redacted_text: String, policy_applied: String|nil, detections: [...] }
      def apply_policy(text:, classification_level: "internal", context: {})
        return { redacted_text: text, policy_applied: nil, detections: [] } if text.blank?

        detections = run_pattern_scan(text)
        detections.concat(run_classification_scan(text))
        detections = deduplicate_detections(detections)

        # Filter detections to only those exceeding the classification threshold
        threshold_level = REDACTION_THRESHOLDS[classification_level]
        filtered = if threshold_level
                     threshold_idx = SENSITIVITY_ORDER.index(threshold_level) || SENSITIVITY_ORDER.size
                     detections.select do |d|
                       det_idx = SENSITIVITY_ORDER.index(d[:classification]) || SENSITIVITY_ORDER.size
                       det_idx <= threshold_idx
                     end
                   else
                     detections
                   end

        redacted_text = apply_redactions(text, filtered)

        if filtered.any?
          log_detections(filtered, context.merge(classification_level: classification_level), "masked")
          record_policy_enforcement(filtered, classification_level, context)
        end

        {
          redacted_text: redacted_text,
          policy_applied: classification_level,
          detections: filtered
        }
      end

      # Batch scan multiple texts.
      # Returns Array of scan results keyed by index.
      def batch_scan(texts:, context: {})
        return [] if texts.blank?

        texts.map.with_index do |text, idx|
          result = scan(text: text, context: context.merge(batch_index: idx))
          result.merge(index: idx)
        end
      end

      # Check if text is safe to output (no PII above confidence threshold).
      # Returns Boolean.
      def safe_to_output?(text:, max_confidence: 0.7)
        return true if text.blank?

        detections = run_pattern_scan(text)
        detections.concat(run_classification_scan(text))
        detections = deduplicate_detections(detections)

        high_confidence = detections.select { |d| d[:confidence] >= max_confidence }

        if high_confidence.any?
          Rails.logger.warn "[PiiRedaction] Unsafe output detected: #{high_confidence.size} PII item(s) above confidence #{max_confidence}"

          if defined?(PowernodeEnterprise::Engine)
            Ai::ComplianceAuditEntry.log!(
              account: @account,
              action_type: "pii_output_gate",
              resource_type: "AgentOutput",
              resource_id: SecureRandom.uuid,
              outcome: "blocked",
              description: "Output blocked: #{high_confidence.size} PII detection(s) above confidence #{max_confidence}",
              context: {
                types: high_confidence.map { |d| d[:type] }.uniq,
                max_confidence_found: high_confidence.map { |d| d[:confidence] }.max
              }
            )
          end

          false
        else
          true
        end
      rescue StandardError => e
        Rails.logger.error "[PiiRedaction] safe_to_output? error: #{e.message}"
        false
      end

      private

      # Run built-in regex pattern scanning against the text.
      def run_pattern_scan(text)
        detections = []

        PATTERNS.each do |type, config|
          text.scan(config[:regex]) do
            match_data = Regexp.last_match
            matched_text = match_data[0]

            # Skip very short matches that are likely false positives
            next if matched_text.length < 4
            # Skip AWS secret key pattern unless it looks like a real key
            next if type == :aws_secret_key && !plausible_aws_secret?(matched_text)

            detections << {
              type: type.to_s,
              match: matched_text,
              position: match_data.begin(0),
              length: matched_text.length,
              confidence: config[:confidence],
              classification: config[:classification],
              source: "builtin_pattern"
            }
          end
        end

        detections
      end

      # Run account-specific DataClassification pattern scanning.
      def run_classification_scan(text)
        detections = []
        return detections unless defined?(PowernodeEnterprise::Engine)

        classifications = Ai::DataClassification.where(account: @account)

        classifications.each do |classification|
          matches = classification.detect_in_text(text)
          matches.each do |match|
            detections << {
              type: "custom_#{classification.name.parameterize(separator: '_')}",
              match: match[:match],
              position: match[:position],
              length: match[:match].to_s.length,
              confidence: 0.80,
              classification: classification.classification_level,
              source: "data_classification",
              classification_id: classification.id
            }
          end
        end

        detections
      end

      # Remove overlapping detections, keeping the higher-confidence one.
      def deduplicate_detections(detections)
        return detections if detections.size <= 1

        sorted = detections.sort_by { |d| [d[:position] || 0, -(d[:confidence] || 0)] }
        result = []

        sorted.each do |detection|
          overlapping = result.find do |existing|
            next false unless detection[:position] && existing[:position]

            existing_end = existing[:position] + (existing[:length] || 0)
            detection_end = detection[:position] + (detection[:length] || 0)

            detection[:position] < existing_end && detection_end > existing[:position]
          end

          if overlapping
            # Keep the one with higher confidence
            if detection[:confidence] > overlapping[:confidence]
              result.delete(overlapping)
              result << detection
            end
          else
            result << detection
          end
        end

        result
      end

      # Apply redactions to text by replacing detected matches.
      # Process from end to start so positions remain valid.
      def apply_redactions(text, detections)
        return text if detections.empty?

        result = text.dup
        sorted = detections.select { |d| d[:position] }.sort_by { |d| -d[:position] }

        sorted.each do |detection|
          placeholder = format(REDACTION_PLACEHOLDER, type: detection[:type].to_s.upcase)
          start_pos = detection[:position]
          end_pos = start_pos + (detection[:length] || detection[:match].to_s.length)

          next if start_pos < 0 || end_pos > result.length

          result[start_pos...end_pos] = placeholder
        end

        # Handle detections without position (from classification scan fallback)
        no_position = detections.reject { |d| d[:position] }
        no_position.each do |detection|
          next if detection[:match].blank?

          placeholder = format(REDACTION_PLACEHOLDER, type: detection[:type].to_s.upcase)
          result = result.gsub(detection[:match], placeholder)
        end

        result
      end

      # AWS secret keys are 40 chars base64-ish. Filter out common false positives.
      def plausible_aws_secret?(value)
        return false if value.length != 40
        return false if value =~ /\A[0-9]+\z/
        return false if value =~ /\A[a-z]+\z/i

        # Must have a mix of character classes
        has_upper = value =~ /[A-Z]/
        has_lower = value =~ /[a-z]/
        has_digit = value =~ /[0-9]/

        [has_upper, has_lower, has_digit].count(&:itself) >= 2
      end

      # Log detections to Ai::DataDetection via DataClassification.
      def log_detections(detections, context, action)
        return unless defined?(PowernodeEnterprise::Engine)

        detections.each do |detection|
          classification = find_or_default_classification(detection[:classification])
          next unless classification

          classification.record_detection!(
            source_type: context[:source_type] || "AgentIO",
            source_id: context[:source_id] || SecureRandom.uuid,
            field_path: context[:field_path],
            original: detection[:match].to_s.truncate(200),
            action: action,
            confidence: detection[:confidence]
          )
        rescue StandardError => e
          Rails.logger.error "[PiiRedaction] Failed to log detection (#{detection[:type]}): #{e.message}"
        end
      rescue StandardError => e
        Rails.logger.error "[PiiRedaction] Failed to log detections batch: #{e.message}"
      end

      # Record a policy enforcement event via CompliancePolicy violations.
      def record_policy_enforcement(detections, classification_level, context)
        return unless defined?(PowernodeEnterprise::Engine)

        policy = Ai::CompliancePolicy.where(account: @account)
                                     .active
                                     .by_type("output_filter")
                                     .first
        return unless policy

        types_found = detections.map { |d| d[:type] }.uniq
        max_confidence = detections.map { |d| d[:confidence] }.max || 0.0

        severity = if detections.any? { |d| %w[pci phi].include?(d[:classification]) }
                     "critical"
                   elsif detections.any? { |d| d[:classification] == "pii" }
                     "high"
                   elsif detections.any? { |d| d[:classification] == "restricted" }
                     "high"
                   else
                     "medium"
                   end

        policy.record_violation!(
          source_type: context[:source_type] || "AgentIO",
          source_id: context[:source_id] || SecureRandom.uuid,
          description: "PII detected and redacted: #{types_found.join(', ')} (classification: #{classification_level})",
          context: {
            types_found: types_found,
            detection_count: detections.size,
            classification_level: classification_level,
            max_confidence: max_confidence
          },
          severity: severity
        )

        Ai::ComplianceAuditEntry.log!(
          account: @account,
          action_type: "pii_redaction_applied",
          resource_type: context[:source_type] || "AgentIO",
          resource_id: context[:source_id],
          outcome: "warning",
          description: "Redacted #{detections.size} PII item(s): #{types_found.join(', ')}",
          context: {
            classification_level: classification_level,
            types_found: types_found,
            detection_count: detections.size
          }
        )
      rescue StandardError => e
        Rails.logger.error "[PiiRedaction] Failed to record policy enforcement: #{e.message}"
      end

      # Find a DataClassification for the given level, falling back to a default.
      def find_or_default_classification(level)
        return nil unless defined?(PowernodeEnterprise::Engine)

        Ai::DataClassification.where(account: @account)
                              .by_level(level)
                              .first ||
          Ai::DataClassification.where(account: @account)
                                .by_level("internal")
                                .first
      end
    end
  end
end

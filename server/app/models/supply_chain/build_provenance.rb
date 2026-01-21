# frozen_string_literal: true

module SupplyChain
  class BuildProvenance < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_build_provenances"

    # ============================================
    # Associations
    # ============================================
    belongs_to :attestation, class_name: "SupplyChain::Attestation"
    belongs_to :account

    # ============================================
    # Validations
    # ============================================
    validates :builder_id, presence: true
    validates :attestation_id, uniqueness: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_builder, ->(builder_id) { where(builder_id: builder_id) }
    scope :reproducible, -> { where(reproducible: true) }
    scope :verified_reproducible, -> { reproducible.where.not(reproducibility_verified_at: nil) }
    scope :by_source_repo, ->(repo) { where(source_repository: repo) }
    scope :by_source_commit, ->(commit) { where(source_commit: commit) }
    scope :recent, -> { order(build_started_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    after_save :calculate_duration, if: :should_calculate_duration?

    # ============================================
    # Instance Methods
    # ============================================
    def reproducible?
      reproducible
    end

    def verified_reproducible?
      reproducible? && reproducibility_verified_at.present?
    end

    def build_completed?
      build_finished_at.present?
    end

    def build_in_progress?
      build_started_at.present? && build_finished_at.nil?
    end

    def formatted_duration
      return nil unless build_duration_ms.present?

      seconds = build_duration_ms / 1000
      minutes = seconds / 60
      hours = minutes / 60

      if hours > 0
        "#{hours}h #{minutes % 60}m"
      elsif minutes > 0
        "#{minutes}m #{seconds % 60}s"
      else
        "#{seconds}s"
      end
    end

    def material_count
      materials&.length || 0
    end

    def add_material(uri:, digest:, **options)
      material = {
        uri: uri,
        digest: digest,
        **options
      }

      self.materials = (materials || []) << material
      save!
    end

    def find_material_by_uri(uri)
      materials&.find { |m| m["uri"] == uri }
    end

    def source_material
      find_material_by_uri(source_repository) ||
        materials&.find { |m| m["uri"]&.include?("git") }
    end

    def verify_reproducibility!(verification_hash = nil)
      if verification_hash.present? && verification_hash == reproducibility_hash
        update!(
          reproducible: true,
          reproducibility_verified_at: Time.current
        )
        true
      else
        update!(reproducible: false)
        false
      end
    end

    def to_slsa_predicate
      {
        "buildDefinition" => {
          "buildType" => builder_id,
          "externalParameters" => invocation.dig("parameters") || {},
          "internalParameters" => invocation.dig("internal_parameters") || {},
          "resolvedDependencies" => materials.map do |m|
            {
              "uri" => m["uri"],
              "digest" => m["digest"]
            }
          end
        },
        "runDetails" => {
          "builder" => {
            "id" => builder_id,
            "version" => builder_version ? { builder_id => builder_version } : {}
          },
          "metadata" => {
            "invocationId" => attestation.attestation_id,
            "startedOn" => build_started_at&.iso8601,
            "finishedOn" => build_finished_at&.iso8601
          },
          "byproducts" => []
        }
      }
    end

    def summary
      {
        id: id,
        attestation_id: attestation_id,
        builder_id: builder_id,
        builder_version: builder_version,
        material_count: material_count,
        source_repository: source_repository,
        source_commit: source_commit,
        source_branch: source_branch,
        reproducible: reproducible?,
        verified_reproducible: verified_reproducible?,
        build_started_at: build_started_at,
        build_finished_at: build_finished_at,
        build_duration_ms: build_duration_ms,
        formatted_duration: formatted_duration
      }
    end

    private

    def sanitize_jsonb_fields
      self.materials ||= []
      self.invocation ||= {}
      self.build_config ||= {}
      self.environment ||= {}
      self.metadata ||= {}
    end

    def should_calculate_duration?
      saved_change_to_build_started_at? || saved_change_to_build_finished_at?
    end

    def calculate_duration
      return unless build_started_at.present? && build_finished_at.present?

      duration = ((build_finished_at - build_started_at) * 1000).to_i
      update_column(:build_duration_ms, duration) if duration != build_duration_ms
    end
  end
end

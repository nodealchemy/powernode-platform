# frozen_string_literal: true

class CreateSupplyChainTables < ActiveRecord::Migration[8.0]
  def change
    # ============================================
    # Phase 1: Core SBOM Infrastructure
    # ============================================

    # Main SBOM documents
    create_table :supply_chain_sboms, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :repository, foreign_key: { to_table: :devops_repositories }, type: :uuid
      t.references :pipeline_run, foreign_key: { to_table: :devops_pipeline_runs }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :sbom_id, null: false
      t.string :format, null: false, default: "cyclonedx_1_5"
      t.jsonb :document, null: false, default: {}
      t.string :commit_sha
      t.string :branch
      t.string :version
      t.string :name

      t.integer :component_count, null: false, default: 0
      t.integer :vulnerability_count, null: false, default: 0
      t.decimal :risk_score, precision: 5, scale: 2, default: 0.0

      t.boolean :ntia_minimum_compliant, null: false, default: false
      t.string :document_hash
      t.text :signature
      t.string :signature_algorithm

      t.string :status, null: false, default: "draft"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :sbom_id], unique: true, name: "idx_sboms_account_sbom_id"
      t.index [:repository_id, :commit_sha], name: "idx_sboms_repo_commit"
      t.index [:account_id, :status], name: "idx_sboms_account_status"
      t.index [:created_at], name: "idx_sboms_created_at"
      t.index [:metadata], using: :gin, name: "idx_sboms_metadata"
    end

    # SBOM Components (individual dependencies)
    create_table :supply_chain_sbom_components, id: :uuid do |t|
      t.references :sbom, null: false, foreign_key: { to_table: :supply_chain_sboms, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.string :purl, null: false
      t.string :name, null: false
      t.string :version
      t.string :ecosystem, null: false
      t.string :namespace

      t.string :dependency_type, null: false, default: "direct"
      t.integer :depth, null: false, default: 0
      t.string :scope

      t.string :license_spdx_id
      t.string :license_name
      t.string :license_compliance_status, default: "unknown"

      t.decimal :risk_score, precision: 5, scale: 2, default: 0.0
      t.boolean :has_known_vulnerabilities, null: false, default: false
      t.boolean :is_outdated, null: false, default: false
      t.string :latest_version

      t.jsonb :metadata, null: false, default: {}
      t.jsonb :properties, null: false, default: {}

      t.timestamps null: false

      t.index [:sbom_id, :purl], unique: true, name: "idx_sbom_components_sbom_purl"
      t.index [:account_id, :ecosystem], name: "idx_sbom_components_account_ecosystem"
      t.index [:purl], name: "idx_sbom_components_purl"
      t.index [:has_known_vulnerabilities], name: "idx_sbom_components_has_vulns"
      t.index [:metadata], using: :gin, name: "idx_sbom_components_metadata"
    end

    # SBOM Vulnerabilities (CVE findings)
    create_table :supply_chain_sbom_vulnerabilities, id: :uuid do |t|
      t.references :sbom, null: false, foreign_key: { to_table: :supply_chain_sboms, on_delete: :cascade }, type: :uuid
      t.references :component, null: false, foreign_key: { to_table: :supply_chain_sbom_components, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.string :vulnerability_id, null: false
      t.string :source, null: false, default: "nvd"
      t.string :severity, null: false, default: "unknown"
      t.decimal :cvss_score, precision: 4, scale: 2
      t.string :cvss_vector
      t.integer :cvss_version

      t.decimal :contextual_score, precision: 4, scale: 2
      t.jsonb :context_factors, null: false, default: {}

      t.string :remediation_status, null: false, default: "open"
      t.string :fixed_version
      t.text :description
      t.jsonb :references, null: false, default: []

      t.datetime :published_at
      t.datetime :modified_at
      t.datetime :dismissed_at
      t.references :dismissed_by, foreign_key: { to_table: :users }, type: :uuid
      t.text :dismissal_reason

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:sbom_id, :vulnerability_id, :component_id], unique: true, name: "idx_sbom_vulns_unique"
      t.index [:account_id, :severity], name: "idx_sbom_vulns_account_severity"
      t.index [:vulnerability_id], name: "idx_sbom_vulns_vuln_id"
      t.index [:remediation_status], name: "idx_sbom_vulns_status"
      t.index [:context_factors], using: :gin, name: "idx_sbom_vulns_context"
    end

    # SBOM Diffs (drift detection)
    create_table :supply_chain_sbom_diffs, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :base_sbom, null: false, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :target_sbom, null: false, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid

      t.jsonb :added_components, null: false, default: []
      t.jsonb :removed_components, null: false, default: []
      t.jsonb :updated_components, null: false, default: []
      t.jsonb :new_vulnerabilities, null: false, default: []
      t.jsonb :resolved_vulnerabilities, null: false, default: []

      t.integer :added_count, null: false, default: 0
      t.integer :removed_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.decimal :risk_delta, precision: 5, scale: 2, default: 0.0

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:base_sbom_id, :target_sbom_id], unique: true, name: "idx_sbom_diffs_base_target"
      t.index [:account_id, :created_at], name: "idx_sbom_diffs_account_created"
    end

    # ============================================
    # Phase 2: Vulnerability Intelligence
    # ============================================

    # Vulnerability Feeds (external sources)
    create_table :supply_chain_vulnerability_feeds, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.string :source, null: false
      t.string :name, null: false
      t.string :url
      t.string :api_key_encrypted

      t.datetime :last_sync_at
      t.string :sync_status, null: false, default: "pending"
      t.integer :entry_count, null: false, default: 0
      t.text :last_sync_error

      t.boolean :is_active, null: false, default: true
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :source], unique: true, name: "idx_vuln_feeds_account_source"
      t.index [:sync_status], name: "idx_vuln_feeds_sync_status"
    end

    # Remediation Plans
    create_table :supply_chain_remediation_plans, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sbom, null: false, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :workflow_run, foreign_key: { to_table: :ai_workflow_runs }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :plan_type, null: false, default: "manual"
      t.string :status, null: false, default: "draft"

      t.jsonb :target_vulnerabilities, null: false, default: []
      t.jsonb :upgrade_recommendations, null: false, default: []
      t.jsonb :breaking_changes, null: false, default: []
      t.text :summary

      t.decimal :confidence_score, precision: 5, scale: 4, default: 0.0
      t.boolean :auto_executable, null: false, default: false

      t.string :generated_pr_url
      t.string :approval_status, default: "pending"
      t.references :approved_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :approved_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :status], name: "idx_remediation_plans_account_status"
      t.index [:sbom_id], name: "idx_remediation_plans_sbom"
    end

    # ============================================
    # Phase 3: Artifact Provenance
    # ============================================

    # Signing Keys
    create_table :supply_chain_signing_keys, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :key_id, null: false
      t.string :key_type, null: false, default: "cosign"
      t.string :name, null: false
      t.text :description

      t.text :encrypted_private_key
      t.text :public_key, null: false
      t.string :fingerprint, null: false

      t.string :kms_provider
      t.string :kms_key_uri
      t.string :kms_region

      t.string :status, null: false, default: "active"
      t.datetime :expires_at
      t.datetime :rotated_at
      t.references :rotated_from, foreign_key: { to_table: :supply_chain_signing_keys }, type: :uuid

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :key_id], unique: true, name: "idx_signing_keys_account_key_id"
      t.index [:fingerprint], unique: true, name: "idx_signing_keys_fingerprint"
      t.index [:status], name: "idx_signing_keys_status"
    end

    # Attestations (SLSA provenance records)
    create_table :supply_chain_attestations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :signing_key, foreign_key: { to_table: :supply_chain_signing_keys }, type: :uuid
      t.references :pipeline_run, foreign_key: { to_table: :devops_pipeline_runs }, type: :uuid
      t.references :sbom, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :attestation_id, null: false
      t.string :attestation_type, null: false, default: "slsa_provenance"
      t.integer :slsa_level, default: 1

      t.string :subject_name, null: false
      t.string :subject_digest, null: false
      t.string :subject_digest_algorithm, null: false, default: "sha256"

      t.jsonb :predicate, null: false, default: {}
      t.string :predicate_type, null: false

      t.text :signature
      t.string :signature_algorithm
      t.string :signature_format, default: "dsse"

      t.string :rekor_log_id
      t.string :rekor_log_url
      t.datetime :rekor_logged_at

      t.string :verification_status, null: false, default: "unverified"
      t.jsonb :verification_results, null: false, default: {}
      t.datetime :verified_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :attestation_id], unique: true, name: "idx_attestations_account_id"
      t.index [:subject_digest], name: "idx_attestations_subject_digest"
      t.index [:verification_status], name: "idx_attestations_verification"
      t.index [:predicate], using: :gin, name: "idx_attestations_predicate"
    end

    # Build Provenance (detailed build metadata)
    create_table :supply_chain_build_provenances, id: :uuid do |t|
      t.references :attestation, null: false, foreign_key: { to_table: :supply_chain_attestations, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.string :builder_id, null: false
      t.string :builder_version

      t.jsonb :materials, null: false, default: []
      t.jsonb :invocation, null: false, default: {}
      t.jsonb :build_config, null: false, default: {}
      t.jsonb :environment, null: false, default: {}

      t.boolean :reproducible, null: false, default: false
      t.datetime :reproducibility_verified_at
      t.string :reproducibility_hash

      t.string :source_repository
      t.string :source_commit
      t.string :source_branch

      t.datetime :build_started_at
      t.datetime :build_finished_at
      t.integer :build_duration_ms

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:attestation_id], unique: true, name: "idx_build_provenance_attestation"
      t.index [:builder_id], name: "idx_build_provenance_builder"
      t.index [:materials], using: :gin, name: "idx_build_provenance_materials"
    end

    # Verification Logs (tamper-evident audit chain)
    create_table :supply_chain_verification_logs, id: :uuid do |t|
      t.references :attestation, null: false, foreign_key: { to_table: :supply_chain_attestations }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :verified_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :verification_type, null: false
      t.string :result, null: false
      t.text :result_message

      t.string :previous_log_hash
      t.string :log_hash, null: false

      t.jsonb :verification_details, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:attestation_id, :created_at], name: "idx_verification_logs_attestation_time"
      t.index [:log_hash], unique: true, name: "idx_verification_logs_hash"
      t.index [:previous_log_hash], name: "idx_verification_logs_prev_hash"
    end

    # ============================================
    # Phase 4: Container Security
    # ============================================

    # Container Images
    create_table :supply_chain_container_images, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :attestation, foreign_key: { to_table: :supply_chain_attestations }, type: :uuid
      t.references :sbom, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :base_image, foreign_key: { to_table: :supply_chain_container_images }, type: :uuid

      t.string :registry, null: false
      t.string :repository, null: false
      t.string :tag
      t.string :digest, null: false

      t.jsonb :layers, null: false, default: []
      t.bigint :size_bytes, default: 0
      t.string :architecture
      t.string :os

      t.string :status, null: false, default: "unverified"
      t.boolean :is_signed, null: false, default: false
      t.boolean :is_deployed, null: false, default: false
      t.jsonb :deployment_contexts, null: false, default: []

      t.integer :critical_vuln_count, null: false, default: 0
      t.integer :high_vuln_count, null: false, default: 0
      t.integer :medium_vuln_count, null: false, default: 0
      t.integer :low_vuln_count, null: false, default: 0

      t.datetime :last_scanned_at
      t.datetime :pushed_at

      t.jsonb :labels, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :digest], unique: true, name: "idx_container_images_account_digest"
      t.index [:registry, :repository, :tag], name: "idx_container_images_registry_repo_tag"
      t.index [:status], name: "idx_container_images_status"
      t.index [:is_deployed], name: "idx_container_images_deployed"
      t.index [:labels], using: :gin, name: "idx_container_images_labels"
    end

    # Image Policies (allowlist/enforcement)
    create_table :supply_chain_image_policies, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.text :description
      t.string :policy_type, null: false, default: "registry_allowlist"
      t.string :enforcement_level, null: false, default: "warn"

      t.jsonb :match_rules, null: false, default: {}
      t.jsonb :rules, null: false, default: {}

      t.integer :max_critical_vulns
      t.integer :max_high_vulns
      t.boolean :require_signature, null: false, default: false
      t.boolean :require_sbom, null: false, default: false

      t.boolean :is_active, null: false, default: true
      t.integer :priority, null: false, default: 0

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :name], unique: true, name: "idx_image_policies_account_name"
      t.index [:policy_type], name: "idx_image_policies_type"
      t.index [:is_active], name: "idx_image_policies_active"
    end

    # Vulnerability Scans (image scan results)
    create_table :supply_chain_vulnerability_scans, id: :uuid do |t|
      t.references :container_image, null: false, foreign_key: { to_table: :supply_chain_container_images, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :scanner_name, null: false, default: "trivy"
      t.string :scanner_version
      t.string :status, null: false, default: "pending"

      t.integer :critical_count, null: false, default: 0
      t.integer :high_count, null: false, default: 0
      t.integer :medium_count, null: false, default: 0
      t.integer :low_count, null: false, default: 0
      t.integer :unknown_count, null: false, default: 0

      t.jsonb :vulnerabilities, null: false, default: []
      t.jsonb :sbom, null: false, default: {}
      t.jsonb :layer_vulnerabilities, null: false, default: {}

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.text :error_message

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:container_image_id, :created_at], name: "idx_vuln_scans_image_created"
      t.index [:account_id, :status], name: "idx_vuln_scans_account_status"
      t.index [:vulnerabilities], using: :gin, name: "idx_vuln_scans_vulns"
    end

    # CVE Monitors (continuous monitoring)
    create_table :supply_chain_cve_monitors, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.text :description
      t.string :scope_type, null: false, default: "account_wide"
      t.uuid :scope_id

      t.string :min_severity, null: false, default: "medium"
      t.string :schedule_cron
      t.datetime :last_run_at
      t.datetime :next_run_at

      t.jsonb :notification_channels, null: false, default: []
      t.jsonb :filters, null: false, default: {}

      t.boolean :is_active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :name], unique: true, name: "idx_cve_monitors_account_name"
      t.index [:scope_type, :scope_id], name: "idx_cve_monitors_scope"
      t.index [:is_active], name: "idx_cve_monitors_active"
      t.index [:next_run_at], name: "idx_cve_monitors_next_run"
    end

    # ============================================
    # Phase 5: License Compliance
    # ============================================

    # Licenses (SPDX license catalog)
    create_table :supply_chain_licenses, id: :uuid do |t|
      t.string :spdx_id, null: false
      t.string :name, null: false
      t.string :category, null: false, default: "unknown"

      t.boolean :is_osi_approved, null: false, default: false
      t.boolean :is_copyleft, null: false, default: false
      t.boolean :is_strong_copyleft, null: false, default: false
      t.boolean :is_network_copyleft, null: false, default: false
      t.boolean :is_deprecated, null: false, default: false

      t.text :description
      t.text :license_text
      t.string :url

      t.jsonb :compatibility, null: false, default: {}
      t.jsonb :detection_patterns, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:spdx_id], unique: true, name: "idx_licenses_spdx_id"
      t.index [:category], name: "idx_licenses_category"
      t.index [:is_copyleft], name: "idx_licenses_copyleft"
    end

    # License Policies
    create_table :supply_chain_license_policies, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.text :description
      t.string :policy_type, null: false, default: "allowlist"
      t.string :enforcement_level, null: false, default: "warn"

      t.jsonb :allowed_licenses, null: false, default: []
      t.jsonb :denied_licenses, null: false, default: []
      t.jsonb :exception_packages, null: false, default: []

      t.boolean :block_copyleft, null: false, default: false
      t.boolean :block_strong_copyleft, null: false, default: true
      t.boolean :block_unknown, null: false, default: false

      t.boolean :is_active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.integer :priority, null: false, default: 0

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :name], unique: true, name: "idx_license_policies_account_name"
      t.index [:is_active], name: "idx_license_policies_active"
      t.index [:is_default], where: "is_default = true", name: "idx_license_policies_default"
    end

    # License Detections
    create_table :supply_chain_license_detections, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sbom_component, null: false, foreign_key: { to_table: :supply_chain_sbom_components, on_delete: :cascade }, type: :uuid
      t.references :license, foreign_key: { to_table: :supply_chain_licenses }, type: :uuid

      t.string :detected_license_id
      t.string :detected_license_name
      t.string :detection_source, null: false, default: "manifest"
      t.decimal :confidence_score, precision: 5, scale: 4, default: 1.0

      t.jsonb :ai_interpretation, null: false, default: {}
      t.text :license_text_snippet
      t.string :file_path

      t.boolean :is_primary, null: false, default: true
      t.boolean :requires_review, null: false, default: false

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:sbom_component_id], name: "idx_license_detections_component"
      t.index [:license_id], name: "idx_license_detections_license"
      t.index [:detection_source], name: "idx_license_detections_source"
    end

    # License Violations
    create_table :supply_chain_license_violations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sbom, null: false, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :sbom_component, null: false, foreign_key: { to_table: :supply_chain_sbom_components }, type: :uuid
      t.references :license_policy, null: false, foreign_key: { to_table: :supply_chain_license_policies }, type: :uuid
      t.references :license, foreign_key: { to_table: :supply_chain_licenses }, type: :uuid

      t.string :violation_type, null: false, default: "denied"
      t.string :severity, null: false, default: "high"
      t.string :status, null: false, default: "open"

      t.text :description
      t.jsonb :ai_remediation, null: false, default: {}

      t.boolean :exception_requested, null: false, default: false
      t.string :exception_status
      t.text :exception_reason
      t.references :exception_approved_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :exception_approved_at
      t.datetime :exception_expires_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :status], name: "idx_license_violations_account_status"
      t.index [:sbom_id], name: "idx_license_violations_sbom"
      t.index [:violation_type], name: "idx_license_violations_type"
    end

    # Attributions (NOTICE file entries)
    create_table :supply_chain_attributions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sbom_component, null: false, foreign_key: { to_table: :supply_chain_sbom_components, on_delete: :cascade }, type: :uuid
      t.references :license, foreign_key: { to_table: :supply_chain_licenses }, type: :uuid

      t.string :package_name, null: false
      t.string :package_version
      t.string :copyright_holder
      t.integer :copyright_year

      t.text :license_text
      t.text :notice_text
      t.string :attribution_url

      t.boolean :requires_attribution, null: false, default: true
      t.boolean :requires_license_copy, null: false, default: false
      t.boolean :requires_source_disclosure, null: false, default: false

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:sbom_component_id], unique: true, name: "idx_attributions_component"
      t.index [:account_id], name: "idx_attributions_account"
    end

    # ============================================
    # Phase 6: Vendor Risk
    # ============================================

    # Vendors (third-party registry)
    create_table :supply_chain_vendors, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :vendor_type, null: false, default: "saas"
      t.string :website
      t.string :contact_email

      t.string :risk_tier, null: false, default: "medium"
      t.decimal :risk_score, precision: 5, scale: 2, default: 0.0

      t.jsonb :certifications, null: false, default: []
      t.jsonb :security_contacts, null: false, default: []

      t.boolean :handles_pii, null: false, default: false
      t.boolean :handles_phi, null: false, default: false
      t.boolean :handles_pci, null: false, default: false
      t.boolean :has_baa, null: false, default: false
      t.boolean :has_dpa, null: false, default: false

      t.string :status, null: false, default: "active"
      t.datetime :contract_start_date
      t.datetime :contract_end_date
      t.datetime :last_assessment_at
      t.datetime :next_assessment_due

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :slug], unique: true, name: "idx_vendors_account_slug"
      t.index [:risk_tier], name: "idx_vendors_risk_tier"
      t.index [:status], name: "idx_vendors_status"
      t.index [:certifications], using: :gin, name: "idx_vendors_certifications"
    end

    # Risk Assessments
    create_table :supply_chain_risk_assessments, id: :uuid do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :supply_chain_vendors, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :assessor, foreign_key: { to_table: :users }, type: :uuid

      t.string :assessment_type, null: false, default: "initial"
      t.string :status, null: false, default: "in_progress"

      t.decimal :security_score, precision: 5, scale: 2, default: 0.0
      t.decimal :compliance_score, precision: 5, scale: 2, default: 0.0
      t.decimal :operational_score, precision: 5, scale: 2, default: 0.0
      t.decimal :overall_score, precision: 5, scale: 2, default: 0.0

      t.jsonb :findings, null: false, default: []
      t.jsonb :recommendations, null: false, default: []
      t.jsonb :evidence, null: false, default: []

      t.text :summary
      t.datetime :assessment_date
      t.datetime :valid_until
      t.datetime :completed_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:vendor_id, :created_at], name: "idx_risk_assessments_vendor_created"
      t.index [:account_id, :status], name: "idx_risk_assessments_account_status"
      t.index [:assessment_type], name: "idx_risk_assessments_type"
    end

    # Questionnaire Templates (SOC 2, ISO 27001)
    create_table :supply_chain_questionnaire_templates, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.text :description
      t.string :template_type, null: false, default: "custom"
      t.string :version, null: false, default: "1.0"

      t.jsonb :sections, null: false, default: []
      t.jsonb :questions, null: false, default: []

      t.boolean :is_system, null: false, default: false
      t.boolean :is_active, null: false, default: true

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :name], unique: true, where: "account_id IS NOT NULL", name: "idx_questionnaire_templates_account_name"
      t.index [:template_type], name: "idx_questionnaire_templates_type"
      t.index [:is_system], name: "idx_questionnaire_templates_system"
    end

    # Questionnaire Responses
    create_table :supply_chain_questionnaire_responses, id: :uuid do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :supply_chain_vendors }, type: :uuid
      t.references :template, null: false, foreign_key: { to_table: :supply_chain_questionnaire_templates }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :risk_assessment, foreign_key: { to_table: :supply_chain_risk_assessments }, type: :uuid
      t.references :requested_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :status, null: false, default: "pending"
      t.string :access_token, null: false

      t.jsonb :responses, null: false, default: {}
      t.decimal :overall_score, precision: 5, scale: 2
      t.jsonb :section_scores, null: false, default: {}

      t.datetime :sent_at
      t.datetime :started_at
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.datetime :expires_at

      t.references :reviewed_by, foreign_key: { to_table: :users }, type: :uuid
      t.text :review_notes

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:vendor_id, :template_id], name: "idx_questionnaire_responses_vendor_template"
      t.index [:access_token], unique: true, name: "idx_questionnaire_responses_token"
      t.index [:status], name: "idx_questionnaire_responses_status"
    end

    # Vendor Monitoring Events
    create_table :supply_chain_vendor_monitoring_events, id: :uuid do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :supply_chain_vendors, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.string :event_type, null: false
      t.string :severity, null: false, default: "info"
      t.string :source, null: false, default: "internal"

      t.string :title, null: false
      t.text :description
      t.string :external_url

      t.jsonb :recommended_actions, null: false, default: []
      t.jsonb :affected_services, null: false, default: []

      t.boolean :is_acknowledged, null: false, default: false
      t.datetime :acknowledged_at
      t.references :acknowledged_by, foreign_key: { to_table: :users }, type: :uuid

      t.datetime :detected_at, null: false
      t.datetime :resolved_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:vendor_id, :created_at], name: "idx_vendor_events_vendor_created"
      t.index [:account_id, :severity], name: "idx_vendor_events_account_severity"
      t.index [:event_type], name: "idx_vendor_events_type"
      t.index [:is_acknowledged], name: "idx_vendor_events_acknowledged"
    end

    # ============================================
    # Marketplace: Scan Templates
    # ============================================

    # Scan Templates (marketplace templates)
    create_table :supply_chain_scan_templates, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category, null: false, default: "security"

      t.jsonb :configuration_schema, null: false, default: {}
      t.jsonb :default_configuration, null: false, default: {}
      t.jsonb :supported_ecosystems, null: false, default: []

      t.string :version, null: false, default: "1.0.0"
      t.string :status, null: false, default: "draft"

      t.boolean :is_system, null: false, default: false
      t.boolean :is_public, null: false, default: false
      t.integer :install_count, null: false, default: 0
      t.decimal :average_rating, precision: 3, scale: 2, default: 0.0

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:slug], unique: true, name: "idx_scan_templates_slug"
      t.index [:category], name: "idx_scan_templates_category"
      t.index [:status], name: "idx_scan_templates_status"
      t.index [:is_public], name: "idx_scan_templates_public"
    end

    # Scan Instances (per-account instances)
    create_table :supply_chain_scan_instances, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :scan_template, null: false, foreign_key: { to_table: :supply_chain_scan_templates }, type: :uuid
      t.references :installed_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name, null: false
      t.text :description
      t.jsonb :configuration, null: false, default: {}

      t.string :status, null: false, default: "active"
      t.string :schedule_cron
      t.datetime :last_execution_at
      t.datetime :next_execution_at

      t.integer :execution_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :scan_template_id], unique: true, name: "idx_scan_instances_account_template"
      t.index [:status], name: "idx_scan_instances_status"
      t.index [:next_execution_at], name: "idx_scan_instances_next_execution"
    end

    # Scan Executions (execution tracking)
    create_table :supply_chain_scan_executions, id: :uuid do |t|
      t.references :scan_instance, null: false, foreign_key: { to_table: :supply_chain_scan_instances, on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :execution_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :trigger_type, null: false, default: "manual"

      t.jsonb :input_data, null: false, default: {}
      t.jsonb :output_data, null: false, default: {}
      t.text :logs

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.text :error_message

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:execution_id], unique: true, name: "idx_scan_executions_execution_id"
      t.index [:scan_instance_id, :created_at], name: "idx_scan_executions_instance_created"
      t.index [:account_id, :status], name: "idx_scan_executions_account_status"
    end

    # Reports (compliance exports)
    create_table :supply_chain_reports, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sbom, foreign_key: { to_table: :supply_chain_sboms }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :report_type, null: false
      t.string :format, null: false, default: "pdf"
      t.string :name, null: false
      t.text :description

      t.string :status, null: false, default: "pending"
      t.string :file_path
      t.string :file_url
      t.bigint :file_size_bytes

      t.jsonb :parameters, null: false, default: {}
      t.jsonb :summary, null: false, default: {}

      t.datetime :generated_at
      t.datetime :expires_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps null: false

      t.index [:account_id, :report_type], name: "idx_reports_account_type"
      t.index [:status], name: "idx_reports_status"
      t.index [:created_at], name: "idx_reports_created"
    end

    # ============================================
    # Check Constraints
    # ============================================

    # SBOM constraints
    add_check_constraint :supply_chain_sboms,
      "format IN ('spdx_2_3', 'cyclonedx_1_4', 'cyclonedx_1_5', 'cyclonedx_1_6')",
      name: "check_sboms_format"

    add_check_constraint :supply_chain_sboms,
      "status IN ('draft', 'generating', 'completed', 'failed', 'archived')",
      name: "check_sboms_status"

    add_check_constraint :supply_chain_sbom_components,
      "dependency_type IN ('direct', 'transitive', 'dev', 'optional', 'peer')",
      name: "check_sbom_components_dependency_type"

    add_check_constraint :supply_chain_sbom_components,
      "ecosystem IN ('npm', 'gem', 'pip', 'maven', 'gradle', 'go', 'cargo', 'nuget', 'composer', 'hex', 'pub', 'cocoapods', 'swift', 'other')",
      name: "check_sbom_components_ecosystem"

    add_check_constraint :supply_chain_sbom_vulnerabilities,
      "severity IN ('critical', 'high', 'medium', 'low', 'none', 'unknown')",
      name: "check_sbom_vulns_severity"

    add_check_constraint :supply_chain_sbom_vulnerabilities,
      "remediation_status IN ('open', 'in_progress', 'fixed', 'dismissed', 'wont_fix')",
      name: "check_sbom_vulns_remediation_status"

    # Vulnerability feed constraints
    add_check_constraint :supply_chain_vulnerability_feeds,
      "source IN ('nvd', 'osv', 'github_advisory', 'snyk', 'sonatype', 'custom')",
      name: "check_vuln_feeds_source"

    add_check_constraint :supply_chain_vulnerability_feeds,
      "sync_status IN ('pending', 'syncing', 'completed', 'failed')",
      name: "check_vuln_feeds_sync_status"

    # Remediation plan constraints
    add_check_constraint :supply_chain_remediation_plans,
      "plan_type IN ('manual', 'ai_generated', 'auto_fix')",
      name: "check_remediation_plans_type"

    add_check_constraint :supply_chain_remediation_plans,
      "status IN ('draft', 'pending_review', 'approved', 'rejected', 'executing', 'completed', 'failed')",
      name: "check_remediation_plans_status"

    # Signing key constraints
    add_check_constraint :supply_chain_signing_keys,
      "key_type IN ('cosign', 'oidc_identity', 'kms_reference', 'gpg')",
      name: "check_signing_keys_type"

    add_check_constraint :supply_chain_signing_keys,
      "status IN ('active', 'rotating', 'rotated', 'revoked', 'expired')",
      name: "check_signing_keys_status"

    # Attestation constraints
    add_check_constraint :supply_chain_attestations,
      "attestation_type IN ('slsa_provenance', 'sbom', 'vuln_scan', 'custom')",
      name: "check_attestations_type"

    add_check_constraint :supply_chain_attestations,
      "slsa_level IN (0, 1, 2, 3)",
      name: "check_attestations_slsa_level"

    add_check_constraint :supply_chain_attestations,
      "verification_status IN ('unverified', 'verified', 'failed', 'expired')",
      name: "check_attestations_verification_status"

    # Container image constraints
    add_check_constraint :supply_chain_container_images,
      "status IN ('unverified', 'verified', 'quarantined', 'approved', 'rejected')",
      name: "check_container_images_status"

    # Image policy constraints
    add_check_constraint :supply_chain_image_policies,
      "policy_type IN ('registry_allowlist', 'signature_required', 'vulnerability_threshold', 'custom')",
      name: "check_image_policies_type"

    add_check_constraint :supply_chain_image_policies,
      "enforcement_level IN ('log', 'warn', 'block')",
      name: "check_image_policies_enforcement"

    # Vulnerability scan constraints
    add_check_constraint :supply_chain_vulnerability_scans,
      "scanner_name IN ('trivy', 'grype', 'clair', 'snyk', 'custom')",
      name: "check_vuln_scans_scanner"

    add_check_constraint :supply_chain_vulnerability_scans,
      "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')",
      name: "check_vuln_scans_status"

    # CVE monitor constraints
    add_check_constraint :supply_chain_cve_monitors,
      "scope_type IN ('image', 'repository', 'account_wide')",
      name: "check_cve_monitors_scope"

    add_check_constraint :supply_chain_cve_monitors,
      "min_severity IN ('critical', 'high', 'medium', 'low')",
      name: "check_cve_monitors_severity"

    # License constraints
    add_check_constraint :supply_chain_licenses,
      "category IN ('permissive', 'copyleft', 'weak_copyleft', 'public_domain', 'proprietary', 'unknown')",
      name: "check_licenses_category"

    add_check_constraint :supply_chain_license_policies,
      "policy_type IN ('allowlist', 'denylist', 'hybrid')",
      name: "check_license_policies_type"

    add_check_constraint :supply_chain_license_policies,
      "enforcement_level IN ('log', 'warn', 'block')",
      name: "check_license_policies_enforcement"

    add_check_constraint :supply_chain_license_violations,
      "violation_type IN ('denied', 'copyleft', 'incompatible', 'unknown', 'expired')",
      name: "check_license_violations_type"

    add_check_constraint :supply_chain_license_violations,
      "severity IN ('critical', 'high', 'medium', 'low')",
      name: "check_license_violations_severity"

    add_check_constraint :supply_chain_license_violations,
      "status IN ('open', 'reviewing', 'resolved', 'exception_granted', 'wont_fix')",
      name: "check_license_violations_status"

    # Vendor constraints
    add_check_constraint :supply_chain_vendors,
      "vendor_type IN ('saas', 'api', 'library', 'infrastructure', 'hardware', 'consulting', 'other')",
      name: "check_vendors_type"

    add_check_constraint :supply_chain_vendors,
      "risk_tier IN ('critical', 'high', 'medium', 'low')",
      name: "check_vendors_risk_tier"

    add_check_constraint :supply_chain_vendors,
      "status IN ('active', 'inactive', 'under_review', 'terminated')",
      name: "check_vendors_status"

    # Risk assessment constraints
    add_check_constraint :supply_chain_risk_assessments,
      "assessment_type IN ('initial', 'periodic', 'incident', 'renewal')",
      name: "check_risk_assessments_type"

    add_check_constraint :supply_chain_risk_assessments,
      "status IN ('draft', 'in_progress', 'pending_review', 'completed', 'expired')",
      name: "check_risk_assessments_status"

    # Questionnaire constraints
    add_check_constraint :supply_chain_questionnaire_templates,
      "template_type IN ('soc2', 'iso27001', 'gdpr', 'hipaa', 'pci_dss', 'custom')",
      name: "check_questionnaire_templates_type"

    add_check_constraint :supply_chain_questionnaire_responses,
      "status IN ('pending', 'in_progress', 'submitted', 'reviewed', 'expired')",
      name: "check_questionnaire_responses_status"

    # Vendor monitoring event constraints
    add_check_constraint :supply_chain_vendor_monitoring_events,
      "event_type IN ('security_incident', 'breach', 'certification_expiry', 'contract_renewal', 'service_degradation', 'compliance_update', 'news_alert')",
      name: "check_vendor_events_type"

    add_check_constraint :supply_chain_vendor_monitoring_events,
      "severity IN ('critical', 'high', 'medium', 'low', 'info')",
      name: "check_vendor_events_severity"

    # Scan template constraints
    add_check_constraint :supply_chain_scan_templates,
      "category IN ('security', 'compliance', 'license', 'quality', 'custom')",
      name: "check_scan_templates_category"

    add_check_constraint :supply_chain_scan_templates,
      "status IN ('draft', 'published', 'archived', 'deprecated')",
      name: "check_scan_templates_status"

    # Scan instance constraints
    add_check_constraint :supply_chain_scan_instances,
      "status IN ('active', 'paused', 'disabled')",
      name: "check_scan_instances_status"

    # Scan execution constraints
    add_check_constraint :supply_chain_scan_executions,
      "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')",
      name: "check_scan_executions_status"

    add_check_constraint :supply_chain_scan_executions,
      "trigger_type IN ('manual', 'scheduled', 'webhook', 'pipeline', 'api')",
      name: "check_scan_executions_trigger"

    # Report constraints
    add_check_constraint :supply_chain_reports,
      "report_type IN ('sbom_export', 'vulnerability_report', 'license_report', 'attribution', 'compliance_summary', 'vendor_assessment', 'custom')",
      name: "check_reports_type"

    add_check_constraint :supply_chain_reports,
      "format IN ('pdf', 'json', 'csv', 'html', 'xml', 'spdx', 'cyclonedx')",
      name: "check_reports_format"

    add_check_constraint :supply_chain_reports,
      "status IN ('pending', 'generating', 'completed', 'failed', 'expired')",
      name: "check_reports_status"
  end
end

# frozen_string_literal: true

# Auditable concern for models that need audit logging
# Automatically tracks changes for compliance and security
#
# ## Resolving the account
#
# Every AuditLog row requires an account (`belongs_to :account`, and
# `audit_logs.account_id` is NOT NULL): the account is how tenants read their
# own audit trail, so a row without one is a row nobody can ever see. Models
# that carry `belongs_to :account` need no configuration. Models that reach an
# account through an owner declare the path:
#
#     audit_account_via :ralph_loop                    # ralph_loop.account
#     audit_account_via %i[mcp_tool mcp_server], :user # first non-nil wins
#     audit_account_via :owner_account                 # already an Account
#
# Models that genuinely have no owning tenant (global reference data) declare
# that instead, which suppresses the write rather than letting it fail:
#
#     audit_without_account! reason: "global SPDX catalogue, not tenant data"
#
# Both declarations are asserted by spec/models/concerns/auditable_spec.rb,
# which walks every model including this concern.
module Auditable
  extend ActiveSupport::Concern

  # Raised when a model that is supposed to have an account cannot produce one.
  # Routed through the same failure path as any other audit write error.
  class AccountUnresolved < StandardError; end

  # Audit callbacks are inert in the test environment by default: the suite
  # creates records constantly and auditing every one would add an INSERT (plus
  # an advisory-lock round trip) to each. Specs that exercise auditing turn it
  # on for their own examples with `Auditable.with_logging`.
  mattr_accessor :logging_enabled, default: !Rails.env.test?

  # A failed audit write must never break the user-facing save that triggered
  # it, so outside the test environment a failure is logged and instrumented
  # but swallowed. In test it raises, so CI fails on a regression instead of
  # letting the gap reappear silently.
  mattr_accessor :raise_on_failure, default: Rails.env.test?

  # Emitted on every failed or suppressed audit write so the gap is countable
  # in production rather than living only in a log line.
  FAILURE_NOTIFICATION = "audit.write_failed.auditable"
  SKIPPED_NOTIFICATION = "audit.write_skipped.auditable"

  # Secret material that Rails does not classify as "encrypted" but that must
  # still never reach an audit row. Kept deliberately SHORT: a hand-maintained
  # list of column names is exactly what failed here — it named these two and
  # missed every `encrypted_*` column on Ai::DataSourceCredential, and any
  # encrypted column added tomorrow would have inherited the same gap silently.
  # The self-maintaining half of the rule is audit_redacted_attribute_names.
  ALWAYS_REDACTED_ATTRIBUTES = %w[password_digest encrypted_password].freeze

  # Written in place of a redacted value. A placeholder rather than a dropped
  # key, so the audit trail still records THAT a secret attribute was set or
  # changed — which is the part an auditor needs — without disclosing it.
  REDACTED_PLACEHOLDER = "[FILTERED]"

  def self.with_logging
    previous = logging_enabled
    self.logging_enabled = true
    yield
  ensure
    self.logging_enabled = previous
  end

  included do
    # Ordered candidate paths for resolving the audit account. Empty means
    # "use the model's own :account association".
    class_attribute :audit_account_sources, instance_writer: false, default: [].freeze

    # Set by audit_without_account! for global records with no owning tenant.
    class_attribute :audit_account_exemption, instance_writer: false, default: nil

    # Set by audit_optional_account! for models where only *some* rows are
    # tenant-owned (system templates shared across accounts, typically).
    class_attribute :audit_optional_account_reason, instance_writer: false, default: nil

    # Audit log creation after record creation
    after_create :log_record_creation

    # Audit log updates after record changes
    after_update :log_record_update

    # Audit log deletion before record destruction
    before_destroy :log_record_deletion
  end

  class_methods do
    # Declares where this model's audit account comes from. Each source is an
    # association name, or an array of names to walk. The first source that
    # yields an account wins.
    def audit_account_via(*sources)
      self.audit_account_sources = sources.map { |source| Array(source).map(&:to_sym).freeze }.freeze
    end

    # Declares that this model has no owning account, so audit writes are
    # suppressed instead of failing. The reason is surfaced by the spec.
    def audit_without_account!(reason:)
      self.audit_account_exemption = reason
    end

    # Declares that a row of this model may legitimately have no account (a
    # system template shared across tenants). Those rows are skipped; rows that
    # do have an account are audited normally.
    def audit_optional_account!(reason:)
      self.audit_optional_account_reason = reason
    end
  end

  # The account an audit row for this record belongs to. Override directly for
  # anything the declarative form cannot express.
  def audit_account
    return try(:account) if audit_account_sources.empty?

    audit_account_sources.each do |path|
      owner = path.reduce(self) { |object, segment| object.respond_to?(segment) ? object.public_send(segment) : nil }
      next if owner.nil?

      resolved = owner.is_a?(Account) ? owner : owner.try(:account)
      return resolved if resolved
    end

    nil
  end

  private

  def log_record_creation
    write_audit_log("created", new_values: redact_audit_values(auditable_attributes))
  end

  def log_record_update
    return unless saved_changes.present?

    # Filter out non-auditable changes (timestamps, etc.)
    relevant_changes = saved_changes.except("updated_at", "created_at")
    return if relevant_changes.empty?

    # saved_changes is the ONLY source here — it deliberately does not go
    # through auditable_attributes, because an update audits what changed, not
    # the whole row. That divergence is why the two paths could drift on
    # secrets; redact_audit_values is the seam they now share.
    write_audit_log(
      "updated",
      old_values: redact_audit_values(relevant_changes.transform_values(&:first)),
      new_values: redact_audit_values(relevant_changes.transform_values(&:last))
    )
  end

  def log_record_deletion
    write_audit_log("deleted", old_values: redact_audit_values(auditable_attributes))
  end

  def write_audit_log(action, old_values: nil, new_values: nil)
    return unless Auditable.logging_enabled
    return record_audit_skipped(action) if audit_account_exemption

    account = audit_account
    if account.nil?
      return record_audit_skipped(action) if audit_optional_account_reason

      raise AccountUnresolved,
            "#{self.class.name} could not resolve an audit account. Declare one with " \
            "audit_account_via, or audit_without_account! if it has no owning tenant."
    end

    AuditLog.log_action(
      action: action,
      resource: self,
      account: account,
      old_values: old_values,
      new_values: new_values,
      source: "system"
    )
  rescue StandardError => e
    record_audit_failure(action, e)
  end

  def record_audit_failure(action, error)
    ActiveSupport::Notifications.instrument(
      FAILURE_NOTIFICATION,
      model: self.class.name,
      record_id: id,
      action: action,
      error_class: error.class.name,
      message: error.message
    )
    Rails.logger.error "Failed to log record #{action} for #{self.class.name}##{id}: #{error.message}"
    raise error if Auditable.raise_on_failure
  end

  def record_audit_skipped(action)
    ActiveSupport::Notifications.instrument(
      SKIPPED_NOTIFICATION,
      model: self.class.name,
      record_id: id,
      action: action,
      reason: audit_account_exemption || audit_optional_account_reason
    )
    nil
  end

  # The ONE seam every audit path runs its values through, so create/delete
  # (which build from auditable_attributes) and update (which builds from
  # saved_changes) cannot diverge on secret handling again. Previously only the
  # create/delete path had any filter at all, and it lived inside
  # auditable_attributes where the update path never reached it.
  #
  # Values arrive already flattened to scalars: a Hash of attribute name to
  # value for create/delete, and to the old- or new-half of a saved_changes
  # pair for update. Redaction is by attribute NAME, so both halves of a change
  # are covered and the key survives to show the attribute changed.
  def redact_audit_values(values)
    return values if values.blank?

    redacted = audit_redacted_attribute_names
    values.each_with_object({}) do |(name, value), filtered|
      filtered[name] = redacted.include?(name.to_s) ? REDACTED_PLACEHOLDER : value
    end
  end

  # Which attribute names must never have their VALUE written to an audit row.
  #
  # The encrypted half is asked of the model rather than listed here, and that
  # is the whole point of the fix. `encrypts` installs an attribute type that
  # decrypts transparently, so `attributes` and `saved_changes` hand back
  # plaintext — which makes the model's encrypted set exactly the set of values
  # that would otherwise be disclosed, and makes the rule self-maintaining: a
  # column that gains `encrypts` later is covered the moment it is declared,
  # with no second place to remember to update. `encrypted_attributes` is
  # defined on every ActiveRecord class and is nil until `encrypts` is called.
  def audit_redacted_attribute_names
    encrypted = self.class.try(:encrypted_attributes) || []
    Set.new(ALWAYS_REDACTED_ATTRIBUTES).merge(encrypted.map(&:to_s))
  end

  # Override this method in models to specify WHICH attributes are audited.
  # Secret values are not this method's concern — redact_audit_values runs over
  # its result (and over the update path alike), so an override here cannot
  # reintroduce the disclosure.
  def auditable_attributes
    attributes.except("id", "created_at", "updated_at")
  end
end

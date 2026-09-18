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

  # The redaction rule, expressed WITHOUT an instance so a writer that never
  # goes through this concern can apply the same one. AuditLog itself calls
  # these from a before_validation, which is what makes the rule cover every
  # writer of audit_logs rather than only the models that include Auditable
  # (IMP-01a08809). The instance methods below delegate here, so there is one
  # definition and the two cannot drift.
  #
  # `klass` is the resource's CLASS, or nil when it cannot be resolved —
  # Audit::LoggingService and AuditLogging both synthesize OpenStruct dummy
  # resources whose class name ("API", "Webhook") constantizes to nothing. A
  # nil klass still gets ALWAYS_REDACTED_ATTRIBUTES, which is the floor; it
  # must never raise, because a redaction pass that blows up takes the audit
  # write down with it.
  #
  # `extra_redacted:` is the CLASS-LEVEL rule's per-instance, per-write
  # extension — see #audit_extra_redactions below for what sets it and why.
  # It is matched by EXACT name (like the `redacted` set below), not the
  # substring semantics `attribute_filter_for` gives `filter_attributes`:
  # a caller here lists every field it means, deliberately, rather than
  # relying on one name to sweep in siblings it may not have reviewed.
  def self.redact_values(values, klass, extra_redacted: nil)
    return values unless values.is_a?(Hash)
    return values if values.blank?

    redacted = redacted_attribute_names_for(klass)
    redacted |= Array(extra_redacted).map(&:to_s) if extra_redacted.present?
    filter = attribute_filter_for(klass)
    values.each_with_object({}) do |(name, value), filtered|
      filtered[name] = if redacted.include?(name.to_s)
        REDACTED_PLACEHOLDER
      else
        filter.filter_param(name.to_s, value)
      end
    end
  end

  def self.redacted_attribute_names_for(klass)
    encrypted = klass.try(:encrypted_attributes) || []
    Set.new(ALWAYS_REDACTED_ATTRIBUTES).merge(encrypted.map(&:to_s))
  end

  def self.attribute_filter_for(klass)
    ActiveSupport::ParameterFilter.new(
      Array(klass.try(:filter_attributes)), mask: REDACTED_PLACEHOLDER
    )
  end

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

    # Set by webhook_payload_attributes (IMP-dd0305de2799, D5). Empty by
    # default — see #webhook_payload_data for why that default is "ids only",
    # not "everything redact_audit_values doesn't specifically strip".
    class_attribute :webhook_payload_attribute_names, instance_writer: false, default: [].freeze

    # Per-INSTANCE, per-WRITE redaction extension. An ordinary attr_accessor
    # (in-memory only, never persisted): a caller sets it on a specific
    # record, immediately before the one save whose automatic audit row must
    # not archive certain field values — an erasure/anonymization write being
    # the motivating case, but nothing here names one (IMP-7ff4be3454a6).
    #
    #   record.audit_extra_redactions = %w[email name authorized_keys]
    #   record.update!(...)
    #
    # Why an instance ivar and not a class-level toggle: the class-level
    # `filter_attributes` seam (see redacted_attribute_names_for /
    # attribute_filter_for) redacts a field for EVERY write of EVERY instance
    # of the model, which is too broad when only one specific write needs it
    # — the same field can be exactly the evidence a NORMAL write's audit row
    # exists to preserve (User#authorized_keys: pinned in
    # spec/models/concerns/auditable_secret_redaction_spec.rb, "a public key
    # is not a secret"). And `Auditable.logging_enabled` (the other existing
    # toggle) is a process-wide `mattr_accessor` — flipping it around one
    # save is not thread-safe under a threaded Puma worker, so it must never
    # be reused for this. An instance ivar has neither problem: it is scoped
    # to the one Ruby object the caller is holding, so no other request or
    # thread can observe it.
    #
    # Cleared on every path that could otherwise leave it set on the
    # in-memory instance after the one write it was meant for is done —
    # not only the happy path. FOUR clear sites, each verified empirically
    # (spec/models/concerns/auditable_secret_redaction_spec.rb) against what
    # this Rails version's callback/transaction machinery actually does,
    # not assumed from general Rails knowledge — the first draft of this
    # comment claimed after_rollback alone would cover a validation failure,
    # which measurement below disproves:
    #   - #write_audit_log clears it FIRST, unconditionally, which covers a
    #     write that reaches that method (including when logging is
    #     disabled, Auditable.logging_enabled false — the test-env default —
    #     and no row is ever written). Safe there because every
    #     #redact_audit_values call for THIS write has already consumed it —
    #     Ruby evaluates a method's keyword-argument values before the
    #     method body runs, so by the time write_audit_log's body starts,
    #     the callback that triggered it already built old_values/new_values
    #     with this redaction applied.
    #   - #log_record_update's own early returns (saved_changes blank — a
    #     genuine no-op update, e.g. re-assigning a field its current value —
    #     or only timestamp columns changed) never reach write_audit_log at
    #     all, so each clears it directly before returning.
    #   - after_validation, ONLY when validation failed (`if: -> {
    #     errors.any? }` — never on a passing validation, or it would clear
    #     the flag before create/update ever gets to use it). This is the
    #     PRIMARY defense for the common "save failed" case: a plain
    #     `record.update!(invalid_attrs)` raises ActiveRecord::RecordInvalid
    #     from validation, WITHOUT ever entering a transaction or running
    #     after_update/after_rollback — measured directly, not assumed (see
    #     "checks whether after_rollback fires on a validation failure" in
    #     the redaction spec, which is false even wrapped in an explicit
    #     outer transaction).
    #   - after_rollback covers the DIFFERENT case where validation PASSED,
    #     the record actually persisted, and something ELSE inside the same
    #     (often caller-opened) transaction failed afterward, rolling the
    #     whole thing back — measured to fire in exactly that shape. It does
    #     NOT fire for a validation failure (measured, see above); it is not
    #     a substitute for the after_validation clear, it is a different gap.
    # Without all four, a caller whose write failed (either way) or was a
    # no-op would leave the flag armed for whatever save touches this same
    # in-memory instance next — which could be a genuinely unrelated, later
    # write that was never meant to be redacted.
    #
    # Residual, accepted gap: a bare `record.valid?`/`record.invalid?` call —
    # not part of a save — also runs after_validation, so it would clear a
    # flag set for an UPCOMING save if that stray validity check happens to
    # fail in between. The documented contract is "set immediately before
    # the one save it covers"; a validity check squeezed into that window is
    # unusual, out-of-contract usage, not a normal caller shape.
    attr_accessor :audit_extra_redactions

    # Audit log creation after record creation
    after_create :log_record_creation

    # Audit log updates after record changes
    after_update :log_record_update

    # Audit log deletion before record destruction
    before_destroy :log_record_deletion

    # See the audit_extra_redactions declaration above for what each of
    # these two callbacks covers and why neither alone is sufficient.
    after_validation :clear_audit_extra_redactions, if: -> { errors.any? }
    after_rollback :clear_audit_extra_redactions
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

    # Declares which of this model's OWN attributes are safe to ship, verbatim
    # (after redact_audit_values), in an outbound platform webhook payload's
    # "data" (IMP-dd0305de2799, D5). Review the model's full column list
    # before calling this — it is an allowlist precisely because the default
    # (never calling it) is the safe one.
    def webhook_payload_attributes(*names)
      self.webhook_payload_attribute_names = names.map(&:to_s).freeze
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
    unless saved_changes.present?
      clear_audit_extra_redactions
      return
    end

    # Filter out non-auditable changes (timestamps, etc.)
    relevant_changes = saved_changes.except("updated_at", "created_at")
    if relevant_changes.empty?
      clear_audit_extra_redactions
      return
    end

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
    # Clear FIRST, unconditionally — see the audit_extra_redactions
    # declaration for why this is always safe: every redact_audit_values
    # call for THIS write already ran (its result is sitting in
    # old_values/new_values above) before this method's body started.
    clear_audit_extra_redactions

    return unless Auditable.logging_enabled
    return record_audit_skipped(action) if audit_account_exemption

    account = audit_account
    if account.nil?
      return record_audit_skipped(action) if audit_optional_account_reason
    end

    begin
      if account.nil?
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
      return record_audit_failure(action, e)
    end

    # IMP-dd0305de2799 (D9): deliberately OUTSIDE the rescue above and not
    # wrapped in one of its own that routes through record_audit_failure. The
    # audit row has already been written by the time this runs, so a
    # webhook-publish failure is a DIFFERENT fact than "the audit write
    # failed" and must not be reported (or counted) as one, nor allowed to
    # unwind an audit write that already succeeded. publish_webhook_event owns
    # its own failure handling end to end: it always logs, and in test it
    # re-raises so a regression fails loud — but that raise propagates
    # straight out of write_audit_log to the Rails callback (aborting the
    # triggering save, same as any other uncaught callback exception), never
    # through record_audit_failure / FAILURE_NOTIFICATION.
    publish_webhook_event(action, account)
  end

  # IMP-dd0305de2799: the generic create/update/delete audit trail this
  # concern already writes for every Auditable model is the seam a platform
  # webhook event hangs off of.
  #
  # Why hook HERE and not AuditLog.log_action itself — two independent
  # guards, doing two different jobs, and it matters which does which:
  #
  #   1. WebhookEventPublisher.event_type_for's %w[created updated deleted]
  #      allowlist is what actually prevents a double-fire TODAY: no
  #      AuditLog.log_action call site in core or the extensions passes a
  #      bare "created"/"updated"/"deleted" action directly (they use
  #      domain-specific names — "account_created", "suspend_account" — which
  #      the allowlist already rejects regardless of hook location), so
  #      hooking log_action itself would behave identically today. Do not
  #      credit the hook location for that; it doesn't do it.
  #   2. The hook location is what protects against a DIFFERENT, real risk:
  #      some log_action callers (Audit::LoggingService, AuditLogging) pass a
  #      synthesized OpenStruct "resource" rather than a real AR instance (see
  #      the comment on Auditable.redact_values about a nil-constantizing
  #      klass), and a future call site using a generic action name on one of
  #      those would sail past the allowlist with no real `id`/attributes to
  #      build a payload from. Hooking write_audit_log guarantees `self` is
  #      always a real, Auditable-including model instance. See
  #      spec/integration/webhook_platform_event_delivery_spec.rb for the
  #      constructed case: an explicit `AuditLog.log_action(action: "updated",
  #      ...)` call for the same resource does NOT produce a second delivery,
  #      precisely because that call never reaches this method.
  #
  # WebhookEventPublisher.event_type_for is also what makes this a no-op for
  # every Auditable model/action that isn't one of the names
  # WebhookEndpoint.available_event_types declares — most Auditable models
  # never produce a delivery.
  #
  # Inherits the audit subsystem's own enable flag and failure domain: this
  # never runs at all while Auditable.logging_enabled is false (test default),
  # and a write that bypasses Auditable's callbacks entirely — User#reset_password!
  # and Security::AccountEncryptionKeyService both use update_columns — never
  # reaches write_audit_log, so it produces no user.updated/account.updated
  # event either. That is the same audit blind spot those call sites already
  # have; this concern does not widen or narrow it.
  def publish_webhook_event(action, account)
    event_type = WebhookEventPublisher.event_type_for(self, action)
    return unless event_type

    WebhookEventPublisher.publish(
      event_type: event_type,
      account: account,
      payload: {
        "event_type" => event_type,
        "action" => action.to_s,
        "timestamp" => Time.current.iso8601,
        "id" => id,
        "account_id" => account.id,
        "data" => webhook_payload_data
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to publish webhook event for #{self.class.name}##{id} (#{action}): #{e.message}"
    raise e if Auditable.raise_on_failure
  end

  # IMP-dd0305de2799 (D5): audit-row parity is the WRONG bar for a payload
  # leaving the process to a customer-supplied URL. redact_audit_values exists
  # to strip SECRETS (encrypted columns, ALWAYS_REDACTED_ATTRIBUTES,
  # filter_attributes) — it is a no-op for a model with none of those
  # declared, which is exactly Account's situation: no `encrypts`, no
  # `filter_attributes` (ActiveRecord::Base.filter_attributes is empty in this
  # app), so an unfiltered `auditable_attributes` would have shipped tax_id,
  # billing_email, stripe_customer_id/paypal_customer_id,
  # encryption_key_vault_path and the operator-writable settings/metadata
  # jsonb bags to whatever URL an admin configured — at the DEFAULT
  # payload_detail_level ("full"), the one that does not even trim it.
  #
  # So "data" is built from an explicit PER-MODEL ALLOWLIST of attributes the
  # model has reviewed and declared safe to send externally
  # (`webhook_payload_attributes :name, :slug, ...` in the model body), with
  # redact_audit_values still applied as a SECOND pass over that narrowed set
  # — not the only one. A model that declares no allowlist sends identifying
  # fields only (the top-level "id"/"account_id" this payload already
  # carries); neither User nor Account declares one yet, so both currently
  # ship ids-only "data" until someone audits their own column list.
  def webhook_payload_data
    allowed = self.class.webhook_payload_attribute_names
    return {} if allowed.empty?

    redact_audit_values(attributes.slice(*allowed))
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
  # Pre-redaction, kept even though AuditLog now redacts on the way in. It is
  # not redundant: it keeps secret material out of the values this concern
  # hands to log_action in the first place, so a value never exists in an
  # in-memory audit payload it does not need to reach. The seam applies the
  # same rule, and re-running it over an already-masked value is a no-op.
  def redact_audit_values(values)
    Auditable.redact_values(values, self.class, extra_redacted: audit_extra_redactions)
  end

  # Every path that must not let audit_extra_redactions survive past the one
  # write it was set for calls this — see the declaration above for the full
  # list of call sites and why each is needed. A plain nil assignment;
  # idempotent, safe to call whether or not the flag was ever set.
  def clear_audit_extra_redactions
    self.audit_extra_redactions = nil
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
    Auditable.redacted_attribute_names_for(self.class)
  end

  # The model's own filtered-attribute list, applied with the semantics Rails
  # gives it for #inspect: `filter_attributes` entries match attribute names as
  # case-insensitive substrings (or Regexp / Proc), and a Hash value is walked
  # so a secret nested in a JSON column is masked too.
  #
  # This exists because "is it encrypted?" is not the same question as "is it
  # secret?". A column can hold plaintext credential material under a name
  # that merely LOOKS encrypted (Devops::KubernetesCluster#encrypted_kubeconfig
  # and its two node-join tokens), and such a column is invisible to
  # audit_redacted_attribute_names — no `encrypts`, no entry. Honouring
  # `filter_attributes` gives those models one declaration that keeps the value
  # out of the console, the logs and the audit trail alike, so a row written
  # THROUGH THIS CONCERN can never disclose what `inspect` already refuses to
  # print. Auditable is not the only writer of audit_logs — Audit::LoggingService,
  # AuditLogging#resource_attributes_for_logging and 58 direct AuditLog.create!
  # sites all reach the table too. Those are covered as of IMP-01a08809, but NOT
  # by this method: AuditLog#redact_secret_values applies the same rule as the
  # row is written. Read this one as the pre-redaction on Auditable's own path.
  #
  # Source of the list: `self.class.filter_attributes`, which inherits from
  # ActiveRecord::Base.filter_attributes. That base list is EMPTY in this app
  # (asserted in spec/models/concerns/auditable_secret_redaction_spec.rb) even
  # though config.filter_parameters has entries, because the railtie
  # initializer "active_record.set_filter_attributes" merges them only on the
  # :active_record load hook. If that ever changes, every Auditable model would
  # start masking audit values on substrings like "token" / "_key" / "email";
  # the spec is the tripwire, and the answer then is to narrow this to the
  # class's OWN declaration rather than to accept the widened masking.
  def audit_attribute_filter
    Auditable.attribute_filter_for(self.class)
  end

  # Override this method in models to specify WHICH attributes are audited.
  # Secret values are not this method's concern — redact_audit_values runs over
  # its result (and over the update path alike), so an override here cannot
  # reintroduce the disclosure.
  def auditable_attributes
    attributes.except("id", "created_at", "updated_at")
  end
end

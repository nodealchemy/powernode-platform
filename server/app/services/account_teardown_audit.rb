# frozen_string_literal: true

# The audit trail of Account#destroy! (adversarial review #2). The teardown deletes
# every audit row of the account at the end, which used to erase the key revocations
# it had just caused and never recorded the deletion itself.
#
# Platform scope: rows written here have audit_logs.account_id NULL
# (AuditActions::PLATFORM_SCOPED_ACTIONS) and so survive the account. They go into the
# SAME table as every other audit row, i.e. the same global hash chain, because a
# separate table would need its own chain and could not be verified with the rest.
# account_id is part of each row's hash, so a surviving row is never UPDATEd to NULL
# (that would break its integrity_hash): it is re-written as a NEW chained row that
# carries the original's fields in its (hashed) metadata, and the original is deleted.
#
# It runs inside the teardown transaction and FAILS CLOSED: any error propagates, the
# transaction rolls back, and nothing is deleted (no audit means no delete).
# Nothing here records key material: ids and counts only.
class AccountTeardownAudit
  RETAINED_ACTION = "account.teardown_key_audit_retained"
  REVOKED_ACTION = "account.teardown_key_revoked"
  DESTROYED_ACTION = "account.destroyed"
  SOURCE = "system"

  # Key-bearing associations of Account, label => association name. Core registers its own
  # below; an extension registers its (Account.register_teardown_key_source).
  class << self
    def key_sources
      @key_sources ||= {}
    end
  end

  # Names that mark a metadata key as sensitive. Applied to the copied original_metadata on top of the
  # AuditLog redactor, and deliberately broader than it (previews and hints leak key material too).
  SENSITIVE_KEY = /key|secret|token|password|passphrase|credential|private|preview|hint|signature|seed|mnemonic/i

  def initialize(account, actor: nil)
    @account = account
    @actor = actor
  end

  # Before any dependent is destroyed: what is about to go.
  def snapshot!
    @counts = table_counts
    @key_ids = key_ids
    @name_digest = Digest::SHA256.hexdigest(@account.name.to_s)
  end

  # A User, an explicit String label, or (unset) the OS process, so the row is never anonymous.
  def actor_id = @actor.is_a?(User) ? @actor.id : nil

  def actor_label
    case @actor
    when User then "user:#{@actor.id}"
    when String, Symbol then @actor.to_s
    else "process:#{Etc.getlogin || ENV.fetch('USER', 'unknown')}@#{Socket.gethostname}"
    end
  end

  # After the dependents and users are gone, before the account's audit rows are deleted.
  def record!
    retain_key_operation_rows
    record_key_revocations
    record_destroyed
  end

  private

  def table_counts
    @account.class.reflect_on_all_associations
            .select { |r| %i[destroy delete_all nullify].include?(r.options[:dependent]) }
            .reject { |r| %i[users audit_logs].include?(r.name) }
            .each_with_object([]) do |r, counts|
      n = @account.association(r.name).scope.count
      counts << { "table" => r.klass.table_name, "rows" => n } if n.positive?
    rescue StandardError
      next
    end.push({ "table" => "users", "rows" => @account.users.count })
  end

  def key_ids
    self.class.key_sources.each_with_object([]) do |(_label, assoc), out|
      reflection = @account.class.reflect_on_association(assoc)
      next unless reflection

      ids = @account.association(assoc).scope.pluck(:id)
      out << { "model" => reflection.klass.name, "ids" => ids } if ids.any?
    end
  end

  def retain_key_operation_rows
    AuditLog.where(account_id: @account.id).find_each do |row|
      next unless AuditActions.key_operation?(row.action)

      write(
        RETAINED_ACTION, "Account", @account.id,
        {
          "original_id" => row.id, "original_action" => row.action, "original_account_id" => row.account_id,
          "original_integrity_hash" => row.integrity_hash, "original_previous_hash" => row.previous_hash,
          "original_sequence_number" => row.sequence_number,
          "original_user_id" => row.user_id, "original_resource_type" => row.resource_type,
          "original_resource_id" => row.resource_id, "original_created_at" => row.created_at&.iso8601,
          "original_metadata" => scrub(row.metadata)
        }
      )
    end
  end

  def record_key_revocations
    @key_ids.each do |entry|
      entry["ids"].each do |id|
        write(REVOKED_ACTION, entry["model"], id, { "account_id" => @account.id, "actor_id" => actor_id, "actor_label" => actor_label })
      end
    end
  end

  def record_destroyed
    write(
      DESTROYED_ACTION, "Account", @account.id,
      { "account_id" => @account.id, "name_digest" => @name_digest, "actor_id" => actor_id, "actor_label" => actor_label,
        "counts" => @counts, "revoked_records" => @key_ids, "deleted_sequence_range" => deleted_sequence_range },
      severity: "high", risk_level: "high"
    )
  end

  # The global-chain positions the teardown is about to delete, so a verifier can attribute the gap.
  def deleted_sequence_range
    rows = AuditLog.where(account_id: @account.id)
    seqs = rows.where.not(sequence_number: nil)
    { "min" => seqs.minimum(:sequence_number), "max" => seqs.maximum(:sequence_number), "count" => rows.count }
  end

  def scrub(value)
    case value
    when Hash then value.each_with_object({}) { |(k, v), h| h[k] = k.to_s.match?(SENSITIVE_KEY) ? "[FILTERED]" : scrub(v) }
    when Array then value.map { |v| scrub(v) }
    else value
    end
  end

  # create! (never log_action with a rescue): a failure must propagate and abort the teardown.
  def write(action, resource_type, resource_id, metadata, severity: "medium", risk_level: "medium")
    AuditLog.create!(
      action: action, resource_type: resource_type, resource_id: resource_id.to_s, account: nil,
      source: SOURCE, severity: severity, risk_level: risk_level, metadata: metadata
    )
  end
end

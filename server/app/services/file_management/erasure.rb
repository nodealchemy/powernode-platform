# frozen_string_literal: true

module FileManagement
  # GDPR Article 17 erasure of FileManagement::Object rows and their blobs
  # (IMP-d97f6e3bbc2b). One call erases ONE bounded batch of the personal
  # files in +scope+ and tells the caller where to resume; the worker loops
  # on the cursor, so no single HTTP request ever walks a whole account.
  #
  # What one file's erasure is — and the ordering that makes both "a raise
  # leaves no destruction behind" and "a failed blob delete is not counted"
  # hold at once:
  #
  #   1. The referent seam is asked, once per batch and read-only, which ids
  #      it HOLDS (ErasureReferentRegistry.holds). A held file is refused
  #      with the handler's reason and never touched.
  #   2. Each remaining file is erased in its OWN transaction (a savepoint
  #      under an outer one): the seam RELEASES the file (core's chat
  #      attachment nullifies its pointer), the shares are deleted, and the
  #      row is destroyed. The model's after_destroy removes the blob as the
  #      LAST step inside that transaction, in strict mode, so a provider
  #      that returns false (every provider rescues internally and returns
  #      false rather than raising) raises StorageRemovalFailed and the
  #      whole file — row, shares, versions, tags, audit row — rolls back.
  #      It is reported as failed, not counted.
  #   3. A NO ACTION foreign key nobody registered fires at the DELETE
  #      statement, inside the same transaction, and is caught: the file is
  #      reported as held ("referenced_by_restrict_fk"), nothing is lost.
  #
  # Per-file rather than per-batch transactions, deliberately: a batch-wide
  # transaction would widen the one window this ordering cannot close.
  # RESIDUAL WINDOW: the provider has removed the blob and the transaction
  # then fails to commit (the storage-counter write after it, or the commit
  # itself). The row and its shares survive, the blob is gone, and the file
  # is reported as failed for this run. A retry re-selects it and completes,
  # because every provider's delete_file treats a missing blob as success
  # (local/nfs/smb: `return true unless exist?`; s3: delete_object is a
  # no-op on a missing key; gcs: `return true unless gcs_file`; azure: 404
  # is success). Until then the row is a dangling pointer, not retained
  # content.
  #
  # Category policy: only PERSONAL_CATEGORIES are candidates. An allowlist,
  # not a denylist, so a category added later defaults to retained-and-
  # reported rather than destroyed. Everything else in the scope (disk
  # images, SBOM exports, attestation proofs, vendor artifacts, 'system')
  # is counted as retained_count so the caller can see it was left.
  class Erasure
    # The categories a data subject's own activity produces. 'system' and the
    # supply-chain / disk-image categories are platform artifacts.
    PERSONAL_CATEGORIES = %w[user_upload workflow_output ai_generated temp import page_content].freeze

    # Sized against the worker's 30-second per-request client timeout
    # (BackendApiClient / CircuitBreaker): 50 blob deletes at a pessimistic
    # 200 ms each is 10 s, well inside it. A caller may ask for more, up to
    # MAX_BATCH_SIZE.
    DEFAULT_BATCH_SIZE = 50
    MAX_BATCH_SIZE = 200

    # Personal content the destroy's own audit row must not archive — the
    # same hazard Api::V1::Internal::UsersController#delete_settings guards
    # against with audit_extra_redactions.
    AUDIT_REDACTED_FIELDS = %w[
      filename storage_key metadata exif_data dimensions processing_metadata
      checksum_md5 checksum_sha256
    ].freeze

    # failures: [{ id:, kind: 'held' | 'error', reason: }]. 'held' is a
    # policy gap (a referent will not let go) a retry cannot clear; 'error'
    # is operational (storage, an unexpected raise) and a retry may.
    Result = Struct.new(:erased_count, :failures, :retained_count, :remaining, :cursor, keyword_init: true) do
      def held
        failures.select { |f| f[:kind] == "held" }
      end

      def errors
        failures.select { |f| f[:kind] == "error" }
      end

      # The internal API payload both delete_files actions render.
      # `erased: true` means an erasure path ran — an older worker build
      # branches on `erased == false` to mean "no path exists".
      def to_h
        {
          count: erased_count,
          erased: true,
          failed: failures,
          held: held.size,
          errors: errors.size,
          retained_platform_artifacts: retained_count,
          remaining: remaining,
          cursor: cursor
        }
      end

      def audit_metadata
        {
          records_deleted: erased_count,
          erased: true,
          held: held.size,
          errors: errors.size,
          retained_platform_artifacts: retained_count,
          remaining: remaining
        }
      end

      def message
        "Erased #{erased_count} file records (#{held.size} held, #{errors.size} failed, " \
          "#{retained_count} platform artifacts retained, #{remaining} remaining)"
      end
    end

    def self.call(scope:, batch_size: nil, after_id: nil)
      new(scope: scope, batch_size: batch_size, after_id: after_id).call
    end

    def self.batch_size_for(value)
      size = value.to_i
      return DEFAULT_BATCH_SIZE unless size.positive?

      [ size, MAX_BATCH_SIZE ].min
    end

    UUID_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    # A cursor is one of this service's own ids echoed back. Anything else
    # would reach Postgres as an invalid uuid literal and 500 the request,
    # which on the termination path reverts the whole termination.
    def self.valid_cursor?(value)
      value.blank? || UUID_PATTERN.match?(value.to_s)
    end

    def initialize(scope:, batch_size: nil, after_id: nil)
      raise ArgumentError, "after_id must be a UUID cursor" unless self.class.valid_cursor?(after_id)

      @scope = scope
      @batch_size = self.class.batch_size_for(batch_size)
      @after_id = after_id.presence
    end

    def call
      batch = candidates.limit(@batch_size).includes(:storage).to_a
      held = ErasureReferentRegistry.holds(batch.map(&:id))

      failures = []
      erased_count = 0

      batch.each do |file|
        if (reason = held[file.id])
          failures << failure(file, "held", reason)
          next
        end

        outcome = erase_one(file)
        if outcome.nil?
          erased_count += 1
        else
          failures << outcome
        end
      end

      cursor = batch.last&.id || @after_id
      remaining = cursor ? candidates.where("file_objects.id > ?", cursor).count : 0

      Result.new(
        erased_count: erased_count,
        failures: failures,
        retained_count: retained_count,
        remaining: remaining,
        cursor: cursor
      )
    end

    private

    # Personal files in the scope, in id order (UUIDv7 — time-ordered), past
    # the cursor. The cursor always advances past a failed file, so a caller
    # looping on `remaining` terminates.
    def candidates
      relation = @scope.where(category: PERSONAL_CATEGORIES).order(:id)
      relation = relation.where("file_objects.id > ?", @after_id) if @after_id
      relation
    end

    def retained_count
      @scope.where("file_objects.category IS NULL OR file_objects.category NOT IN (?)", PERSONAL_CATEGORIES).count
    end

    # nil on success; a failure hash otherwise. Nothing escapes: one bad file
    # must not end the batch.
    #
    # Shares, versions and processing jobs are deleted with delete_all rather
    # than left to the destroy's `dependent: :destroy` cascade: Version and
    # ProcessingJob are Auditable too, and their own "deleted" audit rows
    # would archive the version's storage_key (which embeds the filename),
    # change_description and metadata, and the job's parameters, result
    # and error details — personal content the file's redacted row keeps
    # out. Nothing else references those rows. Tags keep the cascade (their
    # after_destroy maintains the tag counter, and a tag row holds no
    # content).
    def erase_one(file)
      FileManagement::Object.transaction(requires_new: true) do
        ErasureReferentRegistry.release(file)
        file.shares.delete_all
        file.versions.delete_all
        file.processing_jobs.delete_all
        file.strict_storage_removal = true
        file.audit_extra_redactions = AUDIT_REDACTED_FIELDS
        file.destroy!
      end
      nil
    rescue FileManagement::Object::StorageRemovalFailed => e
      Rails.logger.error "[FileManagement::Erasure] #{file.id}: #{e.message}"
      failure(file, "error", "storage_removal_failed")
    rescue ActiveRecord::InvalidForeignKey => e
      Rails.logger.warn "[FileManagement::Erasure] #{file.id} is referenced by an unregistered restrict FK: #{e.message}"
      failure(file, "held", "referenced_by_restrict_fk")
    rescue StandardError => e
      Rails.logger.error "[FileManagement::Erasure] #{file.id}: #{e.class}: #{e.message}"
      failure(file, "error", e.class.name)
    end

    def failure(file, kind, reason)
      { id: file.id, kind: kind, reason: reason }
    end
  end
end

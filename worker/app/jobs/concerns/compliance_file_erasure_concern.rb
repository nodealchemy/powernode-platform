# frozen_string_literal: true

# Walks the server's batched files erasure (FileManagement::Erasure behind
# DELETE /api/v1/internal/users/:id/files and
# DELETE /api/v1/internal/accounts/:id/files, IMP-d97f6e3bbc2b). Each
# request erases one bounded batch and answers with `remaining` and a
# `cursor`; this loops on the cursor so no single request walks a large
# account, and no account is too large to finish. Shared by
# Compliance::DataDeletionJob and Compliance::AccountTerminationJob, which
# differ only in how they report the outcome.
module ComplianceFileErasureConcern
  extend ActiveSupport::Concern

  # 10_000 batches at the server's default of 50 files is half a million
  # files — a ceiling against a cursor that stops advancing, not a budget.
  MAX_FILE_ERASURE_BATCHES = 10_000

  # How many failed files a failure summary names before it falls back to
  # a count. A failure can list a whole batch, and the summary lands in an
  # exception message, a termination_log entry and an error_message column.
  FAILURE_SAMPLE_SIZE = 10

  # Returns a symbol-keyed summary over every batch:
  #   { count:, failed: [ { 'id' =>, 'kind' => 'held' | 'error', 'reason' => } ],
  #     held: [...], errors: [...], retained_platform_artifacts:, batches:,
  #     aborted_remaining: }
  # or, from an OLDER server build that still reports `erased: false` (the
  # accounts route did, before the erasure path existed), that response's
  # data untouched ({ 'erased' => false, 'reason' => ... }) so the caller can
  # keep recording the gap the way it did before.
  #
  # Stops walking after a batch in which NOTHING was erased and every
  # failure was operational: the store is down, and every further batch
  # would fail the same way while growing the failure list. The files past
  # the cursor are reported in `aborted_remaining`, never as erased.
  def erase_files_in_batches(path)
    totals = { count: 0, failed: [], retained_platform_artifacts: 0, batches: 0, aborted_remaining: 0 }
    after_id = nil

    loop do
      response = after_id ? api_client.delete(path, { after_id: after_id }) : api_client.delete(path)
      data = response['data'] || {}
      return data if data['erased'] == false

      failed = Array(data['failed'])
      totals[:count] += data['count'].to_i
      totals[:failed].concat(failed)
      totals[:retained_platform_artifacts] = data['retained_platform_artifacts'].to_i
      totals[:batches] += 1

      remaining = data['remaining'].to_i
      cursor = data['cursor']
      break if remaining.zero? || cursor.blank?

      if data['count'].to_i.zero? && failed.any? && failed.all? { |f| f['kind'] != 'held' }
        totals[:aborted_remaining] = remaining
        break
      end

      if totals[:batches] >= MAX_FILE_ERASURE_BATCHES
        raise "File erasure at #{path} did not finish within #{MAX_FILE_ERASURE_BATCHES} batches " \
              "(#{remaining} remaining)"
      end

      after_id = cursor
    end

    totals[:held] = totals[:failed].select { |f| f['kind'] == 'held' }
    totals[:errors] = totals[:failed].reject { |f| f['kind'] == 'held' }
    totals
  end

  # One bounded line naming the first FAILURE_SAMPLE_SIZE files the server
  # could not erase, then a count. Ids only — never a filename.
  def file_erasure_failure_summary(failures)
    sample = failures.first(FAILURE_SAMPLE_SIZE).map { |f| "#{f['id']} (#{f['kind']}: #{f['reason']})" }
    rest = failures.size - sample.size
    rest.positive? ? "#{sample.join(', ')}, and #{rest} more" : sample.join(', ')
  end
end

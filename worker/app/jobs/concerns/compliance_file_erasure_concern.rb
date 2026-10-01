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

  # The server stopped answering (an ApiError) AFTER at least one batch had
  # already erased files. Distinct from an error on the first request so a
  # caller can tell "this server has no erasure route" from "the erasure
  # was interrupted part way" — the latter must never be recorded as a
  # skip. Carries the totals so far and the error that stopped the walk.
  class FileErasureInterrupted < StandardError
    attr_reader :totals, :api_error

    def initialize(totals, api_error)
      @totals = totals
      @api_error = api_error
      super("file erasure interrupted after #{totals[:count]} file(s) were erased: #{api_error.message}")
    end
  end

  # Returns a symbol-keyed summary over every batch:
  #   { count:, failed: [ { 'id' =>, 'kind' => 'held' | 'error', 'reason' => } ],
  #     held: [...], errors: [...], retained_platform_artifacts:, batches: }
  # or, from an OLDER server build that still reports `erased: false` (the
  # accounts route did, before the erasure path existed), that response's
  # data untouched ({ 'erased' => false, 'reason' => ... }) so the caller can
  # keep recording the gap the way it did before.
  #
  # The walk does NOT stop on a batch in which every file failed: the
  # server advances the cursor past failed files and short-circuits a
  # storage that already failed inside a call (one provider attempt per
  # dead store per batch), so files on a healthy store behind a dead one
  # are still reached, `remaining` strictly decreases, and the ceiling
  # above bounds everything-dead.
  def erase_files_in_batches(path)
    totals = { count: 0, failed: [], retained_platform_artifacts: 0, batches: 0 }
    after_id = nil

    loop do
      response = begin
        after_id ? api_client.delete(path, { after_id: after_id }) : api_client.delete(path)
      rescue BackendApiClient::ApiError => e
        raise if totals[:batches].zero?

        raise FileErasureInterrupted.new(finish_file_erasure_totals(totals), e)
      end
      data = response['data'] || {}
      return data if data['erased'] == false

      totals[:count] += data['count'].to_i
      totals[:failed].concat(Array(data['failed']))
      totals[:retained_platform_artifacts] = data['retained_platform_artifacts'].to_i
      totals[:batches] += 1

      remaining = data['remaining'].to_i
      cursor = data['cursor']
      break if remaining.zero? || cursor.blank?

      if totals[:batches] >= MAX_FILE_ERASURE_BATCHES
        raise "File erasure at #{path} did not finish within #{MAX_FILE_ERASURE_BATCHES} batches " \
              "(#{remaining} remaining)"
      end

      after_id = cursor
    end

    finish_file_erasure_totals(totals)
  end

  # One bounded line naming the first FAILURE_SAMPLE_SIZE files the server
  # could not erase, then a count. Ids only — never a filename.
  def file_erasure_failure_summary(failures)
    sample = failures.first(FAILURE_SAMPLE_SIZE).map { |f| "#{f['id']} (#{f['kind']}: #{f['reason']})" }
    rest = failures.size - sample.size
    rest.positive? ? "#{sample.join(', ')}, and #{rest} more" : sample.join(', ')
  end

  private

  def finish_file_erasure_totals(totals)
    totals[:held] = totals[:failed].select { |f| f['kind'] == 'held' }
    totals[:errors] = totals[:failed].reject { |f| f['kind'] == 'held' }
    totals
  end
end

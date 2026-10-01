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

  # Returns a symbol-keyed summary over every batch:
  #   { count:, failed: [ { 'id' =>, 'kind' => 'held' | 'error', 'reason' => } ],
  #     held: [...], errors: [...], retained_platform_artifacts:, batches: }
  # or, from an OLDER server build that still reports `erased: false`, that
  # response's data untouched ({ 'erased' => false, 'reason' => ... }) so the
  # caller can keep recording the gap the way it did before this path existed.
  def erase_files_in_batches(path)
    totals = { count: 0, failed: [], retained_platform_artifacts: 0, batches: 0 }
    after_id = nil

    loop do
      response = after_id ? api_client.delete(path, { after_id: after_id }) : api_client.delete(path)
      data = response['data'] || {}
      return data if data['erased'] == false

      totals[:count] += data['count'].to_i
      totals[:failed].concat(Array(data['failed']))
      totals[:retained_platform_artifacts] = data['retained_platform_artifacts'].to_i
      totals[:batches] += 1

      cursor = data['cursor']
      break if data['remaining'].to_i.zero? || cursor.blank?
      if totals[:batches] >= MAX_FILE_ERASURE_BATCHES
        raise "File erasure at #{path} did not finish within #{MAX_FILE_ERASURE_BATCHES} batches " \
              "(#{data['remaining']} remaining)"
      end

      after_id = cursor
    end

    totals[:held] = totals[:failed].select { |f| f['kind'] == 'held' }
    totals[:errors] = totals[:failed].reject { |f| f['kind'] == 'held' }
    totals
  end

  # One line naming every file the server could not erase, for an error
  # message or a log entry. Ids only — never a filename.
  def file_erasure_failure_summary(failures)
    failures.map { |f| "#{f['id']} (#{f['kind']}: #{f['reason']})" }.join(', ')
  end
end

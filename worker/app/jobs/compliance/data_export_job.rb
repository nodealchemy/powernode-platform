# frozen_string_literal: true

module Compliance
  # Job for processing GDPR data export requests
  class DataExportJob < BaseJob
    sidekiq_options queue: :compliance

    # Where this job writes an archive on the worker host. The archive is the
    # subject's full personal-data export, so whatever writes it here owns
    # removing it: the server never sees this directory (it deletes only its
    # own filesystem), see .discard_archive.
    EXPORT_DIR_NAME = 'powernode_exports'

    def self.export_dir
      File.join(Dir.tmpdir, EXPORT_DIR_NAME)
    end

    # Removes an archive this job wrote. The path arrives from the server's
    # row, so it is not trusted to name a file this job owns, and the worker may
    # run as root, so containment is decided on REAL paths: expand_path does not
    # resolve a symlink, and a linked subdirectory (or a squatted export
    # directory in the shared tmp) would otherwise point the delete anywhere.
    #
    #   - the export directory must be a real directory owned by this process's
    #     uid with no group/other write bit, else nothing is deleted;
    #   - the archive's parent, resolved, must be the export directory or inside
    #     it (compared with a trailing separator, so a sibling sharing the
    #     prefix is outside);
    #   - the archive itself must be a regular file, never a symlink.
    #
    # Returns :removed, :missing, :outside_export_dir, :symlink,
    # :unsafe_export_dir or :failed; never raises, so a cleanup problem cannot
    # fail the caller.
    def self.discard_archive(path)
      return :missing if path.blank?

      root = export_dir
      return :missing unless File.exist?(root)
      return :unsafe_export_dir unless trusted_export_dir?(root)

      expanded = File.expand_path(path.to_s)
      real_parent = File.realpath(File.dirname(expanded))
      real_root = File.realpath(root)
      return :outside_export_dir unless "#{real_parent}#{File::SEPARATOR}".start_with?("#{real_root}#{File::SEPARATOR}")

      target = File.join(real_parent, File.basename(expanded))
      stat = File.lstat(target)
      return :symlink if stat.symlink?
      return :outside_export_dir unless stat.file?

      File.delete(target)
      :removed
    rescue Errno::ENOENT
      :missing
    rescue SystemCallError
      :failed
    end

    # A real (not linked) directory this process owns that nobody else can
    # write into: the only kind of directory a delete driven by a path from
    # elsewhere is safe inside, and one nobody else can have planted links in.
    def self.trusted_export_dir?(dir)
      stat = File.lstat(dir)
      stat.directory? && stat.uid == Process.euid && (stat.mode & 0o022).zero?
    end

    # IMP-0310a1351dab BLOCKER: this job could never finish before this fix.
    # Two independent breaks, both against
    # Api::V1::Internal::DataExportRequestsController:
    #   1. `show` nests the record under `data.data_export_request` (see
    #      DataExportRequestsController#show -> serialize_request), not
    #      `data` directly — `response['data']['status']` always read nil,
    #      so the `unless export_request['status'] == 'pending'` guard
    #      always took the "skip" branch and returned without doing
    #      anything, on every single invocation, for every export ever
    #      created (self-service or termination-linked).
    #   2. `update` dispatches on `params[:action_type]`
    #      ('start'/'complete'/'fail'/'expire') — see
    #      DataExportRequestsController#update — and every PATCH this job
    #      sent carried a bare status/field payload with no action_type,
    #      which falls through to the generic branch (`@export_request
    #      .update(export_request_update_params)`, permitting only
    #      `metadata:`) and would have raised ActiveRecord::RecordInvalid or
    #      silently updated nothing, had the job ever reached a PATCH call
    #      at all (it never did, because of #1).
    def execute(export_request_id)
      log_info "Processing data export request: #{export_request_id}"

      response = api_client.get("/api/v1/internal/data_export_requests/#{export_request_id}")

      unless response['success']
        raise "Failed to fetch export request: #{response['error']}"
      end

      export_request = response.dig('data', 'data_export_request')
      unless export_request
        raise "Malformed response fetching export request #{export_request_id}: " \
              "expected data.data_export_request, got #{response['data'].inspect}"
      end

      unless export_request['status'] == 'pending'
        log_info "Export request #{export_request_id} is not pending, skipping"
        return
      end

      start_response = api_client.patch(
        "/api/v1/internal/data_export_requests/#{export_request_id}",
        { action_type: 'start' }
      )
      unless start_response['success']
        raise "Failed to start export request #{export_request_id}: #{start_response['error']}"
      end

      file_path = nil
      begin
        export_data = gather_export_data(export_request)
        file_path, file_size = write_export_file(export_request, export_data)

        # The server generates and stores its OWN download_token on
        # complete_export (DataExportRequestsController#complete_export) —
        # it does not read one from this payload. `serialize_request`'s
        # non-`include_details` shape (returned here) does not expose the
        # generated token either, so this job cannot learn the real one from
        # this response. notify_user_export_ready therefore does not
        # currently carry a working download link — a separate,
        # pre-existing gap this fix does not close (out of scope for
        # IMP-0310a1351dab's FK/gate/pipeline fixes; flagged, not silently
        # papered over with a token that would not match what is stored).
        complete_response = api_client.patch(
          "/api/v1/internal/data_export_requests/#{export_request_id}",
          { action_type: 'complete', file_path: file_path, file_size_bytes: file_size }
        )
        unless complete_response['success']
          raise "Failed to complete export request #{export_request_id}: #{complete_response['error']}"
        end

        log_export_outcome(export_request_id, export_data.dig(:export_info, :manifest) || {})

        notify_user_export_ready(export_request, nil)
      rescue => e
        log_error "Data export failed: #{e.message}"
        discard_unrecorded_archive(file_path)

        api_client.patch(
          "/api/v1/internal/data_export_requests/#{export_request_id}",
          { action_type: 'fail', error_message: e.message }
        )

        raise
      end
    end

    private

    # An archive written by a run that then failed is on no row (the complete
    # write never landed, or its response was refused), so nothing else will
    # ever remove it, and a retry writes a fresh one.
    def discard_unrecorded_archive(file_path)
      return if file_path.blank?

      result = self.class.discard_archive(file_path)
      log_warn "Could not remove the archive of a failed data export (#{result})" if result == :failed
    end

    def gather_export_data(export_request)
      user_id = export_request['user_id']
      account_id = export_request['account_id']
      data_types = export_request['include_data_types'] || []
      excluded = export_request['exclude_data_types'] || []

      manifest = {}
      export_data = {
        export_info: {
          generated_at: Time.current.iso8601,
          user_id: user_id,
          account_id: account_id,
          format: export_request['format'],
          # Per data type: what the archive actually holds. `exported` with a
          # count, or why the section is absent — `unavailable` (no provider
          # installed), `not_exportable` (no export path exists), `failed`.
          # An empty section is never left to read as "the subject has none".
          manifest: manifest
        }
      }

      (data_types - excluded).each do |data_type|
        section, entry = fetch_data_type(data_type, user_id, account_id)
        export_data[data_type] = section
        manifest[data_type] = entry
      end

      export_data
    end

    # Returns [section, manifest_entry].
    def fetch_data_type(data_type, user_id, account_id)
      path, params = export_path(data_type, user_id, account_id)
      unless path
        return [{ note: "Data type '#{data_type}' is not exportable" },
                { status: 'not_exportable' }]
      end

      response = api_client.get(path, params)
      data = response['data']
      meta = response['meta'] || {}

      if response['success'] == false || data.nil?
        log_warn "Failed to fetch #{data_type}: backend answered without data"
        [{ error: "Failed to fetch #{data_type}" }, { status: 'failed' }]
      elsif meta['available'] == false
        [data, { status: 'unavailable', reason: meta['reason'] }]
      else
        [data, { status: 'exported', count: data.is_a?(Array) ? data.size : 1 }]
      end
    rescue => e
      log_warn "Failed to fetch #{data_type}: #{e.message}"
      [{ error: "Failed to fetch #{data_type}" }, { status: 'failed' }]
    end

    def export_path(data_type, user_id, account_id)
      case data_type
      when 'profile' then ["/api/v1/internal/users/#{user_id}/export/profile", {}]
      when 'audit_logs' then ["/api/v1/internal/users/#{user_id}/export/audit_logs", {}]
      when 'consents' then ["/api/v1/internal/users/#{user_id}/export/consents", {}]
      when 'payments' then ["/api/v1/internal/accounts/#{account_id}/export/payments", {}]
      when 'invoices' then ["/api/v1/internal/accounts/#{account_id}/export/invoices", {}]
      when 'subscriptions' then ["/api/v1/internal/accounts/#{account_id}/export/subscriptions", {}]
      # The subject's own files in their account (account_id + uploaded_by_id).
      when 'files' then ["/api/v1/internal/accounts/#{account_id}/export/files", { user_id: user_id }]
      end
    end

    # The completion line carries the per-type counts, and anything the
    # archive does NOT hold is warned about by name — "completed successfully"
    # alone read the same whether the archive held the subject's data or
    # nothing at all.
    def log_export_outcome(export_request_id, manifest)
      summary = manifest.map do |type, entry|
        entry[:status] == 'exported' ? "#{type}=#{entry[:count]}" : "#{type}=#{entry[:status]}"
      end
      log_info "Data export #{export_request_id} completed: #{summary.join(' ')}"

      missing = manifest.reject { |_type, entry| entry[:status] == 'exported' }
      return if missing.empty?

      log_warn "Data export #{export_request_id} archive omits " \
               "#{missing.map { |type, entry| "#{type} (#{entry[:status]})" }.join(', ')}"
    end

    def write_export_file(export_request, data)
      export_dir = self.class.export_dir
      # 0700: the archive is the subject's full personal-data export, and
      # .discard_archive only ever deletes inside a directory nobody else
      # can write into.
      FileUtils.mkdir_p(export_dir, mode: 0o700)

      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      user_id = export_request['user_id']
      filename = "export_#{user_id}_#{timestamp}"

      case export_request['format']
      when 'json'
        file_path = File.join(export_dir, "#{filename}.json")
        File.write(file_path, JSON.pretty_generate(data))
      when 'csv'
        file_path = write_csv_export(export_dir, filename, data)
      when 'zip'
        file_path = write_zip_export(export_dir, filename, data)
      else
        file_path = File.join(export_dir, "#{filename}.json")
        File.write(file_path, JSON.pretty_generate(data))
      end

      [file_path, File.size(file_path)]
    end

    def write_csv_export(export_dir, filename, data)
      require 'csv'
      require 'zip'

      csv_dir = File.join(export_dir, filename)
      FileUtils.mkdir_p(csv_dir)

      data.each do |key, value|
        next unless value.is_a?(Array) && value.any? && value.first.is_a?(Hash)

        csv_path = File.join(csv_dir, "#{key}.csv")
        CSV.open(csv_path, 'w') do |csv|
          csv << value.first.keys
          value.each { |row| csv << row.values }
        end
      end

      # Create zip
      zip_path = File.join(export_dir, "#{filename}.zip")
      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        Dir[File.join(csv_dir, '*.csv')].each do |file|
          zipfile.add(File.basename(file), file)
        end
      end

      FileUtils.rm_rf(csv_dir)
      zip_path
    end

    def write_zip_export(export_dir, filename, data)
      require 'zip'

      json_path = File.join(export_dir, "#{filename}.json")
      File.write(json_path, JSON.pretty_generate(data))

      zip_path = File.join(export_dir, "#{filename}.zip")
      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        zipfile.add("#{filename}.json", json_path)
      end

      FileUtils.rm(json_path)
      zip_path
    end

    def notify_user_export_ready(export_request, download_token)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          user_id: export_request['user_id'],
          type: 'data_export_ready',
          data: {
            export_id: export_request['id'],
            download_token: download_token,
            expires_at: 7.days.from_now.iso8601
          }
        }
      )
    rescue => e
      log_warn "Failed to send export notification: #{e.message}"
    end
  end
end

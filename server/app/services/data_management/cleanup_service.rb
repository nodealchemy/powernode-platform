# frozen_string_literal: true

module DataManagement
  class CleanupService
    include ActiveModel::Model

    class << self
      def get_cleanup_stats
        {
          audit_logs: {
            total_count: AuditLog.count,
            old_count: AuditLog.where("created_at < ?", 90.days.ago).count,
            estimated_size: estimate_audit_logs_size,
            oldest_record: AuditLog.minimum(:created_at)&.iso8601
          },
          sessions: {
            total_count: get_total_sessions_count,
            expired_count: get_expired_sessions_count,
            estimated_size: estimate_sessions_size
          },
          temp_files: {
            count: count_temp_files,
            size: temp_files_size,
            size_human: format_file_size(temp_files_size)
          },
          cache: {
            size: get_cache_size,
            size_human: format_file_size(get_cache_size),
            keys_count: get_cache_keys_count
          },
          database: {
            size: get_database_size,
            size_human: format_file_size(get_database_size),
            vacuum_needed: vacuum_needed?
          }
        }
      end

      def cleanup_audit_logs(days_old = 90)
        cutoff_date = days_old.days.ago

        old_logs = AuditLog.where("created_at < ?", cutoff_date)
        count = old_logs.count

        if count > 0
          old_logs.delete_all
          Rails.logger.info "Cleaned up #{count} audit logs older than #{days_old} days"
        end

        {
          cleaned_count: count,
          cutoff_date: cutoff_date.iso8601,
          remaining_count: AuditLog.count
        }
      rescue => e
        Rails.logger.error "Failed to cleanup audit logs: #{e.message}"
        { error: e.message, cleaned_count: 0 }
      end

      def cleanup_expired_sessions
        cleaned_count = 0

        begin
          # Clean up ActionCable connections
          cleaned_count += cleanup_action_cable_sessions

          # Clean up Sidekiq sessions if applicable
          cleaned_count += cleanup_sidekiq_sessions

          # Clean up any custom session stores
          cleaned_count += cleanup_custom_sessions

          Rails.logger.info "Cleaned up #{cleaned_count} expired sessions"
        rescue => e
          Rails.logger.error "Failed to cleanup sessions: #{e.message}"
          return { error: e.message, cleaned_count: 0 }
        end

        {
          cleaned_count: cleaned_count,
          remaining_count: get_total_sessions_count
        }
      end

      def cleanup_temp_files
        temp_dirs = [
          Rails.root.join("tmp"),
          Rails.root.join("storage", "tmp"),
          Rails.root.join("public", "uploads", "tmp")
        ]

        cleaned_count = 0
        cleaned_size = 0

        temp_dirs.each do |dir|
          next unless Dir.exist?(dir)

          Dir.glob(File.join(dir, "**", "*")).each do |file|
            next unless File.file?(file)
            next unless temp_file?(file)

            begin
              file_size = File.size(file)
              File.delete(file)
              cleaned_count += 1
              cleaned_size += file_size
            rescue => e
              Rails.logger.warn "Failed to delete temp file #{file}: #{e.message}"
            end
          end
        end

        Rails.logger.info "Cleaned up #{cleaned_count} temporary files (#{format_file_size(cleaned_size)})"

        {
          cleaned_count: cleaned_count,
          cleaned_size: cleaned_size,
          cleaned_size_human: format_file_size(cleaned_size)
        }
      rescue => e
        Rails.logger.error "Failed to cleanup temp files: #{e.message}"
        { error: e.message, cleaned_count: 0, cleaned_size: 0 }
      end

      def clear_application_cache
        cleared_entries = 0

        begin
          # Clear Rails cache
          if Rails.cache.respond_to?(:clear)
            Rails.cache.clear
            cleared_entries += get_cache_keys_count
          end

          # Clear any custom caches
          cleared_entries += clear_custom_caches

          Rails.logger.info "Cleared #{cleared_entries} cache entries"
        rescue => e
          Rails.logger.error "Failed to clear cache: #{e.message}"
          return { error: e.message, cleared_entries: 0 }
        end

        {
          cleared_entries: cleared_entries,
          cache_size_after: get_cache_size
        }
      end

      def vacuum_database
        begin
          ActiveRecord::Base.connection.execute("VACUUM ANALYZE")
          Rails.logger.info "Database vacuum completed"
          { success: true, message: "Database vacuum completed" }
        rescue => e
          Rails.logger.error "Database vacuum failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      def reindex_database
        begin
          ActiveRecord::Base.connection.execute("REINDEX DATABASE powernode_development")
          Rails.logger.info "Database reindex completed"
          { success: true, message: "Database reindex completed" }
        rescue => e
          Rails.logger.error "Database reindex failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      private

      def estimate_audit_logs_size
        # Rough estimation: average 500 bytes per audit log
        AuditLog.count * 500
      end

      def get_total_sessions_count
        # This would need to be implemented based on your session store
        0
      end

      def get_expired_sessions_count
        # This would need to be implemented based on your session store
        0
      end

      def estimate_sessions_size
        # Rough estimation based on session count
        get_total_sessions_count * 200
      end

      def count_temp_files
        temp_dirs = [
          Rails.root.join("tmp"),
          Rails.root.join("storage", "tmp"),
          Rails.root.join("public", "uploads", "tmp")
        ]

        count = 0
        temp_dirs.each do |dir|
          next unless Dir.exist?(dir)
          count += Dir.glob(File.join(dir, "**", "*")).count { |f| File.file?(f) && temp_file?(f) }
        end
        count
      rescue
        0
      end

      def temp_files_size
        temp_dirs = [
          Rails.root.join("tmp"),
          Rails.root.join("storage", "tmp"),
          Rails.root.join("public", "uploads", "tmp")
        ]

        size = 0
        temp_dirs.each do |dir|
          next unless Dir.exist?(dir)

          Dir.glob(File.join(dir, "**", "*")).each do |file|
            next unless File.file?(file) && temp_file?(file)
            size += File.size(file) rescue 0
          end
        end
        size
      rescue
        0
      end

      def temp_file?(file_path)
        # Consider files older than 1 day as temp files that can be cleaned
        File.mtime(file_path) < 1.day.ago
      rescue
        false
      end

      def get_cache_size
        # This would need to be implemented based on your cache store
        cache_dir = Rails.root.join("tmp", "cache")
        return 0 unless Dir.exist?(cache_dir)

        Dir.glob(File.join(cache_dir, "**", "*")).sum do |file|
          File.file?(file) ? File.size(file) : 0
        end
      rescue
        0
      end

      def get_cache_keys_count
        # This would need to be implemented based on your cache store
        cache_dir = Rails.root.join("tmp", "cache")
        return 0 unless Dir.exist?(cache_dir)

        Dir.glob(File.join(cache_dir, "**", "*")).count { |f| File.file?(f) }
      rescue
        0
      end

      def get_database_size
        begin
          result = ActiveRecord::Base.connection.execute(
            "SELECT pg_database_size(current_database())"
          )
          result.first["pg_database_size"].to_i
        rescue
          0
        end
      end

      def vacuum_needed?
        begin
          # Check if any tables have significant dead tuples
          result = ActiveRecord::Base.connection.execute(<<~SQL)
            SELECT schemaname, tablename, n_dead_tup, n_live_tup,
                   CASE WHEN n_live_tup > 0
                        THEN (n_dead_tup::float / n_live_tup::float)
                        ELSE 0
                   END as dead_ratio
            FROM pg_stat_user_tables
            WHERE n_dead_tup > 1000
            ORDER BY dead_ratio DESC
            LIMIT 1
          SQL

          result.any? { |row| row["dead_ratio"].to_f > 0.1 }
        rescue
          false
        end
      end

      def cleanup_action_cable_sessions
        # Implement ActionCable session cleanup if needed
        0
      end

      def cleanup_sidekiq_sessions
        # Implement Sidekiq session cleanup if needed
        0
      end

      def cleanup_custom_sessions
        # Implement any custom session store cleanup
        0
      end

      def clear_custom_caches
        # Clear any custom application caches
        0
      end

      def format_file_size(bytes)
        return "0 B" if bytes.nil? || bytes.zero?

        units = ["B", "KB", "MB", "GB", "TB"]
        base = 1024
        exp = (Math.log(bytes) / Math.log(base)).floor
        exp = units.length - 1 if exp >= units.length

        formatted = (bytes.to_f / (base ** exp)).round(2)
        "#{formatted} #{units[exp]}"
      end
    end
  end
end

# Backwards compatibility alias

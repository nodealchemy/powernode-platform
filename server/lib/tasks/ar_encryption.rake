# frozen_string_literal: true

# ActiveRecord encryption key rotation tasks.
#
# Workflow (production):
#   1. Generate new keys. Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY (and
#      _DETERMINISTIC_KEY) env vars to the comma-separated form "OLD,NEW".
#      Rails 8's KeyProvider#encryption_key returns @keys.LAST — so NEW
#      MUST be LAST for new writes. Reads try all entries.
#   2. Restart backend.
#   3. Run `bin/rails ar_encryption:re_encrypt_all` — re-saves every row
#      with `encrypts` declarations through proper setters + forced
#      dirty-tracking, so each encrypted column gets rewritten under NEW.
#   4. Set env back to just "NEW"; restart. OLD is no longer trusted.
#
# Forced dirty-tracking is mandatory: setting an encrypted attribute to
# its current decrypted value doesn't mark the column dirty (value
# unchanged → Rails skips the write). The task calls
# `record.send("#{attr}_will_change!")` explicitly to force re-encryption.
#
# CRITICAL: exception details are NEVER printed to stdout/stderr because
# ActiveRecord encryption exception messages can include the encryption
# Context object via Ruby's default NoMethodError#message (which calls
# inspect on the receiver). Failure detail goes to /tmp/ar-reencrypt-
# errors-<pid>.log mode 600.
namespace :ar_encryption do
  ENCRYPTED_MODELS = ->() {
    ActiveRecord::Base.descendants.select do |klass|
      klass.abstract_class? ? false : klass.respond_to?(:encrypted_attributes) && klass.encrypted_attributes.present?
    end.reject { |k| k.table_exists? == false }
  }

  desc "Re-encrypt every record with `encrypts` declarations under the current primary key"
  task re_encrypt_all: :environment do
    Rails.application.eager_load!

    err_log = "/tmp/ar-reencrypt-errors-#{Process.pid}.log"
    File.write(err_log, "")
    File.chmod(0o600, err_log)

    safe_log_error = ->(record_id, klass, ex) {
      # Write to private file, NEVER to stdout/stderr. We log class +
      # backtrace top frame only. The exception's `message` is NEVER
      # captured because Ruby includes inspect-of-receiver in some
      # exception types (NoMethodError), which would leak key material
      # if the receiver is an Encryption::Context.
      File.open(err_log, "a") do |f|
        f.puts "[#{Time.now.utc.iso8601}] klass=#{klass.name} record_id=#{record_id} " \
               "exception_class=#{ex.class.name} top_frame=#{ex.backtrace&.first}"
      end
    }

    models = ENCRYPTED_MODELS.call
    if models.empty?
      puts "No models with `encrypts` declarations found."
      next
    end

    puts "Re-encrypting #{models.size} model(s):"
    models.each do |klass|
      puts "  #{klass.name.ljust(48)} attrs=#{klass.encrypted_attributes.to_a.inspect}  rows=#{klass.count}"
    end
    puts

    grand_total = 0
    grand_errors = 0
    models.each do |klass|
      puts "── #{klass.name} ──"
      processed = 0
      errors    = 0
      klass.unscoped.in_batches(of: 200) do |relation|
        relation.each do |record|
          rid = (record.id rescue "?")
          begin
            # Re-set every encrypted attribute through the proper setter,
            # then FORCE dirty-tracking. Without the explicit will_change!
            # call, Rails sees `attr = current_value_we_just_read` as a
            # no-op and skips the write — so the underlying ciphertext
            # never gets rewritten with the new key. Plain `encrypts`
            # attributes hit this; pepper-layered attributes don't,
            # because the pepper layer's random IV produces a different
            # serialized value each call.
            klass.encrypted_attributes.each do |attr|
              current = record.public_send(attr)
              next if current.nil?
              record.public_send("#{attr}=", current)
              record.send("#{attr}_will_change!")
            end
            if record.save(validate: false, touch: false)
              processed += 1
            else
              errors += 1
              # Don't print record.errors.full_messages — they may
              # include attribute values which are the plaintext of
              # encrypted columns.
              File.open(err_log, "a") { |f| f.puts "[#{Time.now.utc.iso8601}] klass=#{klass.name} record_id=#{rid} save_failed=true" }
            end
          rescue StandardError => e
            errors += 1
            safe_log_error.call(rid, klass, e)
          end
        end
      end
      puts "  processed=#{processed} errors=#{errors}"
      grand_total  += processed
      grand_errors += errors
    end

    puts
    puts "Total: processed=#{grand_total} errors=#{grand_errors}"
    if grand_errors.zero?
      puts "Safe to remove ACTIVE_RECORD_ENCRYPTION_PREVIOUS_* env vars and restart."
    else
      warn "⚠️  Errors encountered. Details (sanitized) in: #{err_log}"
      warn "    Do NOT remove the previous-key env vars yet."
      exit 1
    end
  end

  desc "List models with `encrypts` declarations + row counts"
  task inventory: :environment do
    Rails.application.eager_load!
    models = ENCRYPTED_MODELS.call
    if models.empty?
      puts "No models with `encrypts` declarations loaded."
      next
    end
    total_rows = 0
    models.each do |klass|
      rows = klass.count
      total_rows += rows
      puts "#{klass.name.ljust(48)} attrs=#{klass.encrypted_attributes.to_a.inspect}  rows=#{rows}"
    end
    puts
    puts "Total: #{models.size} model(s), #{total_rows} encrypted row(s)"
  end
end

# frozen_string_literal: true

# IMP-b719328ddeb9 — the address a GDPR completion notice goes to, captured
# while the data subject still has one.
#
# The erasure a deletion request performs anonymizes the user record, email
# included, and an account termination anonymizes every account user (the owner
# among them) BEFORE it is marked complete. Every reader that resolved the
# address at completion therefore got an anonymized placeholder or nil. The
# request now carries its own copy, snapshotted at creation.
#
# The columns hold an ActiveRecord-encrypted value (`encrypts :notification_email`
# in NotificationEmailSnapshot), hence text: the ciphertext envelope is longer
# than the address. They are scrubbed to NULL by the write that moves the row to
# a terminal status — a snapshot that outlived the data it describes would
# itself be personal data kept after erasure — so a NULL is the normal state of
# every settled row.
#
# NO BACKFILL, deliberately. Existing rows are left NULL: the value is
# encrypted, so a set-based UPDATE cannot write it, and a row-by-row model
# backfill is exactly the data migration that can raise at boot on a production
# value. A NULL row takes the nil-safe path (no send, a warning, completion
# proceeds), the same outcome those rows had before this column existed.
#
# Guarded by column_exists? because server/db/schema.rb already carries the
# columns: a fresh schema:load followed by migrate must not fail on them.
class AddNotificationEmailToGdprRequests < ActiveRecord::Migration[8.1]
  TABLES = %i[data_deletion_requests account_terminations].freeze

  def up
    TABLES.each do |table|
      add_column table, :notification_email, :text unless column_exists?(table, :notification_email)
    end
  end

  def down
    TABLES.each do |table|
      remove_column table, :notification_email if column_exists?(table, :notification_email)
    end
  end
end

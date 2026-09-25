# frozen_string_literal: true

# AdminSettingsController#update's nested-hash writer never actually fired
# against a real request: a permitted ActionController::Parameters object's
# nested value is itself an ActionController::Parameters, never a Hash, so
# `value.is_a?(Hash)` was always false and the flat `.to_s` branch ran
# instead — storing the literal string representation of the whole nested
# Parameters object under the single flat key ("rate_limiting",
# "system_notifications", "feature_flags"), e.g.
# '#<ActionController::Parameters {"enabled"=>true, ...} permitted: true>'.
#
# Every save of the rate-limiting form has hit this: admin-configured rate
# limits have never persisted as anything a reader could use. The fix
# (Admin::SystemSettings normalizing at the controller boundary and writing
# proper "rate_limiting.*" dotted rows) lands alongside this migration —
# see server/app/services/admin/system_settings.rb.
#
# Nothing here is salvageable: the stored value is a Ruby #inspect-style
# string dump, not a serialization format, so there is no value worth
# parsing back out. This only ever deletes the single corrupted row per key
# (never the per-field dotted rows the fix introduces) and never logs or
# prints a value — only a count.
class DeleteGarbageAdminSettingsNestedWriterRows < ActiveRecord::Migration[8.0]
  AFFECTED_KEYS = %w[rate_limiting system_notifications feature_flags].freeze
  GARBAGE_PREFIX = "#<ActionController::Parameters"

  def up
    deleted = execute(
      "DELETE FROM admin_settings " \
      "WHERE key IN (#{AFFECTED_KEYS.map { |k| connection.quote(k) }.join(', ')}) " \
      "AND value LIKE #{connection.quote("#{GARBAGE_PREFIX}%")}"
    ).cmd_tuples

    say "Deleted #{deleted} garbage AdminSettings row(s) (value never logged)"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "deleted rows held no salvageable data"
  end
end

# frozen_string_literal: true

# IMP-7552124d35c1 -- users.last_login_ip cannot hold its own encrypted value.
#
# `encrypts :last_login_ip` (User) stores an ActiveRecord encryption envelope,
# several times longer than the address, but the column was varchar(45) -- sized
# for the plaintext. Writing any real address raised
# PG::StringDataRightTruncation. Nothing in app/ writes the column today, so no
# production row holds a value; this widens it before a writer exists.
#
# DDL only, no backfill: a varchar -> text change rewrites no data and cannot
# raise on existing values. Guarded because server/db/schema.rb already carries
# the wide column, so a fresh schema:load followed by migrate is a no-op.
#
# #down narrows back only while no stored value exceeds the old limit; an
# encrypted value never fits, so once the column holds one the rollback leaves
# it wide rather than truncate (or raise on) real data.
class WidenUsersLastLoginIpToText < ActiveRecord::Migration[8.1]
  OLD_LIMIT = 45

  def up
    return unless narrow_string_column?

    change_column :users, :last_login_ip, :text
  end

  def down
    return unless column_exists?(:users, :last_login_ip, :text)
    if select_value("SELECT 1 FROM users WHERE char_length(last_login_ip) > #{OLD_LIMIT} LIMIT 1")
      say "users.last_login_ip holds a value over #{OLD_LIMIT} chars; leaving the column as text"
      return
    end

    change_column :users, :last_login_ip, :string, limit: OLD_LIMIT
  end

  private

  def narrow_string_column?
    column_exists?(:users, :last_login_ip, :string) && !column_exists?(:users, :last_login_ip, :text)
  end
end

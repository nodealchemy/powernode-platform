# frozen_string_literal: true

# IMP-01a05fea. Drops `user_tokens.permissions` — a snapshot of the user's FULL
# permission set taken at mint time, which UserToken#has_permission? used to
# answer from instead of the database.
#
# The reads were deleted in IMP-a18f5a8ed393 and the writes with them: nothing
# in server/, extensions/ or worker/ has read or written this column since.
# What survived is the DATA — a stale permission list on every row minted before
# that fix, sitting in a table where it still reads as authoritative. The model
# comment on #has_permission? spells out both failure directions it produced (a
# stale `system.admin` answering true for anything; a permission granted after
# the mint invisible for the token's life) and ends by warning against
# reintroducing the stamp. A column nothing writes is an invitation; removing it
# makes the warning structural.
#
# IRREVERSIBLE BY DESIGN. #down restores the column but NOT its contents, and
# that is correct: the contents were the defect. A rollback lands on an empty
# column, which is exactly the state every row has had since the writes were
# removed.
#
# SAFE IN EITHER DEPLOY ORDER, measured rather than assumed: with the column
# dropped in a rolled-back transaction, code still carrying `serialize
# :permissions` minted a token, read it back, and answered #has_permission?
# without raising. No ignored_columns staging step is needed.
class DropUserTokensPermissions < ActiveRecord::Migration[8.1]
  def up
    remove_column :user_tokens, :permissions
  end

  def down
    add_column :user_tokens, :permissions, :text
  end
end

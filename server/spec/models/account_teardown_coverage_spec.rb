# frozen_string_literal: true

require "rails_helper"

# Static guard for Account#destroy!: every foreign key (no ON DELETE
# CASCADE/NULLIFY) onto a table the teardown deletes from must be COVERED, or the
# final DELETE fails. The teardown retries a failing dependent after the others
# (declaration order is irrelevant), so only coverage is asserted here, not order.
# Covers every loaded model, extension models included.
#
# Coverage is per (table, column) and row-scope aware. A FK column T.c is
# covered when
#   * a `dependent: :nullify` association nulls exactly that column, and the
#     column is nullable; or
#   * a `dependent: :destroy/:delete_all` association deletes rows by that same
#     column (the rows that reference the deleted owner); or
#   * T is deleted by any association and T has no nullable account_id (every row
#     belongs to an account or hangs under an account-owned parent); a table
#     WITH a nullable account_id (shared rows) is only partly deleted that way and
#     needs one of the first two, or the shared-row refusal below; or
#   * the column references users from such a shared-row table: the teardown
#     refuses while shared rows reference the account's users
#     (Account.shared_user_reference_edges); or
#   * T is a DB-cascade child of a table that is deleted; or
#   * a registered teardown guard names the column in its `covers:` list (the
#     teardown refuses while such rows exist), or T is behind a
#     `restrict_with_*` association of the Account (refuses while rows exist).
RSpec.describe "Account teardown FK coverage" do
  def klass_of(reflection)
    return nil if reflection.polymorphic?

    reflection.klass
  rescue NameError, ArgumentError
    nil
  end

  def column_nullable?(table, column)
    ActiveRecord::Base.connection.columns(table).find { |c| c.name == column.to_s }&.null == true
  end

  # Returns the closure facts used by the examples.
  def teardown_closure
    Rails.application.eager_load!
    deleted = Set.new(%w[accounts users audit_logs])
    nullified = Set.new      # [table, column]
    row_deleted = Set.new    # [table, column] deleted by exactly that column
    guarded_tables = Set.new
    restricted = Set.new     # [table, column] behind a restrict_with_* on Account or User
    owners = {}              # table => tables whose rows delete it (dependent: destroy/delete_all)
    # Account#run_account_teardown destroys the users and deletes the audit rows itself.
    row_deleted << %w[users account_id] << %w[audit_logs account_id]
    queue = [ Account, User ]
    seen = Set.new
    until queue.empty?
      model = queue.shift
      next unless seen.add?(model)

      # A HABTM join table is cleaned by Rails when the owner row is destroyed.
      model.reflect_on_all_associations(:has_and_belongs_to_many).each do |r|
        deleted << r.join_table
        [ r.foreign_key, r.association_foreign_key ].each { |col| row_deleted << [ r.join_table, col.to_s ] }
      end
      model.reflect_on_all_associations.each do |r|
        next if r.options[:through]

        k = klass_of(r) or next
        fk = r.foreign_key.to_s
        case r.options[:dependent]
        when :destroy, :delete_all
          deleted << k.table_name
          (owners[k.table_name] ||= Set.new) << model.table_name
          row_deleted << [ k.table_name, fk ]
          queue << k if r.options[:dependent] == :destroy
        when :nullify then nullified << [ k.table_name, fk ]
        when :restrict_with_error, :restrict_with_exception
          guarded_tables << k.table_name if model == Account
          # A restricted association refuses cleanly (no raw FK error); on User it is
          # also the set of rows Account#run_account_teardown deletes first.
          # Only a restrict on Account or User is a PRE-FLIGHT refusal (it fires before
          # the teardown has any side effect); a nested one fires mid-cascade.
          restricted << [ k.table_name, fk ] if [ Account, User ].include?(model)
          row_deleted << [ k.table_name, fk ] if model == User
        end
      end
    end
    fks = ActiveRecord::Base.connection.tables.flat_map { |t| ActiveRecord::Base.connection.foreign_keys(t) }
    loop do
      more = fks.select { |f| deleted.include?(f.to_table) && f.on_delete == :cascade && !deleted.include?(f.from_table) }
      break if more.empty?

      more.each do |f|
        deleted << f.from_table
        (owners[f.from_table] ||= Set.new) << f.to_table
      end
    end
    { deleted: deleted, nullified: nullified, row_deleted: row_deleted,
      guarded_tables: guarded_tables, restricted: restricted, owners: owners, fks: fks }
  end

  # Is EVERY row of the table removed once its owners' rows are? True when each
  # row carries a NOT NULL account_id, or the table has no account_id and every
  # association that deletes it hangs under a tenant-complete owner. A nullable
  # account_id (shared rows) -- or a child of such a shared table -- is only
  # PARTLY deleted, so its other outbound references need their own coverage.
  def tenant_complete?(table, facts, visiting = Set.new)
    return true if %w[accounts users].include?(table)
    return false unless visiting.add?(table)

    account_col = ActiveRecord::Base.connection.columns(table).find { |col| col.name == "account_id" }
    return !account_col.null if account_col

    parents = facts[:owners][table].to_a
    parents.any? && parents.all? { |parent| parent == table || tenant_complete?(parent, facts, visiting.dup) }
  end

  def covered?(fk, facts)
    t = fk.from_table
    c = fk.column.to_s
    return true if facts[:guarded_tables].include?(t)
    return true if facts[:restricted].include?([ t, c ])
    return true if Account.teardown_guard_coverage.any? { |gt, gc| gt == t && (gc == "*" || gc == c) }
    return true if facts[:nullified].include?([ t, c ]) && column_nullable?(t, c)
    return true if facts[:row_deleted].include?([ t, c ])
    return true if Account.shared_user_reference_edges.any? { |st, sc, _| st == t && sc == c } # nullified / refused
    # Deleted through some association and EVERY row belongs to an account (or
    # hangs under an account-owned parent): all of its outbound references go.
    return true if facts[:deleted].include?(t) && tenant_complete?(t, facts)

    false
  end

  it "leaves no foreign key that would block the account DELETE" do
    facts = teardown_closure
    blockers = facts[:fks].select do |f|
      facts[:deleted].include?(f.to_table) && !%i[cascade nullify].include?(f.on_delete) && !covered?(f, facts)
    end
    expect(blockers.map { |f| "#{f.from_table}.#{f.column} -> #{f.to_table}" }.sort).to eq([])
  end

  it "only nullifies columns that can be null" do
    facts = teardown_closure
    bad = facts[:nullified].reject { |t, c| !ActiveRecord::Base.connection.table_exists?(t) || column_nullable?(t, c) }
    expect(bad).to eq([])
  end

  # The teardown deletes User's restricted rows first; a NEW restrict_with_*
  # association on User must be a conscious decision (add it to the allow-list
  # in Account, and decide what the teardown does with its rows).
  it "knows every restrict_with_* association on User" do
    restricting = User.reflect_on_all_associations
                      .select { |r| %i[restrict_with_error restrict_with_exception].include?(r.options[:dependent]) }
                      .map(&:name)
    expect(restricting.sort).to eq(Account::TEARDOWN_USER_RESTRICTED_ASSOCIATIONS.sort)
  end
end

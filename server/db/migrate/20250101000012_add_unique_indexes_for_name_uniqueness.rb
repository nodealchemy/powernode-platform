# frozen_string_literal: true

# Adds DB-level unique indexes that back model uniqueness validations which
# previously had NO database guard. Without a unique index, the model-level
# `validates ... uniqueness` check is a read-then-write that can be defeated by
# two concurrent requests both passing validation and both inserting — a classic
# race that produces duplicate rows. The model validations stay in place (they
# give friendly errors on the happy path); the index is the last-resort guard.
#
# Targets:
#   - ai_agent_teams   : unique (account_id, name)  [Ai::AgentTeam name uniqueness scoped to account]
#   - validation_rules : unique (name)              [ValidationRule global name uniqueness]
#   - ai_agent_lineages: unique (parent_agent_id, child_agent_id)
#                        [Ai::AgentLineage parent uniqueness scoped to child — a lineage edge
#                         is unique per (parent, child) pair]
#
# Before adding each unique index we DEFENSIVELY de-dupe so the index creation
# cannot fail on pre-existing race duplicates. De-dupe is NON-DESTRUCTIVE:
#   - name tables: keep the earliest (created_at) row untouched; the later rows
#     get a uniqueness-restoring suffix appended to their name
#     ("<name> (dup <short-id>)"). No rows are deleted — an operator can find and
#     reconcile them later.
#   - lineage table: a duplicate (parent, child) edge carries no unique business
#     identity beyond its metadata, and there is no name column to rename. We
#     keep the earliest row and fold the duplicates' ids + metadata into the
#     kept row's metadata under "merged_duplicate_lineage_ids" / "merged_duplicate_metadata"
#     BEFORE removing the redundant edges, so no information is lost.
class AddUniqueIndexesForNameUniqueness < ActiveRecord::Migration[8.1]
  def up
    dedupe_named_table!(:ai_agent_teams, scope_columns: [:account_id])
    dedupe_named_table!(:validation_rules, scope_columns: [])
    dedupe_lineages!

    add_index :ai_agent_teams, [:account_id, :name], unique: true
    add_index :validation_rules, :name, unique: true
    add_index :ai_agent_lineages, [:parent_agent_id, :child_agent_id], unique: true
  end

  def down
    remove_index :ai_agent_teams, column: [:account_id, :name], unique: true
    remove_index :validation_rules, column: :name, unique: true
    remove_index :ai_agent_lineages, column: [:parent_agent_id, :child_agent_id], unique: true
  end

  private

  # Rename later duplicates within each (scope..., name) group so the unique
  # index can be created. The earliest row by created_at keeps its original name.
  def dedupe_named_table!(table, scope_columns:)
    group_cols = (scope_columns + [:name]).map { |c| connection.quote_column_name(c) }.join(", ")
    quoted_table = connection.quote_table_name(table)

    # Find groups with more than one row sharing the same (scope, name).
    dup_groups = connection.select_all(<<~SQL.squish)
      SELECT #{group_cols}, COUNT(*) AS cnt
      FROM #{quoted_table}
      GROUP BY #{group_cols}
      HAVING COUNT(*) > 1
    SQL

    dup_groups.each do |group|
      where_clause = (scope_columns + [:name]).map do |col|
        value = group[col.to_s]
        if value.nil?
          "#{connection.quote_column_name(col)} IS NULL"
        else
          "#{connection.quote_column_name(col)} = #{connection.quote(value)}"
        end
      end.join(" AND ")

      rows = connection.select_all(<<~SQL.squish)
        SELECT id, name FROM #{quoted_table}
        WHERE #{where_clause}
        ORDER BY created_at ASC, id ASC
      SQL

      # First row (earliest) keeps its name; rename the rest. The suffix carries a
      # per-group ordinal AND the full row id so it is guaranteed unique even when
      # several UUIDv7 ids generated in the same millisecond share a leading prefix
      # (a short-id slice alone could collide and re-violate the new index).
      rows.to_a.drop(1).each_with_index do |row, idx|
        new_name = "#{row['name']} (dup #{idx + 1} #{row['id']})"
        connection.execute(<<~SQL.squish)
          UPDATE #{quoted_table}
          SET name = #{connection.quote(new_name)}, updated_at = NOW()
          WHERE id = #{connection.quote(row['id'])}
        SQL
      end
    end
  end

  # Fold duplicate lineage edges into the earliest row's metadata, then remove
  # the redundant edges. No business identity is lost: the (parent, child) edge
  # is preserved (earliest row) and the duplicates' ids + metadata are archived
  # into the kept row.
  def dedupe_lineages!
    quoted_table = connection.quote_table_name(:ai_agent_lineages)

    dup_groups = connection.select_all(<<~SQL.squish)
      SELECT parent_agent_id, child_agent_id, COUNT(*) AS cnt
      FROM #{quoted_table}
      GROUP BY parent_agent_id, child_agent_id
      HAVING COUNT(*) > 1
    SQL

    dup_groups.each do |group|
      rows = connection.select_all(<<~SQL.squish)
        SELECT id, metadata FROM #{quoted_table}
        WHERE parent_agent_id = #{connection.quote(group['parent_agent_id'])}
          AND child_agent_id  = #{connection.quote(group['child_agent_id'])}
        ORDER BY created_at ASC, id ASC
      SQL

      keep = rows.to_a.first
      dups = rows.to_a.drop(1)
      next if dups.empty?

      merged_ids = dups.map { |r| r["id"] }
      merged_meta = dups.map { |r| r["metadata"] }

      kept_meta = parse_jsonb(keep["metadata"])
      kept_meta["merged_duplicate_lineage_ids"] = merged_ids
      kept_meta["merged_duplicate_metadata"]    = merged_meta

      connection.execute(<<~SQL.squish)
        UPDATE #{quoted_table}
        SET metadata = #{connection.quote(kept_meta.to_json)}::jsonb, updated_at = NOW()
        WHERE id = #{connection.quote(keep['id'])}
      SQL

      id_list = merged_ids.map { |id| connection.quote(id) }.join(", ")
      connection.execute(<<~SQL.squish)
        DELETE FROM #{quoted_table} WHERE id IN (#{id_list})
      SQL
    end
  end

  def parse_jsonb(value)
    case value
    when Hash then value
    when String then (JSON.parse(value) rescue {})
    else {}
    end
  end
end

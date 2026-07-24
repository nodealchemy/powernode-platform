# frozen_string_literal: true

# import.rb — load an export.rb dump into the target plane (ops-hub).
#
# Idempotent: every insert is ON CONFLICT DO NOTHING (PK and natural-key
# conflicts both skip), so a partial run resumes by re-running. The source DB
# is never touched; rollback = restore the target from its pre-import pg_dump.
#
# Per-table transforms (per the 2026-07 dev→ops-hub transition plan):
#   - account_id      → target account (NULL/global rows stay NULL)
#   - verified_by_id  → --verified-by user (no DB FK, but dev user ids are
#                       meaningless on the target) or NULL
#   - dev-only FKs    → NULL (teams/agents/executions/repos/users/documents,
#                       ai_skill_id, ai_data_source_id — BridgeService re-links
#                       skill nodes on the target's next skill save)
#   - category_id     → remapped via category slug (categories slug-upsert first)
#   - knowledge_base_id → remapped via (account, name) when the preserved UUID
#                       collided with an existing target KB
#   - edge endpoints  → remapped by (name, node_type) for nodes skipped on the
#                       target's unique active index; edges whose endpoint
#                       resolves to nothing are dropped (counted)
#
# Usage (from the TARGET plane's server dir):
#   bin/rails runner import.rb <export-dir> <target-account-id> [--verified-by EMAIL] [--dry-run]
require "zlib"
require "json"

export_dir = ARGV[0] or abort "usage: rails runner import.rb <export-dir> <target-account-id> [--verified-by EMAIL] [--dry-run]"
target_account_id = ARGV[1] or abort "usage: rails runner import.rb <export-dir> <target-account-id> [--verified-by EMAIL] [--dry-run]"
dry_run = ARGV.include?("--dry-run")
verified_by_email = ARGV[ARGV.index("--verified-by") + 1] if ARGV.include?("--verified-by")

conn = ActiveRecord::Base.connection
manifest = JSON.parse(File.read(File.join(export_dir, "manifest.json")))

# ── Preconditions ────────────────────────────────────────────────────────────
target_schema = conn.select_value("SELECT max(version) FROM schema_migrations")
unless target_schema == manifest["source_schema_version"]
  abort "ABORT: schema mismatch — source #{manifest['source_schema_version']} vs target #{target_schema}. Migrate the lagging plane first."
end
unless conn.select_value("SELECT count(*) FROM pg_extension WHERE extname = 'vector'").to_i == 1
  abort "ABORT: pgvector extension missing on target"
end
unless conn.select_value("SELECT count(*) FROM accounts WHERE id = #{conn.quote(target_account_id)}").to_i == 1
  abort "ABORT: target account #{target_account_id} not found"
end
verified_by_id = nil
if verified_by_email
  # users.email is ActiveRecord-encrypted (deterministic) — a raw-SQL WHERE
  # compares against ciphertext and never matches. Resolve through the model,
  # which encrypts the query value.
  verified_by_id = User.find_by(email: verified_by_email)&.id
  abort "ABORT: --verified-by user #{verified_by_email} not found" unless verified_by_id
end

puts "target account: #{target_account_id}"
puts "verified_by:    #{verified_by_id || 'NULL'}"
puts "mode:           #{dry_run ? 'DRY-RUN (rolled back)' : 'LIVE'}"

# Columns forced to NULL per table (dev-only FKs with no target referent).
NULL_COLUMNS = {
  "ai_knowledge_bases" => %w[created_by_id git_repository_id cloned_from_id],
  "knowledge_base_articles" => %w[author_id last_edited_by_id cloned_from_id],
  "ai_shared_knowledges" => %w[created_by_id git_repository_id],
  "ai_compound_learnings" => %w[ai_agent_team_id source_agent_id source_execution_id
                                git_repository_id disproven_by_id superseded_by_id],
  "ai_knowledge_graph_nodes" => %w[ai_skill_id ai_data_source_id source_document_id],
  "ai_knowledge_graph_edges" => %w[source_document_id]
}.freeze

BATCH = 1_000
stats = Hash.new { |h, k| h[k] = { read: 0, inserted: 0, skipped: 0, dropped: 0 } }

read_rows = lambda do |table, &block|
  Zlib::GzipReader.open(File.join(export_dir, "#{table}.ndjson.gz")) do |gz|
    gz.each_line { |line| block.call(JSON.parse(line)) }
  end
end

insert_batch = lambda do |table, columns, rows|
  return 0 if rows.empty?

  values = rows.map do |row|
    "(" + columns.map { |c| conn.quote(row[c]) }.join(",") + ")"
  end.join(",")
  result = conn.execute(
    "INSERT INTO #{table} (#{columns.join(',')}) VALUES #{values} ON CONFLICT DO NOTHING"
  )
  result.cmd_tuples
end

transform = lambda do |table, row|
  row = row.dup
  row["account_id"] = target_account_id if row["account_id"]
  (NULL_COLUMNS[table] || []).each { |c| row[c] = nil }
  if table == "ai_compound_learnings" && row["verified_by_id"]
    row["verified_by_id"] = verified_by_id
  end
  row
end

import_table = lambda do |table, per_row = nil|
  columns = nil
  batch = []
  flush = lambda do
    stats[table][:inserted] += insert_batch.call(table, columns, batch)
    stats[table][:read] += batch.size
    batch.clear
  end
  read_rows.call(table) do |row|
    row = transform.call(table, row)
    row = per_row.call(row) if per_row
    next stats[table][:dropped] += 1 if row.nil?

    columns ||= row.keys
    batch << row
    flush.call if batch.size >= BATCH
  end
  flush.call
  stats[table][:skipped] = stats[table][:read] - stats[table][:inserted]
  s = stats[table]
  puts format("%-28s read=%-7d inserted=%-7d skipped=%-6d dropped=%d",
              table, s[:read], s[:inserted], s[:skipped], s[:dropped])
end

conn.transaction do
  # 1. Knowledge bases (UUID-preserved; nodes reference them by id)
  import_table.call("ai_knowledge_bases")

  # KB remap for rows whose UUID was skipped (id or (account,name) collision):
  # resolve by name on the target and rewrite node references.
  kb_remap = {}
  read_rows.call("ai_knowledge_bases") do |row|
    next if conn.select_value("SELECT 1 FROM ai_knowledge_bases WHERE id = #{conn.quote(row['id'])}")

    resolved = conn.select_value(<<~SQL)
      SELECT id FROM ai_knowledge_bases
      WHERE name = #{conn.quote(row['name'])}
        AND (account_id = #{conn.quote(target_account_id)} OR account_id IS NULL)
    SQL
    kb_remap[row["id"]] = resolved # nil → nodes fall back to NULL kb
  end
  puts "kb remap: #{kb_remap.inspect}" if kb_remap.any?

  # 2. Categories: slug-upsert (global table), then remap article category_id
  import_table.call("knowledge_base_categories")
  cat_remap = {}
  read_rows.call("knowledge_base_categories") do |row|
    target_id = conn.select_value("SELECT id FROM knowledge_base_categories WHERE slug = #{conn.quote(row['slug'])}")
    cat_remap[row["id"]] = target_id if target_id && target_id != row["id"]
  end
  # Parent links may point at remapped categories
  cat_remap.each do |old_id, new_id|
    conn.execute("UPDATE knowledge_base_categories SET parent_id = #{conn.quote(new_id)} WHERE parent_id = #{conn.quote(old_id)}")
  end
  puts "category remap: #{cat_remap.size} slugs" if cat_remap.any?

  # 3. Articles
  import_table.call("knowledge_base_articles", lambda { |row|
    row["category_id"] = cat_remap[row["category_id"]] || row["category_id"]
    row
  })

  # 4. Shared knowledge + live learnings
  import_table.call("ai_shared_knowledges")
  import_table.call("ai_compound_learnings")

  # 5. Graph nodes (largest table; kb reference remapped inline)
  import_table.call("ai_knowledge_graph_nodes", lambda { |row|
    if row["knowledge_base_id"] && kb_remap.key?(row["knowledge_base_id"])
      row["knowledge_base_id"] = kb_remap[row["knowledge_base_id"]]
    end
    row
  })

  # Node endpoint remap: exported ids that were natural-key-skipped resolve by
  # (name, node_type) against the target's active set.
  node_remap = {}
  node_dropped = Set.new
  pending = []
  resolve_pending = lambda do
    next if pending.empty?

    ids = pending.map { |r| conn.quote(r["id"]) }.join(",")
    present = conn.select_values("SELECT id FROM ai_knowledge_graph_nodes WHERE id IN (#{ids})").to_set
    pending.each do |row|
      next if present.include?(row["id"])

      resolved = conn.select_value(<<~SQL)
        SELECT id FROM ai_knowledge_graph_nodes
        WHERE account_id = #{conn.quote(target_account_id)}
          AND name = #{conn.quote(row['name'])}
          AND node_type = #{conn.quote(row['node_type'])}
          AND status = 'active'
      SQL
      resolved ? node_remap[row["id"]] = resolved : node_dropped << row["id"]
    end
    pending.clear
  end
  read_rows.call("ai_knowledge_graph_nodes") do |row|
    pending << row
    resolve_pending.call if pending.size >= BATCH
  end
  resolve_pending.call
  puts "node remap: #{node_remap.size} resolved by natural key, #{node_dropped.size} unresolvable"

  # 6. Edges: endpoints through the remap; drop edges to vanished nodes
  import_table.call("ai_knowledge_graph_edges", lambda { |row|
    src = node_remap[row["source_node_id"]] || row["source_node_id"]
    tgt = node_remap[row["target_node_id"]] || row["target_node_id"]
    return nil if node_dropped.include?(row["source_node_id"]) || node_dropped.include?(row["target_node_id"])

    row["source_node_id"] = src
    row["target_node_id"] = tgt
    row
  })

  raise ActiveRecord::Rollback if dry_run
end

puts dry_run ? "DRY-RUN complete — all changes rolled back" : "import complete"

# ── Verification snapshot ────────────────────────────────────────────────────
unless dry_run
  puts "\ntarget counts:"
  manifest["tables"].each_key do |table|
    puts format("  %-28s %d", table, conn.select_value("SELECT count(*) FROM #{table}"))
  end
end

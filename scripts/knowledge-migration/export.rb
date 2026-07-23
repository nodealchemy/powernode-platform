# frozen_string_literal: true

# export.rb — dump the curated knowledge corpus for plane migration (dev → ops-hub).
#
# Read-only against the source DB. Writes one NDJSON.gz per table plus a
# manifest.json with counts, filters, and the source schema version. Row UUIDs
# are preserved verbatim — cross-model JSONB provenance links
# (source_learning_id etc.) have no DB FKs and survive only via PK-preserving
# transport. Vector embeddings export as pgvector text and re-cast on import.
#
# Scope (per the 2026-07 dev→ops-hub transition plan):
#   - ai_knowledge_bases:        only rows referenced by exported graph nodes
#   - knowledge_base_categories: all (global, slug-unique)
#   - knowledge_base_articles:   all
#   - ai_shared_knowledges:      all
#   - ai_compound_learnings:     live only (active + verified)
#   - ai_knowledge_graph_nodes:  status <> 'archived'
#   - ai_knowledge_graph_edges:  both endpoints in the exported node set
#
# Usage (from the SOURCE plane's server dir — /opt/powernode/server on dev):
#   bin/rails runner ../scripts/knowledge-migration/export.rb /path/to/export-dir
require "zlib"
require "json"
require "fileutils"

out_dir = ARGV[0] or abort "usage: rails runner export.rb <output-dir>"
FileUtils.mkdir_p(out_dir)

BATCH = 2_000
conn = ActiveRecord::Base.connection

NODE_FILTER = "status <> 'archived'"

TABLES = {
  "ai_knowledge_bases" => <<~SQL.strip,
    id IN (SELECT DISTINCT knowledge_base_id FROM ai_knowledge_graph_nodes
           WHERE knowledge_base_id IS NOT NULL AND #{NODE_FILTER})
  SQL
  "knowledge_base_categories" => nil,
  "knowledge_base_articles" => nil,
  "ai_shared_knowledges" => nil,
  "ai_compound_learnings" => "status IN ('active', 'verified')",
  "ai_knowledge_graph_nodes" => NODE_FILTER,
  "ai_knowledge_graph_edges" => <<~SQL.strip,
    EXISTS (SELECT 1 FROM ai_knowledge_graph_nodes s
            WHERE s.id = ai_knowledge_graph_edges.source_node_id AND s.#{NODE_FILTER})
    AND EXISTS (SELECT 1 FROM ai_knowledge_graph_nodes t
                WHERE t.id = ai_knowledge_graph_edges.target_node_id AND t.#{NODE_FILTER})
  SQL
}.freeze

manifest = {
  "generated_at" => Time.current.iso8601,
  "source_schema_version" => conn.select_value("SELECT max(version) FROM schema_migrations"),
  "source_account_ids" => {},
  "tables" => {}
}

TABLES.each do |table, where|
  where_sql = where ? "WHERE #{where}" : ""
  path = File.join(out_dir, "#{table}.ndjson.gz")
  count = 0
  last_id = nil

  Zlib::GzipWriter.open(path) do |gz|
    loop do
      cursor = last_id ? "#{where ? 'AND' : 'WHERE'} id > #{conn.quote(last_id)}" : ""
      rows = conn.select_all(
        "SELECT * FROM #{table} #{where_sql} #{cursor} ORDER BY id LIMIT #{BATCH}"
      ).to_a
      break if rows.empty?

      rows.each { |row| gz.puts(JSON.generate(row)) }
      count += rows.size
      last_id = rows.last["id"]
    end
  end

  manifest["tables"][table] = { "count" => count, "filter" => where&.gsub(/\s+/, " ") }
  puts "exported #{table}: #{count} rows"
end

# Distinct source account ids per table — the import remaps every one of these
# to the target account, so surface them for eyeballing.
TABLES.each_key do |table|
  next unless conn.columns(table).map(&:name).include?("account_id")

  ids = conn.select_values("SELECT DISTINCT account_id FROM #{table} WHERE account_id IS NOT NULL")
  manifest["source_account_ids"][table] = ids
end

File.write(File.join(out_dir, "manifest.json"), JSON.pretty_generate(manifest))
puts "manifest written: #{File.join(out_dir, 'manifest.json')}"
puts "total: #{manifest['tables'].values.sum { |t| t['count'] }} rows"

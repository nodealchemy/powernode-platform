# frozen_string_literal: true
#
# Schema audit reflection — emits a TSV mapping every DB table to its
# ActiveRecord model + owning component (core vs extension), plus join-table
# and orphan detection. Run in BOTH modes to find extension-owned tables:
#   full:  BUNDLE_GEMFILE=Gemfile.private POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 \
#            rails runner scripts/audit/table_model_map.rb
#   core:  rails runner scripts/audit/table_model_map.rb        # plain Gemfile
#
# Columns: table  has_model  model_class  owner  is_join_table  model_file
# Orphan table  = has_model=false AND is_join_table=false
# Extension-owned = owner not in (core, unknown)
# stderr also lists models whose table is ABSENT from the DB (dead/renamed).

Rails.application.eager_load!

def owner_of(path)
  return "unknown" if path.nil?
  case path
  when %r{/extensions/private/([^/]+)/} then Regexp.last_match(1)
  when %r{/extensions/([^/]+)/}         then Regexp.last_match(1)
  when %r{/server/}                     then "core"
  else "gem"
  end
end

models = ActiveRecord::Base.descendants.reject(&:abstract_class?).select { |m| m.name }
table_models = Hash.new { |h, k| h[k] = [] }
models.each do |m|
  tn = (m.table_name rescue nil)
  table_models[tn] << m if tn
end

# HABTM join tables (evade descendants reflection as standalone models)
join_tables = []
models.each do |m|
  (m.reflect_on_all_associations(:has_and_belongs_to_many) rescue []).each do |a|
    jt = (a.join_table rescue nil)
    join_tables << jt if jt
  end
end
join_tables.uniq!

conn = ActiveRecord::Base.connection
db_tables = conn.tables - %w[schema_migrations ar_internal_metadata]

puts %w[table has_model model_class owner is_join_table model_file].join("\t")
db_tables.sort.each do |t|
  is_join = join_tables.include?(t)
  ms = table_models[t]
  if ms.any?
    ms.each do |m|
      full = (Object.const_source_location(m.name)&.first rescue nil)
      owner = owner_of(full)
      # normalize to repo-relative for readability (non-greedy; keep extension prefix)
      disp = full&.sub(%r{\A.*?/((?:extensions/(?:private/)?[^/]+/)?server)/}, '\1/')
      puts [t, true, m.name, owner, is_join, disp].join("\t")
    end
  else
    puts [t, false, "", "", is_join, ""].join("\t")
  end
end

warn "=== models whose table is ABSENT from this DB (dead/renamed candidates) ==="
table_models.each do |t, ms|
  next if db_tables.include?(t)
  ms.each { |m| warn "#{m.name}\t->\t#{t}\t(table missing)" }
end
warn "=== summary: #{db_tables.size} db tables, #{table_models.size} mapped tables, #{join_tables.size} join tables ==="

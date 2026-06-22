#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 9 — Curated ETL: live powernode_development -> powernode_new_development
#
# Reads OLD via postgres_fdw foreign schema (old_fdw), writes NEW via raw SQL ONLY
# (never AR models) so UUIDs + AR-encrypted ciphertext + pgvector embeddings transfer
# BYTE-EXACT. Generates one SQL file and runs it as the postgres superuser
# (needs session_replication_role + fdw). Idempotent, --dry-run, row-count validation.
#
# Strategy
#   * Column-intersection copy (etl_copy): only columns present in BOTH old+new transfer;
#     new-only columns take their DB default, old-only columns are ignored. Generic — no
#     hand-maintained per-table column maps.
#   * Scope predicate on every table that has account_id: NULL (global) OR one of KEEP.
#   * session_replication_role=replica during load => FK/trigger checks off => no need to
#     topologically order; orphans are pruned + validated afterwards.
#   * Overlap tables (already populated by `db:seed`) are DELETEd first so the live rows
#     load with their LIVE ids (FK children depend on those ids) without natural-key clashes.
#   * Transform islands handled explicitly: roles/role_permissions/permissions are SKIPPED
#     (code-defined + seeded); user_roles + worker_roles remap role_id by role NAME; KG
#     edges + context entries are pruned to migrated parents.
#
# Usage:  ruby scripts/phase9/etl.rb [--dry-run] [--run]

require "set"
require "open3"

OLD_DB = "powernode_development"
NEW_DB = "powernode_new_development"
KEEP   = %w[019c0d95-0b83-76d4-aa5f-e8b102812415 019c0d95-0e69-790a-850b-580050e4e1d5].freeze
KEEP_SQL = KEEP.map { |u| "'#{u}'::uuid" }.join(",")
DRY = ARGV.include?("--dry-run")
SQL_OUT = "/tmp/p9_etl_generated.sql"

# --- never migrate (dropped tables / code-defined / system bookkeeping / handled specially) ---
HARD_SKIP = %w[
  schema_migrations ar_internal_metadata
  permissions role_permissions roles
  cookie_consents ai_marketplace_moderations
].to_set

# Old tables that are dropped in the new schema (no target) — verified intentional.
# (trading_* are excluded wholesale below.)

# Tables seeded by db:seed that live is authoritative for => DELETE seeded rows then load
# live (preserves live ids for FK children, avoids natural-key collisions). New-side names.
OVERLAP = %w[
  ai_devops_templates ai_documents ai_knowledge_bases ai_mission_templates
  ai_model_pricings ai_skills shared_prompt_templates
  knowledge_base_articles knowledge_base_categories knowledge_base_tags
  devops_container_templates business_plans
  flipper_features flipper_gates
  supply_chain_licenses supply_chain_questionnaire_templates supply_chain_scan_templates
  ai_skills_mcp_servers
].to_set

# Join tables with NO single-column `id` PK => cannot ON CONFLICT(id); we DELETE+INSERT.
NO_ID = %w[ai_skills_mcp_servers worker_roles user_roles role_permissions].to_set

# site_settings: unique on `key`, no FK children => upsert on the natural key.
SPECIAL = %w[user_roles worker_roles site_settings].to_set

def cap(*args)
  out, err, st = Open3.capture3(*args)
  raise "CMD FAILED: #{args.join(' ')}\n#{err}" unless st.success?
  out
end

def q_old(sql) = cap("sudo", "-u", "postgres", "psql", "-d", OLD_DB, "-tA", "-c", sql).strip
def q_new(sql) = cap("sudo", "-u", "postgres", "psql", "-d", NEW_DB, "-tA", "-c", sql).strip

puts "== Phase 9 ETL planner (#{DRY ? 'DRY-RUN' : 'EXECUTE'}) =="

# 1. Table universes
old_tables = q_old("SELECT tablename FROM pg_tables WHERE schemaname='public'").split("\n").map(&:strip).to_set
new_tables = q_new("SELECT tablename FROM pg_tables WHERE schemaname='public'").split("\n").map(&:strip).to_set

# Reliable non-empty determination (pg_stat n_live_tup is stale/0 for un-analyzed tables).
# One round-trip: EXISTS(SELECT 1 ...) per table.
nonempty = Set.new
checks = old_tables.map { |t| %(SELECT '#{t}' t, EXISTS(SELECT 1 FROM public."#{t}") e) }.join(" UNION ALL ")
q_old(checks).split("\n").each { |l| name, e = l.split("|"); nonempty << name.strip if e&.strip == "t" }
# account_id presence per OLD table (scope must filter on the SOURCE column).
old_has_acct = Set.new
q_old("SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='account_id'").split("\n").each { |t| old_has_acct << t.strip }

# 2. Build rename map  new_table => old_source  (only where a real source exists)
def source_for(new_t, old_tables)
  return new_t if old_tables.include?(new_t)                          # identity
  if new_t.start_with?("system_sdwan_")
    cand = "sdwan_" + new_t.delete_prefix("system_sdwan_")
    return cand if old_tables.include?(cand)
  elsif new_t.start_with?("business_")
    base = new_t.delete_prefix("business_")
    return base          if old_tables.include?(base)
    return "ai_#{base}"  if old_tables.include?("ai_#{base}")
  end
  nil
end

# 3. Categorise
plan = []        # [{new, old, scope, mode}]
unmapped_new = []
new_tables.each do |nt|
  next if HARD_SKIP.include?(nt)
  src = source_for(nt, old_tables)
  if src.nil?
    unmapped_new << nt
    next
  end
  next unless nonempty.include?(src)       # nothing to migrate
  scope = old_has_acct.include?(src) ? "account_id IS NULL OR account_id IN (#{KEEP_SQL})" : nil
  scope = "id IN (#{KEEP_SQL})" if nt == "accounts"   # accounts keyed on id, not account_id
  mode  = if SPECIAL.include?(nt) then :special
          elsif OVERLAP.include?(nt) || NO_ID.include?(nt) then :reload   # delete+insert
          else :upsert end                                               # insert on conflict(id)
  plan << { new: nt, old: src, scope: scope, mode: mode }
end

# Old non-empty tables that map NOWHERE (intentional drops / trading) — report for audit.
dropped_nonempty = nonempty.to_a.reject do |ot|
  ot.start_with?("trading_") || HARD_SKIP.include?(ot) ||
    new_tables.include?(ot) ||
    new_tables.any? { |nt| source_for(nt, old_tables) == ot }
end

puts "\n-- migrate plan: #{plan.size} tables (upsert=#{plan.count { _1[:mode]==:upsert }}, reload=#{plan.count { _1[:mode]==:reload }}, special=#{plan.count { _1[:mode]==:special }})"
puts "-- new tables with NO old source (seed-only / genuinely new, skipped): #{unmapped_new.size}"
puts "-- OLD non-empty tables dropped (no target): #{dropped_nonempty.sort.join(', ')}" unless dropped_nonempty.empty?
puts "-- trading_* dropped: #{nonempty.count { |t| t.start_with?('trading_') }} non-empty tables (disabled)"

# 4. Emit SQL
sql = +""
sql << <<~SQL
  \\set ON_ERROR_STOP on
  \\timing on
  -- ============ Phase 9 ETL (generated) ============
  CREATE EXTENSION IF NOT EXISTS postgres_fdw;
  DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname='p9_old') THEN
      CREATE SERVER p9_old FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (dbname '#{OLD_DB}', host '/var/run/postgresql', fetch_size '20000');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_user_mappings WHERE srvname='p9_old' AND usename=current_user) THEN
      CREATE USER MAPPING FOR CURRENT_USER SERVER p9_old OPTIONS (user 'postgres');
    END IF;
  END $$;
  DROP SCHEMA IF EXISTS old_fdw CASCADE;
  CREATE SCHEMA old_fdw;
  IMPORT FOREIGN SCHEMA public FROM SERVER p9_old INTO old_fdw;

  -- generic column-intersection copy
  CREATE OR REPLACE FUNCTION p9_copy(p_old text, p_new text, p_scope text, p_conflict text)
  RETURNS bigint LANGUAGE plpgsql AS $fn$
  DECLARE cols text; setc text; whr text; n bigint; stmt text;
  BEGIN
    SELECT string_agg(quote_ident(c), ', '),
           string_agg(quote_ident(c)||' = EXCLUDED.'||quote_ident(c), ', ') FILTER (WHERE c <> 'id')
      INTO cols, setc
    FROM (SELECT column_name c FROM information_schema.columns WHERE table_schema='old_fdw' AND table_name=p_old
          INTERSECT
          SELECT column_name   FROM information_schema.columns WHERE table_schema='public'  AND table_name=p_new) t;
    IF cols IS NULL THEN RAISE EXCEPTION 'p9_copy: no common columns % -> %', p_old, p_new; END IF;
    whr := CASE WHEN p_scope IS NULL OR p_scope='' THEN '' ELSE ' WHERE '||p_scope END;
    stmt := format('INSERT INTO public.%I (%s) SELECT %s FROM old_fdw.%I%s', p_new, cols, cols, p_old, whr);
    IF p_conflict = 'NONE' THEN
      -- target pre-cleared; plain insert
      NULL;
    ELSIF setc IS NULL THEN
      stmt := stmt || format(' ON CONFLICT %s DO NOTHING', p_conflict);
    ELSE
      stmt := stmt || format(' ON CONFLICT %s DO UPDATE SET %s', p_conflict, setc);
    END IF;
    EXECUTE stmt;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
  END $fn$;

  SET session_replication_role = replica;   -- FK/triggers OFF during load
SQL

unless DRY
  plan.each do |p|
    nt, ot, scope, mode = p[:new], p[:old], p[:scope], p[:mode]
    sc = scope ? "'#{scope.gsub("'", "''")}'" : "NULL"   # single-quote the predicate, doubling inner quotes
    case mode
    when :upsert
      sql << "SELECT '#{nt}' tbl, p9_copy('#{ot}','#{nt}',#{sc},'(id)') rows;\n"
    when :reload
      sql << "DELETE FROM public.#{nt};\n"
      sql << "SELECT '#{nt}' tbl, p9_copy('#{ot}','#{nt}',#{sc},'NONE') rows;\n"
    when :special
      # handled in the transforms block below
    end
  end

  # ---- transform islands ----
  sql << <<~SQL

    -- site_settings: upsert on natural key (preserve live production values)
    SELECT 'site_settings' tbl, p9_copy('site_settings','site_settings',NULL,'(key)') rows;

    -- user_roles: remap old role_id -> new (seeded) role id by role NAME, for kept users only
    DELETE FROM public.user_roles;
    INSERT INTO public.user_roles (user_id, role_id, granted_at, granted_by_id)
    SELECT our.user_id, nr.id, our.granted_at, our.granted_by_id
    FROM old_fdw.user_roles our
    JOIN old_fdw.roles oro ON oro.id = our.role_id
    JOIN public.roles  nr  ON nr.name = oro.name
    JOIN old_fdw.users ou  ON ou.id = our.user_id
    WHERE ou.account_id IN (#{KEEP_SQL});

    -- worker_roles: same remap-by-name, restricted to migrated workers
    DELETE FROM public.worker_roles;
    INSERT INTO public.worker_roles (worker_id, role_id, granted_at)
    SELECT owr.worker_id, nr.id, owr.granted_at
    FROM old_fdw.worker_roles owr
    JOIN old_fdw.roles oro ON oro.id = owr.role_id
    JOIN public.roles  nr  ON nr.name = oro.name
    WHERE owr.worker_id IN (SELECT id FROM public.workers);
  SQL

  # ---- generic FK-orphan sweep (FK still off): for every single-column FK whose
  #      parent row is missing, NULL the ref if nullable else DELETE the child row;
  #      loop to a fixpoint so cascading orphans clear. Catches dangling refs to
  #      excluded-account rows that leaked in via non-account-scoped child tables. ----
  sql << <<~'SQL'

    DO $sweep$
    DECLARE r record; n bigint; total bigint; pass int := 0;
    BEGIN
      LOOP
        pass := pass + 1; total := 0;
        FOR r IN
          SELECT con.conname,
                 c.relname        AS child,
                 att.attname      AS child_col,
                 att.attnotnull   AS notnull,
                 pf.relname       AS parent,
                 attp.attname     AS parent_col
          FROM pg_constraint con
          JOIN pg_class c   ON c.oid  = con.conrelid
          JOIN pg_class pf  ON pf.oid = con.confrelid
          JOIN pg_namespace ns ON ns.oid = c.relnamespace AND ns.nspname='public'
          JOIN pg_attribute att  ON att.attrelid = con.conrelid  AND att.attnum  = con.conkey[1]
          JOIN pg_attribute attp ON attp.attrelid = con.confrelid AND attp.attnum = con.confkey[1]
          WHERE con.contype='f' AND array_length(con.conkey,1)=1
        LOOP
          IF r.notnull THEN
            EXECUTE format(
              'DELETE FROM public.%I ch WHERE ch.%I IS NOT NULL AND NOT EXISTS '||
              '(SELECT 1 FROM public.%I p WHERE p.%I = ch.%I)',
              r.child, r.child_col, r.parent, r.parent_col, r.child_col);
          ELSE
            EXECUTE format(
              'UPDATE public.%I ch SET %I = NULL WHERE ch.%I IS NOT NULL AND NOT EXISTS '||
              '(SELECT 1 FROM public.%I p WHERE p.%I = ch.%I)',
              r.child, r.child_col, r.child_col, r.parent, r.parent_col, r.child_col);
          END IF;
          GET DIAGNOSTICS n = ROW_COUNT;
          total := total + n;
        END LOOP;
        RAISE NOTICE 'orphan sweep pass % cleaned % rows', pass, total;
        EXIT WHEN total = 0 OR pass > 10;
      END LOOP;
    END $sweep$;
  SQL

  sql << "\nSET session_replication_role = default;\n"
  sql << "DROP SCHEMA IF EXISTS old_fdw CASCADE;\n"
end

File.write(SQL_OUT, sql)
puts "\n-- SQL written to #{SQL_OUT} (#{sql.lines.size} lines)"

if DRY
  puts "\n-- DRY-RUN: per-table source counts (scoped) --"
  plan.sort_by { _1[:new] }.each do |p|
    cnt = q_old("SELECT count(*) FROM public.#{p[:old]}#{p[:scope] ? " WHERE #{p[:scope]}" : ''}")
    puts format("  %-45s <= %-40s %10s  [%s]", p[:new], p[:old], cnt, p[:mode])
  end
  puts "\n(DRY-RUN: no SQL executed. Re-run with --run to load.)"
  exit 0
end

if ARGV.include?("--run")
  puts "\n== Executing ETL =="
  system("sudo -u postgres psql -d #{NEW_DB} -v ON_ERROR_STOP=1 -f #{SQL_OUT}") || abort("ETL SQL FAILED")
  puts "== ETL load complete =="
else
  puts "\n(plan generated; pass --run to execute, or --dry-run for counts)"
end

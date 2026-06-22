#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 9 A4 — validate the migrated new DB against the scoped live source.
#   * Row-count parity: scoped-OLD count vs NEW count per migrated table.
#     (NEW may be <= OLD where the FK-orphan sweep removed dangling child rows — flagged, not failed.)
#   * FK integrity: zero dangling single-column FKs remain in NEW.
#   * Scope: every NEW user belongs to a kept account; accounts == the 2 kept.
# Decrypt sanity is run separately via rails (see runbook A4).

require "set"
require "open3"

OLD_DB = "powernode_development"
NEW_DB = "powernode_new_development"
KEEP   = %w[019c0d95-0b83-76d4-aa5f-e8b102812415 019c0d95-0e69-790a-850b-580050e4e1d5].freeze
KEEP_SQL = KEEP.map { |u| "'#{u}'::uuid" }.join(",")

def cap(*a)
  o, e, s = Open3.capture3(*a)
  raise "FAIL #{a.join(' ')}\n#{e}" unless s.success?
  o
end
def q_old(s) = cap("sudo", "-u", "postgres", "psql", "-d", OLD_DB, "-tA", "-c", s).strip
def q_new(s) = cap("sudo", "-u", "postgres", "psql", "-d", NEW_DB, "-tA", "-c", s).strip

# rebuild the same migrate plan (mirror of etl.rb) so we validate exactly what was migrated
old_tables = q_old("SELECT tablename FROM pg_tables WHERE schemaname='public'").split("\n").map(&:strip).to_set
new_tables = q_new("SELECT tablename FROM pg_tables WHERE schemaname='public'").split("\n").map(&:strip).to_set
old_has_acct = q_old("SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='account_id'").split("\n").map(&:strip).to_set
HARD_SKIP = %w[schema_migrations ar_internal_metadata permissions role_permissions roles cookie_consents ai_marketplace_moderations].to_set

def source_for(nt, old_tables)
  return nt if old_tables.include?(nt)
  if nt.start_with?("system_sdwan_")
    c = "sdwan_" + nt.delete_prefix("system_sdwan_"); return c if old_tables.include?(c)
  elsif nt.start_with?("business_")
    b = nt.delete_prefix("business_")
    return b if old_tables.include?(b)
    return "ai_#{b}" if old_tables.include?("ai_#{b}")
  end
  nil
end

plan = []
new_tables.each do |nt|
  next if HARD_SKIP.include?(nt)
  src = source_for(nt, old_tables); next if src.nil?
  scope = old_has_acct.include?(src) ? "account_id IS NULL OR account_id IN (#{KEEP_SQL})" : nil
  scope = "id IN (#{KEEP_SQL})" if nt == "accounts"
  oc = q_old("SELECT count(*) FROM public.\"#{src}\"#{scope ? " WHERE #{scope}" : ''}").to_i
  next if oc.zero?
  nc = q_new("SELECT count(*) FROM public.\"#{nt}\"").to_i
  plan << { new: nt, old: src, oldc: oc, newc: nc }
end

exact = plan.select { |p| p[:newc] == p[:oldc] }
swept = plan.select { |p| p[:newc] < p[:oldc] }      # fewer in new => orphan sweep / special transform
over  = plan.select { |p| p[:newc] > p[:oldc] }      # MORE in new => unexpected (investigate)

puts "== A4 row-count parity (#{plan.size} migrated tables) =="
puts "  exact match : #{exact.size}"
puts "  new < old   : #{swept.size}  (orphan-swept / scoped transforms — expected for some)"
puts "  new > old   : #{over.size}   (UNEXPECTED)"
puts "\n-- new < old (top 25 by delta) --"
swept.sort_by { |p| p[:newc] - p[:oldc] }.first(25).each { |p| puts format("  %-44s old=%-8d new=%-8d (-%d)", p[:new], p[:oldc], p[:newc], p[:oldc]-p[:newc]) }
unless over.empty?
  puts "\n-- !! new > old (investigate) --"
  over.each { |p| puts format("  %-44s old=%-8d new=%-8d (+%d)", p[:new], p[:oldc], p[:newc], p[:newc]-p[:oldc]) }
end

puts "\n== scope checks =="
puts "  accounts in new      : #{q_new('SELECT count(*) FROM accounts')} (expect 2)"
puts "  users in new         : #{q_new('SELECT count(*) FROM users')} (expect 6)"
puts "  users w/ bad account : #{q_new("SELECT count(*) FROM users WHERE account_id IS NOT NULL AND account_id NOT IN (#{KEEP_SQL})")} (expect 0)"

puts "\n== FK integrity (dangling single-column FKs in new) =="
fk_orphans = q_new(<<~SQL)
  SELECT coalesce(sum(n),0) FROM (
    SELECT (xpath('/row/c/text()',
      query_to_xml(format(
        'SELECT count(*) c FROM public.%I ch WHERE ch.%I IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.%I p WHERE p.%I = ch.%I)',
        c.relname, att.attname, pf.relname, attp.attname, att.attname),
      false, true, '')))[1]::text::bigint AS n
    FROM pg_constraint con
    JOIN pg_class c  ON c.oid=con.conrelid
    JOIN pg_class pf ON pf.oid=con.confrelid
    JOIN pg_namespace ns ON ns.oid=c.relnamespace AND ns.nspname='public'
    JOIN pg_attribute att  ON att.attrelid=con.conrelid  AND att.attnum=con.conkey[1]
    JOIN pg_attribute attp ON attp.attrelid=con.confrelid AND attp.attnum=con.confkey[1]
    WHERE con.contype='f' AND array_length(con.conkey,1)=1
  ) s;
SQL
puts "  total dangling FK rows: #{fk_orphans} (expect 0)"

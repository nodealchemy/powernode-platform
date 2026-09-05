# frozen_string_literal: true

require "spec_helper"

# Ratchet against the ONE real duplicate the agent-hierarchy campaign found on
# the Autonomy page (HIER-P1): ai_dev_team_seed.rb used to create a SECOND,
# account-scoped `data_analyst` Ai::Agent named "Knowledge Graph Curator"
# beside the GLOBAL `assistant` canonical ai_utility_agents_seed.rb already
# seeds under that name — two independent seed files, two independent
# `find_or_create*` calls, both claiming to be the same logical agent.
# ai_dev_team_seed.rb now BINDS the global canonical instead of re-creating
# it (and does the same for "Documentation Specialist", promoted to a global
# canonical by ai_engineering_agents_seed.rb) — this spec is the guard that
# keeps that fix from regressing, and catches the same shape appearing under
# a new name.
#
# WHAT THIS DOES NOT FLAG (by design — see the app-7-consolidation duplicate-
# name audit): a GLOBAL canonical and its per-account CLONE sharing a name is
# the platform's ratified design (canonicals never execute; clones do), and
# an `Ai::Agent` sharing a display name with an unrelated `Ai::Skill` (e.g.
# "Release Manager" names both an Engineering-hierarchy monitor agent in
# ai_engineering_agents_seed.rb and an unrelated release-planning slash-
# command skill in ai_utility_agents_seed.rb's SPECIALIST_SKILLS array) is a
# different KIND, not a collision — this spec is scoped to the Ai::Agent-
# creating array literals only, never to Ai::Skill definitions, and each
# array is parsed as TOP-LEVEL hashes only so a nested skill_definitions/
# commands sub-hash's own `name:` can never be mistaken for the agent's.
#
# THE ORACLE: build the set of names GLOBALLY created (`find_or_create_global`
# / `find_or_initialize_global`, account_id nil, one canonical owner) and the
# set of names created ACCOUNT-SCOPED (`find_or_create_by!(account:, name:)`
# / `find_or_create_by(account:, name:)`), each read from the file that
# actually calls the creation method — never from a file that merely
# REFERENCES the name (a team-template member descriptor, a skill-assignment
# hash key, a read-only `resolve_for`/`find_by` lookup). The two sets must be
# disjoint: a name independently claimed as a global canonical by one file
# and as an account-scoped row by another is exactly the shape that
# regressed once.
#
# Purely a text scan (no Rails env / DB) so it runs fast and cannot be thrown
# off by another lane's in-flight migrations or dev-DB state.
RSpec.describe "no seed file independently re-creates a global canonical Ai::Agent's name" do
  seeds_dir = File.expand_path("../../../db/seeds", __dir__)

  def self.read(seeds_dir, file)
    path = File.join(seeds_dir, file)
    raise "expected #{file} to exist under #{seeds_dir} — has it moved?" unless File.exist?(path)

    File.read(path)
  end

  # Splits an array literal's body into its TOP-LEVEL `{ ... }` hash entries
  # by brace depth, so a nested hash (skill_definitions: [{ name: ... }]) is
  # never mistaken for a sibling top-level entry.
  def self.top_level_hashes(array_body)
    hashes = []
    depth = 0
    start = nil
    array_body.each_char.with_index do |ch, i|
      if ch == "{"
        start = i if depth.zero?
        depth += 1
      elsif ch == "}"
        depth -= 1
        if depth.zero? && start
          hashes << array_body[start..i]
          start = nil
        end
      end
    end
    hashes
  end

  # Every real agent entry in every array this spec reads carries both
  # `name:` and `agent_type:` at its OWN top level (never true of a nested
  # skill_definition/command hash), so requiring both, and taking `name:`'s
  # FIRST match in that top-level hash string (which always precedes any
  # nested one), pins the agent's own name specifically. The lookbehind
  # excludes `class_name:` / `agent_name:` / `role_name:` / `skill_name:` —
  # a bare `name:` scan matches those as false hits.
  def self.agent_names_from_array(text, const_pattern, file)
    body = text[/#{const_pattern}\s*=\s*\[(.*?)\n\]/m, 1]
    raise "could not locate `#{const_pattern} = [...]` in #{file} — has the constant been renamed?" unless body

    hashes = top_level_hashes(body)
    raise "#{const_pattern} in #{file} parsed no top-level hash entries — the scan is broken" if hashes.empty?

    names = hashes.filter_map do |h|
      next unless h.match?(/(?<![a-zA-Z_])agent_type:/)

      h.match(/(?<![a-zA-Z_])name:\s*["']([^"']+)["']/)&.captures&.first
    end
    raise "#{const_pattern} in #{file} parsed no agent name/agent_type pairs — the scan is broken" if names.empty?

    names
  end

  # ── GLOBAL canonical creation sites (account_id nil) ──────────────────────

  utility_text = read(seeds_dir, "ai_utility_agents_seed.rb")
  engineering_text = read(seeds_dir, "ai_engineering_agents_seed.rb")
  autonomy_text = read(seeds_dir, "autonomy_data_seed.rb")

  # UTILITY_AGENTS: every entry global (Ai::Agent.find_or_initialize_global).
  utility_agent_names = agent_names_from_array(utility_text, "UTILITY_AGENTS", "ai_utility_agents_seed.rb")

  # ENGINEERING_AGENTS: every entry global (find_or_initialize_global(slug:)).
  engineering_agent_names = agent_names_from_array(engineering_text, "ENGINEERING_AGENTS", "ai_engineering_agents_seed.rb")

  # Six more single-agent GLOBAL creations, each its own `find_or_create_global`
  # call rather than an array literal — matched on the `.name = "..."` (or
  # `name:` for ai_concierge_seed.rb's assign_attributes shape) right after the
  # call, bounded to a short window so a same-named field elsewhere in the
  # file can't be mistaken for this agent's.
  def self.single_global_name(text, slug, file)
    idx = text.index(/find_or_(?:create|initialize)_global\(slug:\s*["']#{Regexp.escape(slug)}["']\)/)
    raise "could not locate the find_or_*_global(slug: \"#{slug}\") call in #{file}" unless idx

    window = text[idx, 1200]
    match = window.match(/(?<![a-zA-Z_])name:\s*["']([^"']+)["']/) ||
            window.match(/\.name\s*=\s*["']([^"']+)["']/)
    raise "could not find a name assignment for slug #{slug} in #{file}" unless match

    match[1]
  end

  claude_agents_text = read(seeds_dir, "claude_agents_seed.rb")
  monitoring_text = read(seeds_dir, "monitoring_analytics_agents_seed.rb")
  concierge_text = read(seeds_dir, "ai_concierge_seed.rb")

  single_global_names = [
    single_global_name(claude_agents_text, "strategic-planner", "claude_agents_seed.rb"),
    single_global_name(claude_agents_text, "research-analyst", "claude_agents_seed.rb"),
    single_global_name(monitoring_text, "system-performance-monitor", "monitoring_analytics_agents_seed.rb"),
    single_global_name(monitoring_text, "system-analytics-intelligence", "monitoring_analytics_agents_seed.rb"),
    single_global_name(monitoring_text, "system-health-monitor", "monitoring_analytics_agents_seed.rb"),
    single_global_name(monitoring_text, "system-quality-assurance", "monitoring_analytics_agents_seed.rb"),
    single_global_name(concierge_text, "powernode-assistant", "ai_concierge_seed.rb")
  ]

  # autonomy_data_seed.rb's `extra_agents` array is GLOBAL only for the slugs
  # GLOBAL_AUTONOMY_AGENT_SLUGS names — the rest of that same array is
  # account-scoped (see below). Parsed as (slug, name) pairs, from TOP-LEVEL
  # hashes only, so each entry routes to the right set by its own slug.
  def self.extra_agent_pairs(text)
    body = text[/extra_agents\s*=\s*\[(.*?)\n\]/m, 1]
    raise "could not locate `extra_agents = [...]` in autonomy_data_seed.rb" unless body

    top_level_hashes(body).filter_map do |h|
      slug = h.match(/(?<![a-zA-Z_])slug:\s*["']([^"']+)["']/)&.captures&.first
      name = h.match(/(?<![a-zA-Z_])name:\s*["']([^"']+)["']/)&.captures&.first
      [ slug, name ] if slug && name
    end
  end

  extra_agents = extra_agent_pairs(autonomy_text).uniq
  raise "extra_agents in autonomy_data_seed.rb parsed no slug/name pairs — the scan is broken" if extra_agents.empty?

  global_autonomy_slugs = autonomy_text[/GLOBAL_AUTONOMY_AGENT_SLUGS\s*=\s*%w\[(.*?)\]/m, 1]
  raise "could not locate GLOBAL_AUTONOMY_AGENT_SLUGS in autonomy_data_seed.rb" unless global_autonomy_slugs

  global_autonomy_slugs = global_autonomy_slugs.split
  raise "GLOBAL_AUTONOMY_AGENT_SLUGS parsed empty" if global_autonomy_slugs.empty?

  extra_agents_global_names = extra_agents.select { |slug, _| global_autonomy_slugs.include?(slug) }.map(&:last)
  extra_agents_account_names = extra_agents.reject { |slug, _| global_autonomy_slugs.include?(slug) }.map(&:last)

  GLOBAL_AGENT_NAMES = (
    utility_agent_names + engineering_agent_names + single_global_names + extra_agents_global_names
  ).uniq.freeze

  # ── ACCOUNT-SCOPED creation sites (account_id set, via find_or_create_by!/by) ─

  dev_team_text = read(seeds_dir, "ai_dev_team_seed.rb")
  todo_team_text = read(seeds_dir, "ai_todo_team_seed.rb")

  # ai_dev_team_seed.rb's `agents_data` array feeds ONE loop that always calls
  # Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) — no
  # slug routing to a global path exists in this file, unlike autonomy_data_seed.
  dev_team_agent_names = agent_names_from_array(dev_team_text, "agents_data", "ai_dev_team_seed.rb")

  # ai_todo_team_seed.rb's agent array isn't a single named constant (unlike
  # UTILITY_AGENTS/ENGINEERING_AGENTS/agents_data), so it is scanned directly:
  # every top-level `name:` (the lookbehind excludes `agent_name:`, a
  # role-mapping reference to an agent already created), narrowed to the demo
  # "Todo *" agents this file actually creates. The file also carries MCP
  # server / memory-pool names ('Filesystem MCP', 'Todo App Team Memory')
  # that are a different model entirely and must not be swept in.
  todo_agent_names = todo_team_text.scan(/(?<![a-zA-Z_])name:\s*["']([^"']+)["']/).flatten
                                    .select { |n| n.start_with?("Todo ") && !n.start_with?("Todo App") }
  raise "ai_todo_team_seed.rb parsed no 'Todo *' agent names — the scan is broken" if todo_agent_names.empty?

  ACCOUNT_SCOPED_AGENT_NAMES = (dev_team_agent_names + extra_agents_account_names + todo_agent_names).uniq.freeze

  it "parsed a non-trivial global-canonical name set (scan sanity)" do
    expect(GLOBAL_AGENT_NAMES.size).to be >= 10
  end

  it "parsed a non-trivial account-scoped name set (scan sanity)" do
    expect(ACCOUNT_SCOPED_AGENT_NAMES.size).to be >= 5
  end

  it "creates no account-scoped Ai::Agent whose name a different file already claims as a global canonical" do
    collisions = ACCOUNT_SCOPED_AGENT_NAMES & GLOBAL_AGENT_NAMES

    expect(collisions).to be_empty,
      "these names are BOTH a global canonical (ai_utility_agents_seed.rb / " \
      "ai_engineering_agents_seed.rb / claude_agents_seed.rb / " \
      "monitoring_analytics_agents_seed.rb / ai_concierge_seed.rb / a GLOBAL_AUTONOMY_AGENT_SLUGS " \
      "entry) AND independently created account-scoped (ai_dev_team_seed.rb / " \
      "ai_todo_team_seed.rb / a non-global autonomy_data_seed.rb entry): " \
      "#{collisions.sort.join(', ')} — this is the Knowledge Graph Curator shape " \
      "(HIER-P1): delete the account-scoped creation and bind the global canonical instead " \
      "(Ai::Agent.global.find_by(slug: ...)), the way ai_dev_team_seed.rb already does for " \
      "Knowledge Graph Curator and Documentation Specialist."
  end
end

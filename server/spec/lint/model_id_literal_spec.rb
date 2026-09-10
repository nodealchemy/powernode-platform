# frozen_string_literal: true

require "spec_helper"
require "find"

# CAMPAIGN 01a08c9b, increment E3 — model-id governance gets an enforcement.
#
# The operator rule is old ("AI model names must never be hardcoded — not in
# services, not in specs", 2026-06-11) and until now nothing checked it. The
# audit found ~24 genuine hardcoded ids, twelve of them as `|| "model-id"`
# fallbacks in service logic, and observed that `pattern-validation.sh` has 38
# checks touching none of it and `spec/lint/` had ten ratchets touching none of
# it either.
#
# WHY IT MATTERS, stated once so the rule is not cargo-culted: a hardcoded id
# rots (models are retired), breaks provider portability, and — the failure
# that actually bites — a `||` fallback sends the WRONG PROVIDER'S model id to
# a client. `intent_capture_service.rb:300` carries a comment describing
# exactly that: handing `"gpt-4.1-mini"` to an Anthropic HTTP client, which 404s.
# A fallback in that position does not add resilience; it converts a clean
# "no model configured" into a confusing upstream error.
#
# ── TWO RULES, DELIBERATELY DIFFERENT IN STRICTNESS ──────────────────────────
#
# 1. FALLBACK SHAPE (`|| "claude-…"`) — ZERO TOLERANCE, no baseline. This is
#    the Class-A shape the audit measured at 92% precision, it is always wrong,
#    and E3 removed every instance. A new one fails immediately.
#
# 2. BARE LITERAL — RATCHET with a recorded baseline. Model ids legitimately
#    appear in catalog files (a pricing table, a provider spec, a family
#    classifier) and in seeds that pin a demo agent. Those are listed below
#    with a reason each, by COUNT, so a listed file cannot grow and an
#    unlisted one cannot appear. The oracle is EQUALITY, not `<=`: a DROP is
#    progress that must be recorded here in the same change, because a ceiling
#    nobody re-tightens is not a ratchet.
#
# ── SCOPE, AND WHAT IS HONESTLY NOT COVERED ──────────────────────────────────
#
# Production code only: `app/`, `lib/`, `config/`, `db/` under `server/`,
# `worker/` and every extension including the private ones — plus two roots
# the E3 review found outside that walk: `server/scripts/` (operator scripts,
# two of which WROTE a retired `supported_models` catalog onto providers) and
# `frontend/src/` (shipped form defaults). Specs are NOT scanned, on either
# side: `spec/` by construction, and frontend `*.test.ts(x)`, `__tests__/`,
# `test/` and mocks by the same rule. That is a real gap, not an oversight — 113 spec files carry a model
# literal today, and fixing them means routing each through a factory's
# `supported_models`, which is its own increment. A green run here does NOT
# mean "no hardcoded ids anywhere"; it means none in code that ships.
#
# The walk is Ruby `Find` over the tree, never a shell `grep`: a plain `grep`
# in this repo is a shell function that hides `extensions/private`, and an
# absence check piped through `head` is capped rather than complete.
# A MODULE, not constants inside the RSpec block. A constant assigned inside a
# block lands on Object and can be clobbered by a same-named constant in another
# spec file; and `described_class` is nil here because the describe argument is a
# string, so the constants have to be reachable by an explicit name anyway.
module ModelIdLintRules
  module_function

  REPO_ROOT = File.expand_path("../../..", __dir__)
  SELF_REL = "server/spec/lint/model_id_literal_spec.rb"

  # A model id is a known family followed by a version-bearing suffix. The
  # DIGIT requirement is what keeps `"claude-code"` (a provider slug) and
  # `"claude"` (a git branch prefix in create_pr_handler) out: neither names a
  # model, and flagging them would train people to add exemptions.
  FAMILIES = %w[claude gpt gemini grok llama mistral deepseek qwen].freeze
  MODEL_ID = /
    ['"`]                                  # opening quote (backtick: a TS
                                           #  template literal is a string too)
    (?:#{Regexp.union(FAMILIES)})          # a known family
    -[a-z0-9-]*\d[a-z0-9._-]*              # a suffix carrying at least one digit
                                           # (hyphens allowed BEFORE the digit, or
                                           #  "claude-opus-4-8" would not match)
    ['"`]                                  # closing quote
  /xi

  # The Class-A shape: an `||` (or `.presence ||`) whose right-hand side is a
  # model-id literal. Matched on the same line, which is how every instance the
  # audit found is written.
  #
  # The OPERATOR is `||` / `||=` in Ruby and `??` / `??=` in TypeScript. The
  # E3 review planted `model ||= 'gpt-4o-mini'` in a baselined file and the
  # suite stayed green: the old pattern wanted whitespace right after `||`, and
  # `||=` puts an `=` there. That is the shape most likely to hide in exactly
  # the catalog and seed files the ratchet already tolerates literals in.
  FALLBACK = /(?:\|\||\?\?)=?\s*#{MODEL_ID}/

  # Directories that ship. `spec/` is excluded by construction — see the header.
  SCANNED_SUBDIRS = %w[app lib config db].freeze

  # Roots OUTSIDE the server/worker/extension app layout, each with the file
  # types it holds. Added by the E3 review, which found 22 literals the walk
  # could not see (18 in server/scripts, 4 in frontend/src).
  EXTRA_ROOTS = {
    "server/scripts" => %w[.rb .rake],
    "frontend/src" => %w[.ts .tsx]
  }.freeze

  # Frontend test files are specs by another name; the rule that keeps
  # `spec/` out keeps these out too.
  FRONTEND_TEST_FILE = %r{(?:\.(?:test|spec)\.tsx?\z|/__tests__/|/__mocks__/|/mocks/|/test/|/test-utils(?:/|\.tsx?\z)|/setupTests\.tsx?\z)}

  RUBY_COMMENT = /\A\s*#/
  TS_COMMENT = %r{\A\s*(?://|/\*|\*)}

  def scan_roots(repo_root = REPO_ROOT)
    roots = []
    [ "server", "worker" ].each { |app| roots << File.join(repo_root, app) }
    Dir.glob(File.join(repo_root, "extensions", "*")).each do |ext|
      next unless File.directory?(ext)

      # An extension nests its own server/ and worker/; private extensions live
      # one level deeper and are included on purpose.
      roots.concat(Dir.glob(File.join(ext, "{server,worker}")))
      roots.concat(Dir.glob(File.join(ext, "*", "{server,worker}")))
    end
    roots.select { |path| File.directory?(path) }
  end

  def source_files(repo_root = REPO_ROOT)
    files = []
    scan_roots(repo_root).each do |root|
      SCANNED_SUBDIRS.each do |sub|
        collect(File.join(root, sub), %w[.rb .rake], repo_root, files)
      end
    end
    EXTRA_ROOTS.each do |rel_root, extensions|
      collect(File.join(repo_root, rel_root), extensions, repo_root, files)
    end
    files.uniq.sort
  end

  def collect(dir, extensions, repo_root, files)
    return unless File.directory?(dir)

    Find.find(dir) do |path|
      Find.prune if File.basename(path) == "node_modules"
      next unless File.file?(path)
      next unless path.end_with?(*extensions)

      rel = path.delete_prefix("#{repo_root}/")
      next if rel == SELF_REL
      next if rel.start_with?("frontend/") && rel.match?(FRONTEND_TEST_FILE)

      files << [ rel, path ]
    end
  end

  # A full-line comment cannot choose a model. The marker differs by language.
  def comment_line?(rel, line)
    line.match?(rel.end_with?(".ts", ".tsx") ? TS_COMMENT : RUBY_COMMENT)
  end

  # Catalog files: a model id here is DATA about models, which is the one place
  # the id belongs. Each entry carries its reason and its exact count.
  #
  # Lower a count when you remove a line; delete the entry at zero. Never raise
  # one without saying why in the same change.
  # Fallbacks this rule cannot enforce yet, each named so the debt is visible
  # and self-expiring. EMPTY: its one entry — agent_management_tool.rb, whose
  # fallback stamped a retired id as an agent's model pin — was paid by
  # resolving through the provider's own catalog and refusing when that has
  # nothing.
  #
  # A two-way oracle, the shape the tool-permission guard already uses: a NEW
  # offender fails, and so does a stale entry here. An entry needs a reason,
  # and the spec fails the moment that reason stops being true.
  FALLBACK_EXEMPTIONS = {}.freeze

  BASELINE = {
    # — the model catalog proper —
    "server/app/models/ai/provider_catalog.rb" => [ 33, "Ai::ProviderCatalog::CONFIGS — the built-in provider catalog itself" ],
    "server/app/services/ai/provider_management_service.rb" => [ 27, "MODEL_PRICING: the per-1k price table, keyed by model id" ],
    "server/app/services/ai/provider_management_service/provider_specs.rb" => [ 2, "built-in provider specs: the seed catalog for a provider created from a template" ],
    "server/app/services/ai/providers/default_config.rb" => [ 6, "per-provider default_model catalog — the value `Provider#default_model` resolves to" ],
    "server/app/services/ai/providers/sync/openai.rb" => [ 13, "classifies a SYNCED id into context window / capabilities / rank; reads ids, never invents one" ],
    "server/app/services/ai/providers/sync/azure.rb" => [ 6, "same classifier shape for Azure deployments" ],
    "server/app/models/concerns/ai/provider/configurable.rb" => [ 2, "masked configuration fallback, mirrors default_config.rb for a provider with no row" ],
    # — seeded content. OUT OF E3's SCOPE and recorded rather than fixed: a seed
    #   that creates an agent must pin something, and Ai::Agent validates the pin
    #   against its bound provider, so these are checked at write time. Capped
    #   here so the set cannot grow; migrating them onto a resolver is its own
    #   increment (see the E3 report).
    "server/db/seeds/ai_dev_team_seed.rb" => [ 6, "seeded dev-team agents pin their model" ],
    "server/db/seeds/ai_example_templates_seed.rb" => [ 8, "seeded example agent templates" ],
    "server/db/seeds/ai_governance_seed.rb" => [ 3, "seeded governance agents" ],
    "server/db/seeds/ai_todo_team_seed.rb" => [ 1, "seeded todo-team agent" ],
    "server/db/seeds/claude_agents_seed.rb" => [ 1, "seeded Claude agent" ],
    "server/lib/tasks/configure_claude.rake" => [ 4, "operator rake task that configures a Claude provider" ],
    "server/db/seeds/devops_container_templates.rb" => [ 2, "seeded container template pins a model for a demo agent" ],
    "server/db/seeds/kb/ai_orchestration_articles.rb" => [ 1, "prose in a seeded KB article, not an executable choice" ],
    "extensions/marketing/server/db/seeds/marketing_demo_data_seed.rb" => [ 1, "seeded demo data" ],
    # — analytics that reads an id back out of recorded usage —
    "server/app/services/ai/analytics/cost_analysis_service/breakdown.rb" => [ 1, "cost-advice heuristic over ALREADY-RECORDED usage rows" ],
    # — server/scripts (root added by the E3 review). The two scripts that
    #   WROTE a retired catalog onto providers now re-sync from the provider's
    #   own API instead and carry no literal, so they are absent here. These two
    #   still choose models by name and are recorded, not blessed: —
    "server/scripts/diagnostics/check_and_update_agent_models.rb" => [ 6, "one-off diagnostic that REWRITES agent pins from a task-name heuristic; the ids are retired — capped here, owed a resolver rewrite (E3 review report)" ],
    "server/scripts/setup/create_image_generation_agent.rb" => [ 2, "setup script picks a per-provider-type default for the agent it creates; owed Provider#default_model (E3 review report)" ],
    # — frontend/src (root added by the E3 review) —
    "frontend/src/features/onboarding/ProviderCredentialForm.tsx" => [ 3, "onboarding form PRE-FILLS a default_model field per provider type; the operator can edit it, but a shipped default rots — owed a read of the provider catalog" ],
    "frontend/src/features/ai/devops/components/WorkflowTab.tsx" => [ 1, "an example model id inside a textarea PLACEHOLDER showing the JSON shape — illustrative, never submitted" ]
    # (cost_calculation_service.rb was here at 1; its only hit is a full-line
    #  @param comment, which the scan correctly ignores — entry deleted at zero.)
  }.freeze

  # PRIVATE EXTENSIONS ARE SCANNED BY THE FALLBACK RULE AND EXCLUDED FROM THE
  # RATCHET, and the asymmetry is forced rather than chosen.
  #
  # This file is CORE and is published to the public mirror, so it must not name
  # a private extension (core-purity gate #9) and must run in a clone where that
  # tree is absent. A per-file COUNT for a private path would therefore fail two
  # ways: the name would breach the gate, and in a public clone the file would
  # scan to 0 against a recorded 5 and read as a "tightening" on every run.
  #
  # The fallback rule has no baseline, so it works identically in both clones and
  # DOES cover private extensions — which is the rule that matters, because that
  # is the shape that is always wrong. Bare literals inside a private extension
  # need a ratchet of their own, inside that extension, the way
  # extension_namespace_ratchet_spec.rb has an extension-side twin.
  def private_extension_path?(rel)
    rel.start_with?("extensions/private/")
  end

  def scan(pattern, skip_private: false)
    counts = Hash.new(0)
    source_files.each do |rel, path|
      next if skip_private && private_extension_path?(rel)

      File.foreach(path) do |line|
        # A full-line comment cannot choose a model. A trailing comment is not
        # stripped: telling one from a `#` inside a string needs a lexer, and
        # the conservative direction is to flag.
        next if comment_line?(rel, line)

        counts[rel] += 1 if line.match?(pattern)
      end
    end
    counts
  end

  # One line's worth of the same rule, for the matcher examples. `as:` names
  # the file the source would live in, so the comment rule is the real one.
  def flags?(pattern, source, as: "example.rb")
    source.each_line.any? { |line| !comment_line?(as, line) && line.match?(pattern) }
  end
end

RSpec.describe "model-id literals in production code" do
  R = ModelIdLintRules

  describe "the matchers themselves" do
    def matches?(pattern, source) = R.flags?(pattern, source)
    def ts_matches?(pattern, source) = R.flags?(pattern, source, as: "example.tsx")

    it "flags a fallback in either quote style" do
      expect(matches?(R::FALLBACK, 'model = provider&.default_model || "gpt-4o-mini"')).to be true
      expect(matches?(R::FALLBACK, "model = agent['model'] || 'gpt-4'")).to be true
      expect(matches?(R::FALLBACK, 'x = cred&.provider&.default_model.presence || "claude-haiku-4-5"')).to be true
    end

    # E3 review F4, planted: before this the operator had to be `||` followed
    # by whitespace, so `||=` walked straight past the zero-tolerance rule.
    it "flags the ||= and TypeScript ?? / ??= forms, and not their literal-free twins" do
      expect(matches?(R::FALLBACK, "model ||= 'gpt-4o-mini'")).to be true
      expect(matches?(R::FALLBACK, 'config["model"] ||= "claude-haiku-4-5"')).to be true
      expect(matches?(R::FALLBACK, "model ||= provider.default_model")).to be false

      expect(ts_matches?(R::FALLBACK, "const model = cfg.model ?? 'gpt-4o'")).to be true
      expect(ts_matches?(R::FALLBACK, "model ??= `claude-sonnet-5`")).to be true
      expect(ts_matches?(R::FALLBACK, "const model = cfg.model ?? provider.defaultModel")).to be false
    end

    it "accepts a resolution with no literal on the right" do
      expect(matches?(R::FALLBACK, "model = provider&.default_model || provider.available_models.first")).to be false
      expect(matches?(R::FALLBACK, 'prefix = config["branch_prefix"] || "claude"')).to be false
    end

    it "flags a bare literal and ignores names that only look like one" do
      expect(matches?(R::MODEL_ID, 'MODELS = [ "claude-opus-4-8" ]')).to be true
      expect(matches?(R::MODEL_ID, 'id = "gemini-2.0-flash"')).to be true
      # A provider SLUG and a branch prefix carry no version digit.
      expect(matches?(R::MODEL_ID, 'SLUG = "claude-code"')).to be false
      expect(matches?(R::MODEL_ID, 'prefix = "claude"')).to be false
    end

    it "ignores a full-line comment but still flags the same text as code" do
      expect(matches?(R::MODEL_ID, '  # the old chain hardcoded "claude-3-sonnet-20240229"')).to be false
      expect(matches?(R::MODEL_ID, '  model = "claude-3-sonnet-20240229"')).to be true
    end

    it "applies the TypeScript comment rule to a .tsx line, and not the Ruby one" do
      expect(ts_matches?(R::MODEL_ID, "  // defaults used to be 'claude-sonnet-4-6'")).to be false
      expect(ts_matches?(R::MODEL_ID, "   * e.g. 'gpt-4o'")).to be false
      expect(ts_matches?(R::MODEL_ID, "  defaultValue: 'claude-sonnet-4-6',")).to be true
      # A `#` line in TS is code (a private field), not a comment.
      expect(ts_matches?(R::MODEL_ID, "  #model = 'gpt-4o';")).to be true
    end
  end

  it "walks a non-trivial tree, including the extensions (an empty sweep is not a pass)" do
    files = R.source_files
    expect(files.size).to be > 500
    expect(files.map(&:first)).to include(a_string_starting_with("worker/app/"))
    expect(files.map(&:first)).to include(a_string_starting_with("extensions/"))
  end

  it "reaches server/scripts and frontend/src, and leaves the frontend's tests out" do
    rels = R.source_files.map(&:first)
    scripts = rels.grep(%r{\Aserver/scripts/})
    frontend = rels.grep(%r{\Afrontend/src/})

    expect(scripts.size).to be > 10
    expect(frontend.size).to be > 500
    expect(frontend).to all(match(/\.tsx?\z/))
    expect(frontend.grep(R::FRONTEND_TEST_FILE)).to be_empty
    # The exclusion must bite on something real, or it is asserting nothing.
    expect(Dir.glob(File.join(R::REPO_ROOT, "frontend/src/**/*.test.{ts,tsx}"))).not_to be_empty
  end

  it "has NO `|| \"model-id\"` fallback anywhere in production code" do
    offenders = R.scan(R::FALLBACK).keys.sort
    exempt = R::FALLBACK_EXEMPTIONS.keys.sort
    unexpected = offenders - exempt
    stale = exempt - offenders

    expect(stale).to be_empty, <<~STALE
      A FALLBACK_EXEMPTIONS entry names a file that no longer has a fallback.
      The debt is paid — delete the line so the rule goes back to zero tolerance:

      #{stale.join(", ")}
    STALE

    expect(unexpected).to be_empty, <<~MSG
      A model-id FALLBACK is never correct.

      `x || "gpt-4o-mini"` does not add resilience — it sends one provider's
      model id to another provider's client (see the comment at
      ai/provisioning/intent_capture_service.rb), turning a clean
      "no model configured" into a 404 from upstream.

      Resolve through the provider instead — `Provider#default_model`, then
      `#available_models.first` — and RAISE or return an explicit error when
      nothing resolves. `Provider#default_model_for_devops` is the worked
      example. Do not soften the fallback; delete it.

      Files: #{unexpected.join(", ")}
    MSG
  end

  it "keeps bare model-id literals to the catalog files, at exactly the recorded counts" do
    # A file exempt from the FALLBACK rule is exempt here too, because the one
    # literal it carries IS that fallback — baselining it separately would mean
    # two places to re-tighten when lane 10 folds the fix in, and the second
    # one would be forgotten. One debt, one line.
    actual = R.scan(R::MODEL_ID, skip_private: true).except(*R::FALLBACK_EXEMPTIONS.keys)
    baseline = R::BASELINE

    regressions = actual.reject { |file, count| baseline.key?(file) && baseline[file].first >= count }
                        .map { |file, count| "#{file}: #{count} (allowed #{baseline[file]&.first || 0})" }
    tightenings = baseline.filter_map do |file, (count, _reason)|
      "#{file}: #{actual.fetch(file, 0)} (recorded #{count})" if actual.fetch(file, 0) < count
    end

    expect(regressions).to be_empty, <<~MSG
      Model-id literal in a file that is not a catalog.

      A model id belongs in data about models (the pricing table, a provider
      spec, a family classifier), not in a decision. Route the choice through
      the provider — Ai::Agent pins one at
      mcp_metadata.model_config.model and Provider#default_model resolves the
      rest — or add the file to BASELINE with a reason if it is genuinely a
      catalog.

      #{regressions.join("\n      ")}
    MSG

    expect(tightenings).to be_empty, <<~MSG
      Literal counts dropped below the recorded baseline — progress that must be
      recorded in the same change, or the ceiling stops meaning anything.
      Lower these entries (or delete them at zero) in #{File.basename(R::SELF_REL)}:

      #{tightenings.join("\n      ")}
    MSG
  end
end

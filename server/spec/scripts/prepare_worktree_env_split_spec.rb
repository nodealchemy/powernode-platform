# frozen_string_literal: true

require "spec_helper"

# IMP-a31d6e31023e — a variable BUNDLER must see cannot live in a file only Rails
# loads. `scripts/prepare-worktree.sh` wrote POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1
# into each isolated worktree's `server/.env`, which splits the two reads of
# `discover_extension_gems` (extensions_loader_helper.rb) across dotenv:
#
#   * Bundler evaluates `server/Gemfile` (which calls the helper) BEFORE any Ruby
#     of the app runs. A `.env` is not read at that point, so the private
#     extensions never become path gems and their models never load.
#   * dotenv-rails installs `config.before_configuration { load }`
#     (dotenv-3.2.0/lib/dotenv/rails.rb), reading `<Rails.root>/.env` during app
#     boot — so by the time `server/spec/rails_helper.rb` calls the SAME helper the
#     variable IS set, and it loads those extensions' factories and spec-support
#     helpers for gems that were never bundled.
#
# Observed by execution on this checkout (dotenv 3.2.0 / dotenv-rails 3.2.0):
# with the flag only in a `.env` next to Rails.root, Bundler declared
# ["powernode_marketing", "powernode_supply_chain", "powernode_system"] with
# ENV unset, while the same helper called after the Rails::Application class was
# defined reported private=["business", "trading"].
#
# That is precisely the hazard rails_helper's own comment says the shared-helper
# design avoids ("loading an on-disk-but-inactive extension's factories whose
# models aren't loaded"). Private extensions are selected by
# `BUNDLE_GEMFILE=Gemfile.private` (server/Gemfile.private:12 sets the flag with
# `||=` at Gemfile-evaluation time, on the correct side of dotenv) — never by `.env`.
#
# This guard is generic: NO env var read while the Gemfile is evaluated may be
# written into a dotenv file by prepare-worktree.sh, nor appear in the checked-in
# `server/.env.example` template.
#
# SCOPE — what this does NOT cover: the hazard is a property of ANY dotenv file
# next to Rails.root, but only the generated/committed files above are inspected.
# A hand-written `server/.env` (in a worktree or in MAIN) carrying a Gemfile-time
# var reproduces the identical split with this guard green. Catching that needs a
# RUNTIME detector — rails_helper comparing what the bundle actually contains
# against what `discover_extension_gems` reports, in both directions.
RSpec.describe "prepare-worktree.sh dotenv writes vs Gemfile-time env reads (IMP-a31d6e31023e)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  script_path = File.join(repo_root, "scripts/prepare-worktree.sh")
  env_example_path = File.join(repo_root, "server/.env.example")

  # Files evaluated by BUNDLER, before any Railtie (and therefore before dotenv) runs.
  # Derived, not hard-coded: whatever server/Gemfile{,.private} `require_relative`s is
  # also Gemfile-evaluation-time code, so a future helper is picked up automatically.
  bundler_entrypoints = %w[server/Gemfile server/Gemfile.private].freeze

  # `ENV["K"]`, `ENV['K']`, `ENV.fetch("K")`, `ENV.fetch('K')` — the single-quoted
  # form is already in use in this repo (worker/spec/spec_helper.rb:92), and a
  # regex that saw only the double-quoted `[]` form would miss a future read.
  env_read_re = /ENV\s*(?:\[\s*['"]|\.fetch\(\s*['"])([A-Z_][A-Z0-9_]*)/

  # Shell variables that name a dotenv DESTINATION in prepare-worktree.sh.
  env_file_target_vars = %w[file dst ENV_TEST_LOCAL].freeze

  # The two write shapes the key extraction below understands.
  env_upsert_call_re = /env_upsert\s+"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"\s+([A-Z_][A-Z0-9_]*)/
  printf_arg_re = /(?:^\s*|echo\s+|printf\s+)['"]([A-Z_][A-Z0-9_]*)=/
  env_upsert_body_re = /printf\s+'%s=%s\\n'\s+"\$key"\s+"\$val"/
  # A payload beginning with `#` is a dotenv COMMENT — it defines no key. The
  # script's redirection lands on whichever printf argument comes last, and in
  # the no-free-redis-lane branch that argument is a comment line.
  #
  # This is the exact MIRROR of printf_arg_re, differing only in the payload,
  # and the anchoring is load-bearing rather than tidiness. A bare /['"]\s*#/
  # also matches a trailing shell comment, because the closing quote of
  # `> "$dst"` sits immediately before it — which would have exempted
  # `cat "$src" >> "$dst"  # append` and every other unrecognised shape that
  # happens to carry a comment, in a densely commented script.
  comment_arg_re = /(?:^\s*|echo\s+|printf\s+)['"]\s*#/
  # Any KEY= payload anywhere on the line, QUOTED OR NOT. Deliberately looser
  # than printf_arg_re: it exists only to REFUSE the comment exemption, so
  # looser is safer. Requiring a preceding quote would miss `echo FOO=bar`, and
  # a line combining an unquoted key with a comment would then be skipped.
  key_payload_anywhere_re = /(?:^|['"\s])[A-Z_][A-Z0-9_]*=/

  let(:script) { File.read(script_path) }

  # Run the REAL extraction over an arbitrary snippet. The examples below must
  # exercise the same code the containment anchor uses, not a copy of it.
  def unrecognised_writes_in(line)
    unrecognised_env_writes_from(line)
  end

  def keys_in(line)
    dotenv_keys_from(line)
  end

  # Transitive closure of the Gemfile-evaluation-time source files.
  let(:gemfile_time_sources) do
    seen = []
    queue = bundler_entrypoints.dup
    until queue.empty?
      rel = queue.shift
      next if seen.include?(rel)

      path = File.join(repo_root, rel)
      next unless File.exist?(path)

      seen << rel
      File.read(path).scan(/require_relative\s+['"]([^'"]+)['"]/).flatten.each do |req|
        target = File.expand_path(req, File.dirname(path))
        target += ".rb" unless target.end_with?(".rb")
        next unless target.start_with?("#{repo_root}/")

        queue << target.delete_prefix("#{repo_root}/")
      end
    end
    seen
  end

  # Env vars read while the Gemfile is being evaluated.
  let(:gemfile_time_keys) do
    gemfile_time_sources.flat_map { |rel|
      File.read(File.join(repo_root, rel)).scan(env_read_re).flatten
    }.uniq
  end

  # Env vars prepare-worktree.sh writes into a dotenv file. Two write shapes:
  # `env_upsert "$dst" KEY value` (server/.env) and a quoted `"KEY=..."` printf
  # argument redirected into an env file (server/.env.test.local).
  # define_method, NOT def: these bodies close over the regex locals declared
  # above, and `def` would open a new scope that cannot see them.
  define_method(:dotenv_keys_from) do |source|
    (source.scan(env_upsert_call_re).flatten + source.scan(printf_arg_re).flatten).uniq
  end

  let(:dotenv_written_keys) { dotenv_keys_from(script) }

  # CONTAINMENT anchor: every redirection in the script that targets a dotenv
  # destination must be one of the two shapes parsed above. A THIRD write shape
  # (e.g. a heredoc, or `cat >> "$dst"`) then fails HERE rather than slipping past
  # the disjointness check silently with its keys unseen.
  define_method(:unrecognised_env_writes_from) do |source|
    source.lines.each_with_index.filter_map do |line, idx|
      target = line[/>>?\s*"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"/, 1]
      next if target.nil? || !env_file_target_vars.include?(target)
      next if line.match?(env_upsert_body_re) || line.match?(printf_arg_re)
      # Key-less by construction: a comment payload and NO key payload anywhere
      # on the line. The second half is what keeps this a narrowing of the
      # guard rather than a hole in it — a line carrying both still fails.
      next if line.match?(comment_arg_re) && !line.match?(key_payload_anywhere_re)

      "#{idx + 1}: #{line.strip}"
    end
  end

  let(:unrecognised_env_writes) { unrecognised_env_writes_from(script) }

  it "still finds the script and parses both of its dotenv write shapes" do
    expect(File.exist?(script_path)).to be(true), "missing #{script_path}"
    expect(script).to include("env_upsert")
    # PRESENCE anchor: if these stop parsing, the disjointness assertion below
    # would pass vacuously rather than because the split was closed.
    expect(dotenv_written_keys).to include("DATABASE_NAME", "TEST_ENV_NUMBER")
    expect(unrecognised_env_writes).to be_empty,
      "unrecognised dotenv write shape(s) in scripts/prepare-worktree.sh — the key " \
      "extraction in this spec cannot see them, so they are unguarded:\n" \
      "#{unrecognised_env_writes.join("\n")}"
  end

  # A dotenv COMMENT payload defines no key, so it cannot be a Gemfile-read leak.
  # The script's redirection lands on whichever printf argument is last, and in
  # the no-free-redis-lane branch that argument is a comment — which the shape
  # check read as an unrecognised third write shape (IMP-c478aaebe10e).
  it "classifies a comment-only dotenv write as key-less rather than unrecognised" do
    comment_write = '    "# Specs here will refuse to run until one is freed." > "$ENV_TEST_LOCAL"'
    expect(unrecognised_writes_in(comment_write)).to be_empty
    expect(keys_in(comment_write)).to be_empty
  end

  # The containment anchor must keep failing on a shape it genuinely cannot
  # parse, or the fix above would turn the guard off rather than teach it.
  it "still fails on a genuinely unparsed write shape" do
    heredoc_write = '    cat > "$ENV_TEST_LOCAL" <<EOF'
    expect(unrecognised_writes_in(heredoc_write)).not_to be_empty
  end

  # The exemption must key on the ABSENCE OF A KEY, not on a `#` appearing
  # somewhere. prepare-worktree.sh is densely commented, so a trailing comment
  # on a new write is a plausible shape rather than a contrived one.
  it "does not exempt an unrecognised write shape merely because it carries a trailing comment" do
    expect(unrecognised_writes_in('    cat "$src" >> "$dst"   # append the extras')).not_to be_empty
  end

  it "does not treat a line as key-less when an UNQUOTED KEY= sits beside a comment" do
    expect(unrecognised_writes_in('    echo FOO=bar > "$dst"  # set the flag')).not_to be_empty
  end

  # The dangerous middle case: a line carrying BOTH a comment and a real key.
  # Skipping it on the strength of the comment alone would hide the key.
  it "does not treat a line as key-less when a KEY= payload sits beside a comment" do
    mixed_write = '    "# note" "POWERNODE_DEPLOYED=1" > "$ENV_TEST_LOCAL"'
    expect(unrecognised_writes_in(mixed_write)).not_to be_empty
  end

  # PRESENCE anchor on the exemption itself: if the script is reordered so the
  # redirect no longer lands on a comment, this exemption stops being exercised
  # by the real file and persists as an untested weakening of the guard.
  it "still has a comment-payload dotenv write for the exemption to cover" do
    comment_writes = script.lines.select do |line|
      line.match?(/>>?\s*"\$\{?ENV_TEST_LOCAL\}?"/) && line.match?(comment_arg_re)
    end
    expect(comment_writes).not_to be_empty
  end

  it "still parses the env vars read at Gemfile-evaluation time" do
    # PRESENCE anchor on the source list itself: the helper the Gemfile requires
    # must be reached by the require_relative walk, not just the entrypoints.
    expect(gemfile_time_sources).to include("server/Gemfile", "extensions_loader_helper.rb")
    expect(gemfile_time_keys).to include(
      "POWERNODE_INCLUDE_PRIVATE_EXTENSIONS",
      "POWERNODE_DEPLOYED"
    )
  end

  it "writes no Gemfile-evaluation-time env var into a dotenv file" do
    overlap = dotenv_written_keys & gemfile_time_keys

    expect(overlap).to be_empty,
      "scripts/prepare-worktree.sh writes #{overlap.inspect} into a dotenv file, but " \
      "#{gemfile_time_sources.join(', ')} read those vars while BUNDLER evaluates the " \
      "Gemfile — before dotenv-rails' before_configuration hook loads .env. The Gemfile " \
      "would see them unset while post-boot readers (server/spec/rails_helper.rb) see them " \
      "set. Export such a var into the process environment (or select the private bundle " \
      "with BUNDLE_GEMFILE=Gemfile.private) instead of writing it to .env."
  end

  it "does not offer a Gemfile-evaluation-time env var in the server/.env.example template" do
    skip "no server/.env.example" unless File.exist?(env_example_path)

    example_keys = File.read(env_example_path)
                       .lines
                       .filter_map { |l| l[/^\s*#?\s*([A-Z_][A-Z0-9_]*)=/, 1] }
                       .uniq
    expect(example_keys).not_to be_empty, "server/.env.example parsed to zero keys"

    overlap = example_keys & gemfile_time_keys
    expect(overlap).to be_empty,
      "server/.env.example offers #{overlap.inspect}, which #{gemfile_time_sources.join(', ')} " \
      "read at Gemfile-evaluation time. Anyone copying the template to server/.env would " \
      "reproduce the bundled-without / factories-with split this guard exists to close."
  end
end

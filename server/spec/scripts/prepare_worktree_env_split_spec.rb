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

  let(:script) { File.read(script_path) }

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
  let(:dotenv_written_keys) do
    (script.scan(env_upsert_call_re).flatten + script.scan(printf_arg_re).flatten).uniq
  end

  # CONTAINMENT anchor: every redirection in the script that targets a dotenv
  # destination must be one of the two shapes parsed above. A THIRD write shape
  # (e.g. a heredoc, or `cat >> "$dst"`) then fails HERE rather than slipping past
  # the disjointness check silently with its keys unseen.
  let(:unrecognised_env_writes) do
    script.lines.each_with_index.filter_map do |line, idx|
      target = line[/>>?\s*"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"/, 1]
      next if target.nil? || !env_file_target_vars.include?(target)
      next if line.match?(env_upsert_body_re) || line.match?(printf_arg_re)

      "#{idx + 1}: #{line.strip}"
    end
  end

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

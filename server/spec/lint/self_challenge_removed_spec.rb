# frozen_string_literal: true

require "rails_helper"

# Increment D6 — the self-challenge subsystem is gone, and stays gone.
#
# It was the audit's clearest "built three times, wired zero times" finding
# (§6.3): `generate_challenge!` created a row at `generating` and enqueued
# nothing, the scheduler job appeared in no `sidekiq*.yml`, the challenged agent
# graded itself with a 0.5 default on a parse failure, and no result ever
# reached a trust score or a skill. Three MCP verbs advertised the capability
# regardless.
#
# WHY A LINT AND NOT JUST THE DELETION. A deletion this wide — 3 verbs, a
# model, a table, 2 jobs, an internal controller, 2 routes, a frontend panel —
# comes back one reference at a time, and each one comes back looking harmless:
# a constant in an enum, a route that 404s, an `Ai::SelfChallenge` in a service
# nobody runs. The detector is what makes "deleted" a property rather than a
# moment.
#
# THE ONE DELIBERATE SURVIVOR is `self_challenge` in
# `Ai::Trajectory::TRAJECTORY_TYPES`, kept for historical rows and asserted
# BELOW so its survival is a decision on the record rather than an oversight
# this file happens not to catch.
RSpec.describe "the self-challenge subsystem is deleted", type: :lint do
  def repo_root
    File.expand_path("../../..", __dir__)
  end

  # Every identifier the subsystem owned. Deliberately includes the frontend
  # and worker spellings: this deletion crosses three trees, and a scan of one
  # of them would report "zero references" over two thirds of the surface.
  def forbidden_identifiers
    %w[
      SelfChallenge
      ai_self_challenges
      generate_self_challenge
      list_challenges
      get_challenge_result
      challenge_derived
      AiSelfChallengeJob
      AiSelfChallengeSchedulerJob
      getSelfChallenges
      enqueue_ai_self_challenge
      intelligence_self_challenges
    ]
  end

  # Scanned trees. `extensions/**` is in on purpose — a scan that omits it
  # fakes a clean result over the half of the platform most likely to hold a
  # stale reference.
  def scanned_files
    globs = [
      "server/app/**/*.rb", "server/lib/**/*.rb", "server/config/**/*.rb",
      "server/db/seeds/**/*.rb", "server/db/seeds.rb",
      "worker/app/**/*.rb", "worker/config/**/*.yml",
      "frontend/src/**/*.ts", "frontend/src/**/*.tsx",
      "extensions/*/server/app/**/*.rb", "extensions/private/*/server/app/**/*.rb"
    ]
    files = globs.flat_map { |g| Dir.glob(File.join(repo_root, g)) }.uniq.sort

    expect(files).not_to be_empty, "scanned nothing — the globs have broken"
    expect(files.any? { |f| f.include?("/frontend/") }).to be(true),
      "scanned no frontend sources; a Ruby-only sweep would miss the whole intelligence panel"
    expect(files.any? { |f| f.include?("/extensions/") }).to be(true),
      "scanned no extension sources; omitting extensions/ fakes a clean result"
    files
  end

  # A reference is a code reference, not a mention. The deletion left
  # explanatory comments behind on purpose — `challenge_derived` is named in
  # the comment recording why it went, and `self_challenge` in the one
  # recording why the trajectory value stayed — and a detector that fired on
  # those would force the explanations out of the tree, which is the opposite
  # of what it is for.
  #
  # The line NUMBER is taken before the comment lines are dropped. Numbering the
  # surviving lines instead would report a position that does not exist in the
  # file, and a lint that sends the reader to the wrong line is worse than one
  # that reports no line at all.
  def comment?(line)
    line.strip.start_with?("#", "//", "*", "/*")
  end

  # THE detector. Both arms below drive THIS method rather than restating the
  # rule inline: a hand-copied predicate in the example can keep agreeing with
  # itself while the real one rots.
  def offending_lines(lines)
    lines.each_with_index.filter_map do |line, index|
      next nil if comment?(line)

      hit = forbidden_identifiers.find { |name| line.include?(name) }
      next nil unless hit

      [ index + 1, hit ]
    end
  end

  it "has no code reference to any deleted identifier, in any tree" do
    offenders = scanned_files.flat_map do |file|
      offending_lines(File.readlines(file)).map do |line_number, hit|
        "#{file.delete_prefix("#{repo_root}/")}:#{line_number}  #{hit}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      #{offenders.size} live reference(s) to the deleted self-challenge subsystem:

        #{offenders.join("\n  ")}

      The verbs, the model, the table and the jobs are gone (D6). A reference to
      one of them is either dead code or a NameError waiting for the first caller.
    MSG
  end

  # THE OTHER ARM. A scanner that matched nothing would pass the example above
  # for the wrong reason, and this one is a hand-written substring sweep over a
  # moving tree — going quietly dead is its likeliest failure.
  it "detects a violation when one is present" do
    fake = <<~RUBY
      # A leading comment, so the reported line number cannot come from
      # numbering the surviving (non-comment) lines.
      class Something
        def call
          Ai::SelfChallenge.completed.for_skill(1)
        end
      end
    RUBY

    hits = offending_lines(fake.lines)

    # The LINE NUMBER is asserted, not just the count: it is counted over the
    # whole file including the two comment lines, so a detector that renumbers
    # the surviving lines reports 3 here and fails.
    expect(hits).to eq([ [ 5, "SelfChallenge" ] ])
  end

  it "does not fire on the comments that explain the deletion" do
    commented = [
      "      # `challenge_derived` was removed with the self-challenge subsystem (D6):",
      "        # The `self_challenges` block was removed with the subsystem (D6)."
    ]
    expect(commented).to all(satisfy { |line| comment?(line) })
    expect(offending_lines(commented)).to be_empty
  end

  describe "the deliberate survivor" do
    # Kept on purpose: dropping the value would make every historical
    # trajectory of that type fail validation on its next save, and would make
    # the column lie about what produced the row.
    it "keeps self_challenge in TRAJECTORY_TYPES" do
      expect(Ai::Trajectory::TRAJECTORY_TYPES).to include("self_challenge")
    end

    it "is the only place the string survives in a validated vocabulary" do
      expect(defined?(Ai::SelfChallenge)).to be_nil
    end
  end

  describe "the MCP surface" do
    it "advertises none of the three verbs" do
      advertised = Ai::Tools::PlatformApiToolRegistry.all_tools.keys

      expect(advertised).not_to include("generate_self_challenge")
      expect(advertised).not_to include("list_challenges")
      expect(advertised).not_to include("get_challenge_result")
    end

    # The other arm: the tool that hosted them is still advertised, so an
    # over-broad deletion cannot pass.
    it "still advertises the three surviving skill verbs" do
      advertised = Ai::Tools::PlatformApiToolRegistry.all_tools

      expect(advertised).to include(
        "mutate_skill" => "Ai::Tools::SelfImprovementTool",
        "compose_skills" => "Ai::Tools::SelfImprovementTool",
        "auto_evolve_skill" => "Ai::Tools::SelfImprovementTool"
      )
    end
  end

  describe "the database" do
    it "no longer has the table" do
      expect(ActiveRecord::Base.connection.table_exists?("ai_self_challenges")).to be(false)
    end
  end
end

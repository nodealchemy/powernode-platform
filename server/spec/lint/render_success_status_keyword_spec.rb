# frozen_string_literal: true

require "spec_helper"
require "find"

# `render_success(status:)` IS THE HTTP STATUS KEYWORD, NOT A DATA FIELD.
#
# `def render_success(positional_data = nil, status: :ok, meta:, message:, data:, **extra_data)`
# (`app/controllers/concerns/api_response.rb:16`). Any `status:` passed at the
# TOP LEVEL of the call — not inside a hash literal — binds to that keyword.
# `validate_http_status!` (`:157-169`) then raises ArgumentError for anything
# that is not an Integer 100..599 or a Rack status symbol.
#
# WHY A GUARD AND NOT JUST THE RAISE. The raise is real, but it lands INSIDE the
# action, where an internal-seam controller's `rescue StandardError` — the
# worker-receiver rule that a callback must never answer 5xx — converts it into
# a cheerful 200 carrying `applied: false, error: "Invalid HTTP status ..."`.
# The row is written, the response lies, and the worker branching on `applied`
# counts the call as skipped. That is precisely what happened to increment A8's
# probe endpoint: the sweep was fixed, and it STILL reported every probe as
# skipped, because a second defect on the same line answered for it. It was
# caught only by an example asserting the response BODY; every other example
# asserted the persisted row and passed.
#
# THE RULE: at the top level of a `render_success(...)` call, `status:` may only
# be a Rack status symbol (`:ok`, `:created`, `:not_found`), an Integer literal,
# or a local/method value that resolves to one. A row's status, a model
# attribute, or a string literal belongs INSIDE the data hash:
#
#     render_success(applied: true, instance_status: instance.status)   # renamed
#     render_success({ status: "ok" })                                  # hash literal
#     render_success(data: { status: "ok" })                            # explicit data:
#
# SCOPE: `app/controllers/api/v1/internal/**` — the worker-facing seam, where a
# swallowed raise is invisible to the caller AND to a spec that only checks the
# row. Sites outside it raise loudly to an operator instead.
#
# RATCHET, WITH BOTH ARMS. `KNOWN_OFFENDERS` are live defects on this seam,
# found by the sweep the A8 fix prompted. They are listed rather than fixed
# because each sits in another lane's files; each is queued as an offer. The
# spec asserts CONTAINMENT (no site outside the list) *and* PRESENCE (every
# listed site still matches). A withdrawal that only checks absence lets the
# list rot into a lie: fix one, and this spec tells you to delete its entry.
RSpec.describe "render_success status: keyword misuse on the internal seam" do
  internal_root = File.expand_path("../../app/controllers/api/v1/internal", __dir__)

  # file => the offending `status:` value text, verbatim.
  #
  # Every entry is a LIVE DEFECT, not an accepted style. Each raises
  # ArgumentError today, so the endpoint either 500s a worker callback or, where
  # a rescue catches it, answers 200 with an error string and no real payload.
  KNOWN_OFFENDERS = {
    "ai/goal_plans_controller.rb" => [ '"failed"', '"completed"' ],
    "devops/swarm_controller.rb" => [ '"ok"', '"ok"', '"ok"' ]
  }.freeze

  # Extract every `render_success(` call's argument text, tracking bracket depth
  # so a `status:` nested inside a hash/array literal is NOT flagged, and paren
  # depth so `where(status: "active")` inside an argument is NOT flagged either.
  def self.offending_sites(source)
    # Full-line comments only: a comment cannot bind a keyword, and the file
    # that explains this hazard has to be able to spell it.
    src = source.lines.reject { |l| l.strip.start_with?("#") }.join

    sites = []
    src.to_enum(:scan, /render_success\(/).each do
      start = Regexp.last_match.end(0)
      depth_paren = 1
      depth_bracket = 0
      chars = []
      i = start
      while i < src.length && depth_paren.positive?
        c = src[i]
        case c
        when "(" then depth_paren += 1
        when ")"
          depth_paren -= 1
          break if depth_paren.zero?
        when "{", "[" then depth_bracket += 1
        when "}", "]" then depth_bracket -= 1
        end
        # Blank out anything nested in a literal OR in a nested call, so only
        # true top-level keywords survive.
        chars << (depth_bracket.zero? && depth_paren == 1 ? c : " ")
        i += 1
      end

      top = chars.join
      next unless (m = top.match(/(?:\A|[\s,])status:\s*([^,\n]+)/))

      value = m[1].strip
      # A Rack symbol or an Integer literal is correct by construction. A
      # ternary or a variable is left alone: only a real lexer could resolve it,
      # and the conservative direction for those is to trust the raise.
      next if value.match?(/\A(?::[a-z_]+|\d{3})\z/)
      next if value.include?("?") # ternary over symbols
      next if value.match?(/\A[a-z_][a-z0-9_]*\z/) # plain local/method value

      sites << { line: src[0...Regexp.last_match.begin(0)].count("\n") + 1, value: value }
    end
    sites
  end

  found = Hash.new { |h, k| h[k] = [] }
  Find.find(internal_root) do |path|
    next unless path.end_with?(".rb")

    rel = path.delete_prefix("#{internal_root}/")
    offending_sites(File.read(path)).each { |s| found[rel] << s[:value] }
  end

  it "flags no NEW top-level status: on the internal seam (containment)" do
    unexpected = found.reject { |rel, _| KNOWN_OFFENDERS.key?(rel) }

    expect(unexpected).to be_empty,
      "render_success(status: <not an HTTP status>) on the worker seam — the keyword " \
      "binds to the HTTP status and raises, which a callback's rescue turns into a 200 " \
      "carrying an error string. Move it into the data hash or rename the key:\n" +
      unexpected.map { |rel, vals| "  #{rel}: #{vals.join(', ')}" }.join("\n")
  end

  it "still finds every KNOWN offender (presence — the list must shrink, not rot)" do
    KNOWN_OFFENDERS.each do |rel, expected_values|
      expect(found[rel]).to match_array(expected_values),
        "#{rel} no longer matches its KNOWN_OFFENDERS entry. If you fixed it, delete the " \
        "entry; if you changed it some other way, update it. A stale allowlist is a lie."
    end
  end

  # BOTH ARMS over fixtures, so this can never become a check that passes for
  # everything or fails for everything unnoticed.
  describe "the detector itself" do
    def detect(source)
      RSpec.current_example.example_group.parent_groups.last.offending_sites(source).map { |s| s[:value] }
    end

    it "FLAGS a top-level status: bound to a model attribute" do
      expect(detect("render_success(applied: true, status: instance.status)")).to eq([ "instance.status" ])
    end

    it "FLAGS a top-level status: bound to a string literal" do
      expect(detect('render_success(status: "ok")')).to eq([ '"ok"' ])
    end

    it "does NOT flag a status: inside a hash literal" do
      expect(detect('render_success({ status: "ok" })')).to be_empty
    end

    it "does NOT flag an explicit data: hash" do
      expect(detect('render_success(data: { status: "ok" })')).to be_empty
    end

    it "does NOT flag a genuine Rack status symbol or Integer" do
      expect(detect("render_success({ a: 1 }, status: :created)")).to be_empty
      expect(detect("render_success({ a: 1 }, status: 202)")).to be_empty
    end

    it "does NOT flag a status: inside a NESTED call's arguments" do
      expect(detect('render_success(rows: Thing.where(status: "active").count)')).to be_empty
    end
  end
end

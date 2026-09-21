# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-7e08feaf4ebf / IMP-9553e923e1bc. scripts/audit/exception_forwarding_scan.rb's
# entire output is a completeness claim ("these are the rescue arms that
# read a raw exception"), and it has already had FIVE distinct blind spots
# found in it across three tasks. It also depends on MRI-internal
# RubyVM::AbstractSyntaxTree node names (RESBODY, LASGN/DASGN/IASGN/GASGN,
# LVAR/DVAR/IVAR/GVAR/CVAR, ERRINFO, DSTR/EVSTR) that a future Ruby upgrade
# could rename or restructure — and a scanner whose matchers stop firing
# prints an EMPTY result, which reads as "clean" rather than "broken". A
# committed known-positive fixture, asserted here, turns that silent
# failure into a loud spec failure instead of the weaker "the header asks
# whoever runs it to eyeball the count" this script used to rely on.
RSpec.describe "exception-forwarding scan" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:script) { File.join(repo_root, "scripts/audit/exception_forwarding_scan.rb") }

  def write(dir, rel, body)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # Output is split into three buckets — RAW (needs review), FORWARDED
  # (routes through rescued_error_result but a non-arg0 argument still
  # reads the exception), SANITIZED (every read is argument position 0) —
  # plus a TOTAL line. See the script's own header for why two buckets
  # were not enough (IMP-9553e923e1bc, finding 2): labeling a real forward
  # SANITIZED just because it passes through the audited helper's call is
  # worse than not flagging it at all.
  def run_scan(*roots)
    out, err, status = Open3.capture3("ruby", script, *roots)
    raw = out[/RAW.*?:\n(.*?)\n\nFORWARDED/m, 1].to_s.split("\n")
    forwarded = out[/FORWARDED.*?:\n(.*?)\n\nSANITIZED/m, 1].to_s.split("\n")
    sanitized = out[/SANITIZED.*?:\n(.*?)\n\nTOTAL/m, 1].to_s.split("\n")
    total = out[/TOTAL: (\d+)/, 1].to_i
    [raw, forwarded, sanitized, total, err, status.exitstatus]
  end

  around do |example|
    Dir.mktmpdir("exception-forwarding-scan-spec") { |dir| @dir = dir; example.run }
  end

  # The FOURTH blind spot: `e.record` is a CALL whose receiver is the
  # bound exception, several levels below the top-level call the old
  # matcher inspected. This is the same shape as the real misses
  # (site_setting_tool.rb, system_fleet_tool.rb, ...).
  it "flags a rescued exception read through a receiver chain (e.record.errors...)" do
    write(@dir, "known_positive.rb", <<~RUBY)
      def create_x(params)
        Thing.create!(params)
      rescue ActiveRecord::RecordInvalid => e
        error_result("Validation failed: \#{e.record.errors.full_messages.join(', ')}")
      end
    RUBY

    raw, _forwarded, _sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("known_positive.rb:3"))
    expect(total).to eq(1)
  end

  it "does not flag a rescue that only logs the exception" do
    write(@dir, "known_negative.rb", <<~RUBY)
      def call_x(params)
        do_thing
      rescue StandardError => e
        Rails.logger.error("[X] \#{e.class}: \#{e.message}")
        error_result("An internal error occurred processing this request.")
      end
    RUBY

    raw, forwarded, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(forwarded).to be_empty
    expect(sanitized).to be_empty
    expect(total).to eq(0)
  end

  # A rescue attached to a BLOCK (IMP-095a5fe91b4a's blind spot) binds the
  # exception via DASGN/DVAR, not LASGN/LVAR — re-asserted here so a
  # regression in the receiver-chain rewrite can't silently drop it again.
  it "still flags a block-level rescue (DASGN/DVAR binding)" do
    write(@dir, "block_level.rb", <<~RUBY)
      def batch(ids)
        ids.map do |id|
          { id: id, ok: true }
        rescue StandardError => e
          { id: id, ok: false, reason: e.message }
        end
      end
    RUBY

    raw, _forwarded, _sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("block_level.rb:4"))
  end

  it "flags a bound instance-variable rescue (IASGN/IVAR binding)" do
    write(@dir, "ivar_binding.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => @err
        error_result(@err.message)
      end
    RUBY

    raw, _forwarded, _sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("ivar_binding.rb:3"))
  end

  it "flags a bare rescue reading $! with no local binding at all" do
    write(@dir, "global_errinfo.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError
        error_result($!.message)
      end
    RUBY

    raw, _forwarded, _sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("global_errinfo.rb:3"))
  end

  it 'flags a bare "#{e}"-in-a-string with no method call at all' do
    write(@dir, "bare_interpolation.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        error_result("Failed: \#{e}")
      end
    RUBY

    raw, _forwarded, _sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("bare_interpolation.rb:3"))
  end

  # THE CLASSIFICATION ADDED after review of IMP-7e08feaf4ebf: every hit
  # stays in the total, but is labeled by which sink it flows through.
  # This is not a narrowing of what counts as a read (that was blind spot
  # 4) — it labels an already-counted hit, nothing is dropped from any
  # bucket or the total.
  it "classifies an arm as SANITIZED when the only read is argument position 0 of rescued_error_result" do
    write(@dir, "sanitized.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        rescued_error_result(e, message: "a static, hand-authored safe message")
      end
    RUBY

    raw, forwarded, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(forwarded).to be_empty
    expect(sanitized).to include(a_string_ending_with("sanitized.rb:3"))
    expect(total).to eq(1)
  end

  # BLIND SPOT FIVE, finding 2 (IMP-9553e923e1bc), as broadened by
  # independent review: `sanitizing_sink_call?` used to tag EVERY read
  # anywhere in the sink call's argument list as :sanitized, so even the
  # sweep's OWN reviewed idiom `rescued_error_result(e, message: e.message)`
  # — no extra nesting, exactly what dozens of real arms do — was
  # affirmatively labeled SANITIZED while the helper returns that
  # `message:` string VERBATIM. Only argument position 0 (what the helper
  # logs and never returns) is actually safe. This is its own bucket,
  # FORWARDED-BY-INTENT, not RAW: dumping it into RAW would recreate the
  # exact noise the RAW/SANITIZED split existed to solve (33 such arms
  # exist in core today).
  it "classifies an arm as FORWARDED-BY-INTENT when message: reads e.message directly, with no extra nesting" do
    write(@dir, "forwarded_plain.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        rescued_error_result(e, message: e.message)
      end
    RUBY

    raw, forwarded, sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(forwarded).to include(a_string_ending_with("forwarded_plain.rb:3"))
    expect(sanitized).to be_empty
  end

  it "classifies an arm as FORWARDED-BY-INTENT when a read sits nested inside the sink call's message: argument" do
    write(@dir, "forwarded_nested.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        rescued_error_result(e, message: "failed: " + e.message)
      end
    RUBY

    raw, forwarded, sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(forwarded).to include(a_string_ending_with("forwarded_nested.rb:3"))
    expect(sanitized).to be_empty
  end

  # BLIND SPOT FIVE, finding 1 (IMP-9553e923e1bc). The read's node type
  # depends on the SCOPE DOING THE READING, not the scope that bound the
  # exception. A method-scope `rescue => e` binds via LASGN, but a read of
  # `e` inside a block (`each`, `map`, `transaction do`, ...) is a DVAR —
  # the read's own scope, unrelated to where `e` was bound. The prior fix
  # (ASSIGN_TO_READ_TYPE, matching read-node-type to binding-node-type) was
  # itself still an enumeration standing in for the property actually
  # wanted ("does this node name the bound variable") and missed exactly
  # this cell of the matrix — demonstrated by running the committed
  # scanner on this shape and getting neither RAW nor SANITIZED, just
  # silence.
  it "flags a read inside a block when the RESCUE ITSELF is method-scoped, not block-scoped" do
    write(@dir, "method_scope_binding_block_scope_read.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        [1].each { |i| error_result("boom: \#{e.message}") }
      end
    RUBY

    raw, forwarded, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("method_scope_binding_block_scope_read.rb:3"))
    expect(forwarded).to be_empty
    expect(sanitized).to be_empty
    expect(total).to eq(1)
  end

  it "classifies an arm as RAW when even one read bypasses the sink entirely, alongside one that doesn't" do
    write(@dir, "mixed.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        extra = e.backtrace.first
        rescued_error_result(e, message: "safe text: \#{extra}")
      end
    RUBY

    raw, forwarded, sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("mixed.rb:3"))
    expect(forwarded).to be_empty
    expect(sanitized).to be_empty
  end

  it "warns on stderr and skips a file that fails to parse, and still scans its siblings" do
    write(@dir, "broken.rb", "def foo(\n  bar\n")
    write(@dir, "sibling_known_positive.rb", <<~RUBY)
      def create_x(params)
        Thing.create!(params)
      rescue ActiveRecord::RecordInvalid => e
        error_result("Validation failed: \#{e.record.errors.full_messages.join(', ')}")
      end
    RUBY

    raw, _forwarded, _sanitized, total, err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(err).to include("broken.rb")
    expect(raw).to include(a_string_ending_with("sibling_known_positive.rb:3"))
    expect(total).to eq(1)
  end

  # CONSERVATION (IMP-9553e923e1bc, added after review). Every test above
  # is a POSITIVE-PRESENCE oracle: it proves the arm it names lands in a
  # specific bucket, and says nothing about arms that vanish. That is
  # precisely how blind spot 5's finding 1 survived five earlier rounds of
  # fixtures — a probe printed TOTAL: 2 where the answer was 3, and no
  # existing test could have caught it, because none of them checked the
  # SUM against an independently-known count.
  #
  # This fixture has SEVEN arms, each independently verified by hand to
  # read the bound exception in some way, covering every shape this file
  # currently knows how to recognise (plain method-scope read, block-scope
  # DASGN/DVAR read, method-scope BINDING with a block-scope READ — the
  # exact shape finding 1 missed, IVAR binding, bare $! with no binding,
  # a sanitized sink call, and a forwarded-by-intent sink call). The
  # invariant is not "each of these seven lands in the bucket I predict"
  # (already covered above) — it is that RAW + FORWARDED + SANITIZED,
  # summed, equals 7. If a future read shape (blind spot six) makes an
  # eighth, differently-shaped arm vanish the way finding 1 did, this sum
  # breaks LOUDLY instead of the total silently staying just as
  # plausible-looking as a correct one.
  it "conserves every known-reading arm across the three buckets — nothing vanishes" do
    write(@dir, "conservation.rb", <<~RUBY)
      def plain_method_scope
        bar
      rescue StandardError => e
        error_result(e.message)
      end

      def block_scope_binding
        [1].map do |i|
          i
        rescue StandardError => e
          error_result(e.message)
        end
      end

      def method_scope_binding_block_scope_read
        bar
      rescue StandardError => e
        [1].each { |i| error_result("boom: \#{e.message}") }
      end

      def ivar_binding
        bar
      rescue StandardError => @err
        error_result(@err.message)
      end

      def global_errinfo_no_binding
        bar
      rescue StandardError
        error_result($!.message)
      end

      def sanitized_sink
        bar
      rescue StandardError => e
        rescued_error_result(e)
      end

      def forwarded_sink
        bar
      rescue StandardError => e
        rescued_error_result(e, message: e.message)
      end
    RUBY

    raw, forwarded, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw.size + forwarded.size + sanitized.size).to eq(7)
    expect(total).to eq(7)
  end
end

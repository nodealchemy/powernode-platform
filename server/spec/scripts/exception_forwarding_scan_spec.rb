# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-7e08feaf4ebf. scripts/audit/exception_forwarding_scan.rb's entire
# output is a completeness claim ("these are the rescue arms that read a
# raw exception"), and it has already had FOUR distinct blind spots found
# in it across two tasks. It also depends on MRI-internal
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

  # Output is split into a RAW section (needs review) and a SANITIZED
  # section (every read of the exception routes through
  # rescued_error_result) plus a TOTAL line — see the script's own header
  # for why: an instrument whose count is dominated by already-fixed arms
  # is not readable at a glance, and hiding them entirely would make the
  # blind-spot-4 mistake (narrowing what counts) one layer up.
  def run_scan(*roots)
    out, err, status = Open3.capture3("ruby", script, *roots)
    raw = out[/RAW.*?:\n(.*?)\n\nSANITIZED/m, 1].to_s.split("\n")
    sanitized = out[/SANITIZED.*?:\n(.*?)\n\nTOTAL/m, 1].to_s.split("\n")
    total = out[/TOTAL: (\d+)/, 1].to_i
    [raw, sanitized, total, err, status.exitstatus]
  end

  around do |example|
    Dir.mktmpdir("exception-forwarding-scan-spec") { |dir| @dir = dir; example.run }
  end

  # The FOURTH blind spot this task exists to close: `e.record` is a CALL
  # whose receiver is the bound exception, several levels below the
  # top-level call the old matcher inspected. This is the same shape as the
  # real misses (site_setting_tool.rb, system_fleet_tool.rb, ...).
  it "flags a rescued exception read through a receiver chain (e.record.errors...)" do
    write(@dir, "known_positive.rb", <<~RUBY)
      def create_x(params)
        Thing.create!(params)
      rescue ActiveRecord::RecordInvalid => e
        error_result("Validation failed: \#{e.record.errors.full_messages.join(', ')}")
      end
    RUBY

    raw, _sanitized, total, _err, status = run_scan(@dir)

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

    raw, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
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

    raw, _sanitized, _total, _err, status = run_scan(@dir)

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

    raw, _sanitized, _total, _err, status = run_scan(@dir)

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

    raw, _sanitized, _total, _err, status = run_scan(@dir)

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

    raw, _sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("bare_interpolation.rb:3"))
  end

  # THE CLASSIFICATION ADDED after review of IMP-7e08feaf4ebf: every hit
  # stays in the total, but is labeled by whether it flows through the one
  # audited sink. This is not a narrowing of what counts as a read (that
  # was blind spot 4) — it labels an already-counted hit, nothing is
  # dropped from either bucket or the total.
  it "classifies an arm as SANITIZED when every read routes through rescued_error_result" do
    write(@dir, "sanitized.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        rescued_error_result(e, message: e.message)
      end
    RUBY

    raw, sanitized, total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(sanitized).to include(a_string_ending_with("sanitized.rb:3"))
    expect(total).to eq(1)
  end

  it "classifies an arm as RAW when even one read bypasses the sink, alongside one that doesn't" do
    write(@dir, "mixed.rb", <<~RUBY)
      def foo
        bar
      rescue StandardError => e
        extra = e.backtrace.first
        rescued_error_result(e, message: "safe text: \#{extra}")
      end
    RUBY

    raw, sanitized, _total, _err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to include(a_string_ending_with("mixed.rb:3"))
    expect(sanitized).to be_empty
  end

  it "warns on stderr and skips a file that fails to parse, instead of silently dropping it" do
    write(@dir, "broken.rb", "def foo(\n  bar\n")

    raw, sanitized, total, err, status = run_scan(@dir)

    expect(status).to eq(0)
    expect(raw).to be_empty
    expect(sanitized).to be_empty
    expect(total).to eq(0)
    expect(err).to include("broken.rb")
  end
end

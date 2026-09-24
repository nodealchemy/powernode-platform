# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-f6f80b585b19 — scripts/check-tool-not-found-leak.sh flags an MCP tool's
# `rescue ActiveRecord::RecordNotFound` when it forwards e.message: for a
# scoped relation (`account.things.find(id)`) that message carries a
# ` [WHERE "table"."column" = $1]` suffix (Rails 8.1), and tool results
# replay to the model provider. These specs pin the guard itself — both that
# it catches the real anti-pattern and that it does NOT flag the safe shapes
# already in wide use (a bare rescue with a hand-authored literal, or
# rescued_error_result/not_found_result with no message: override) — so the
# guard can't regress into either a false negative or the alert-fatigue
# false positive the sibling account-scoping guard hit once already.
RSpec.describe "check-tool-not-found-leak.sh (IMP-f6f80b585b19)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:script) { File.join(repo_root, "scripts/check-tool-not-found-leak.sh") }

  def scan(tool_body)
    out = nil
    code = nil
    Dir.mktmpdir do |dir|
      tool_dir = File.join(dir, "tools")
      Dir.mkdir(tool_dir)
      File.write(File.join(tool_dir, "fixture_tool.rb"), tool_body)
      o, s = Open3.capture2e({ "TOOL_LEAK_SCAN_DIRS" => tool_dir }, "bash", script)
      out = o
      code = s.exitstatus
    end
    [ out, code ]
  end

  it "the real tree has no live hit (every known site was fixed alongside this guard)" do
    out, status = Open3.capture2e("bash", script)
    expect(status.exitstatus).to eq(0), "unexpected RecordNotFound leak(s):\n#{out}"
  end

  it "flags error_result(e.message) on a RecordNotFound rescue" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a raw e.message forward; output:\n#{out}"
    expect(out).to include("fixture_tool.rb")
  end

  it "flags rescued_error_result(e, message: e.message), which defeats the safe default" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          rescued_error_result(e, message: e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag message: e.message override; output:\n#{out}"
  end

  it "does NOT flag not_found_result(e) — the fix" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          not_found_result(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a bare rescue with a hand-authored literal message" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find_by(id: params[:id]) || raise(ArgumentError)
        rescue ActiveRecord::RecordNotFound
          { success: false, error: "Thing not found" }
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag rescued_error_result(e) with no message: override (the generic-default shape)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          rescued_error_result(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  # The false-positive trap the account-scoping guard hit once already
  # (IMP-69483951e18e): a DIFFERENT rescue clause's own e.message, sitting
  # right after a safe RecordNotFound clause, must not bleed into its window.
  it "does NOT flag an adjacent RecordInvalid rescue's own e.message" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          { success: false, error: "Thing not found" }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: e.message }
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0), "an unrelated rescue clause's e.message must not trip this guard"
  end

  # Six forms the FIRST cut of this guard (a literal awk match on the
  # RecordNotFound rescue line, `\bmessage\b` only, clause-close on ANY
  # `rescue`/`end` regardless of indentation) missed — the review that
  # replaced it with the Ruby pass in check-tool-not-found-leak.rb confirmed
  # each one red against that first cut before this guard's rewrite landed.
  it "flags e.to_s, not just e.message" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          error_result(e.to_s)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag e.to_s; output:\n#{out}"
  end

  it "flags a captured variable named something other than e" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => err
          error_result(err.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a non-`e` captured variable; output:\n#{out}"
  end

  it "flags an ::ActiveRecord::RecordNotFound rescue (top-level-qualified)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ::ActiveRecord::RecordNotFound => e
          error_result("nf: \#{e.message}")
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag the ::-prefixed class name; output:\n#{out}"
  end

  it "flags RecordNotFound when it is not the first class in a multi-rescue" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ArgumentError, ActiveRecord::RecordNotFound => e
          error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag RecordNotFound listed after another class; output:\n#{out}"
  end

  it "flags a leak that follows an inner if/end at a deeper indent, not just the next line" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          if foo
            bar
          end
          error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "an inner if/end must not close the clause scan early; output:\n#{out}"
  end

  it "flags a same-line `rescue ... then ...` body" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e then error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a same-line then-body; output:\n#{out}"
  end

  it "does NOT flag a StandardError catch-all (out of scope, IMP-f6f80b585b19 item 8 follow-up)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue StandardError => e
          error_result(e.message)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a RecordNotFound rescue whose body is skipped for logging, not forwarding" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          Rails.logger.info("x \#{e.message}")
          not_found_result(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0), "a logger line must not itself trip the guard"
  end

  # Round 2 of the independent review found two more false-negative forms —
  # both confirmed red against the round-1 implementation before this
  # guard's regex was anchored / made to advance one line at a time.
  it "flags a leak whose rescue clause a preceding COMMENT merely mentions RecordNotFound (r2_comment_swallow)" do
    body = <<~RUBY
      # Example: rescue ActiveRecord::RecordNotFound
      class FixtureTool < BaseTool
        def call(p)
          items.each do |x|
            x.find
          rescue ActiveRecord::RecordNotFound => e
            return error_result(e.message)
          end
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "an unanchored match on the comment line used to swallow the whole method, var-less, past the real leak; output:\n#{out}"
  end

  it "flags a NESTED rescue's own leak, under a different captured variable than its enclosing clause (r2_nested_var)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(p)
          x
        rescue ActiveRecord::RecordNotFound => e
          begin
            y
          rescue ActiveRecord::RecordNotFound => err
            return error_result(err.message)
          end
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "the inner clause's own `err.message` leak must not hide behind the outer clause's `e` scan; output:\n#{out}"
  end

  # A comment/string that merely MENTIONS the class, with no real rescue
  # anywhere nearby, must still not be flagged — the anchor fix's other arm.
  it "does NOT flag a RecordNotFound mention inside a string literal that starts a line other than the rescue" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(p)
          msg = "hint: rescue ActiveRecord::RecordNotFound"
          not_found_result(StandardError.new(msg))
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "flags e.detailed_message" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          error_result(e.detailed_message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag e.detailed_message; output:\n#{out}"
  end

  it "flags e.inspect" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          error_result(e.inspect)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag e.inspect; output:\n#{out}"
  end

  it "flags a leak on a line that ALSO logs, rather than exempting it as pure logging" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          Rails.logger.info("x"); return error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "a line that both logs AND returns the leak must still be flagged; output:\n#{out}"
  end

  # IMP-f6f80b585b19 review round 2, item 4 — an empty result from the
  # DEFAULT scan roots (no TOOL_LEAK_SCAN_DIRS override) must fail closed,
  # not silently report all-clear.
  it "fails closed (nonzero, message on stderr) when the default core tree resolves to zero .rb files" do
    # The script derives REPO_ROOT from its OWN location (BASH_SOURCE), not
    # the caller's cwd, so simulating "the default tree is missing" means
    # copying the script itself into a fake repo root with no
    # server/app/services/ai/tools — not just `cd`ing elsewhere first.
    Dir.mktmpdir do |dir|
      fake_scripts_dir = File.join(dir, "scripts")
      Dir.mkdir(fake_scripts_dir)
      FileUtils.cp(script, fake_scripts_dir)
      FileUtils.cp(File.join(repo_root, "scripts/check-tool-not-found-leak.rb"), fake_scripts_dir)
      fake_script = File.join(fake_scripts_dir, File.basename(script))

      _stdout, stderr, status = Open3.capture3("bash", fake_script)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("ZERO"), "expected the fail-closed message on stderr; got:\n#{stderr}"
    end
  end

  # Round 3 of the independent review: five real sites in this codebase
  # (provisioning_tool.rb, dev_loop_tool.rb, system_fleet_tool.rb x2,
  # sdwan_tool.rb — a DIFFERENT exception, same style) use a MULTI-LINE
  # rescue class list, which the guard could not see the class name on at
  # all before it learned to join continuation lines. Both fixtures below
  # are confirmed red against the pre-round-3 implementation (scratch-only,
  # not committed) before this fix landed.
  it "flags ActiveRecord::RecordNotFound spread across a multi-line rescue class list (r3_multiline_list)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          x
        rescue ArgumentError,
               ActiveRecord::RecordNotFound => e
          error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag RecordNotFound on a continuation line; output:\n#{out}"
  end

  it "flags a multi-line rescue list whose first line carries a trailing comment (r3_hash_before)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          x
        rescue ArgumentError, # rescue list
               ActiveRecord::RecordNotFound => e
          error_result(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "a trailing comment on the continuation-triggering line must not hide the join; output:\n#{out}"
  end

  it "flags a literal { success: false, error: e.message } return alongside a logger call (r3_logger_error)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(params)
          account.things.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
          Rails.logger.info(e.message)
          return { success: false, error: e.message }
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "a literal error hash must count as output, same as error_result; output:\n#{out}"
  end

  it "does NOT flag a one-line begin/rescue/end compound statement (documented known miss, r3_end_rescue)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(p)
          begin; account.things.find(p[:id]); rescue ActiveRecord::RecordNotFound => e; error_result(e.message); end
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a rescue MODIFIER reaching $! (documented known miss, r3_modifier)" do
    body = <<~RUBY
      class FixtureTool < BaseTool
        def call(p)
          v = account.things.find(p[:id]) rescue error_result($!.message)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end
end

# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

# IMP-8552945f2672 — scripts/check-skill-executor-error-leak.sh flags a
# System::Ai::Skills executor's `rescue` clause when it builds a DIRECT
# caller-facing return (`failure(...)`, or a bare `{ success:, error: }`
# hash) from the caught exception's own message, without routing through
# BaseSkillExecutor#safe_error_text / #safe_failure. These specs pin the
# guard itself: that it catches the real anti-pattern, that it does NOT flag
# the safe shapes (CallerFacingError forwarding via the helper, a logger
# line, a StandardError already routed through the helper), and that it does
# not false-positive on the KNOWN, separate, larger gap this pass left alone
# (an `errors << {...}` / `failures << {...}` array-push, often spanning two
# lines) — the same false-positive class check-tool-not-found-leak.rb had to
# learn to avoid (an adjacent/unrelated shape must not bleed into the scan).
#
# STATEMENT-LEVEL, not line-level (review round 2): the guard operates on the
# rescue clause's text with comments/logger lines/push-STATEMENTS stripped,
# not on individual lines, so it also catches a `failure(...)` spanning
# several lines, a heredoc, a local re-assigned from the caught variable
# (`msg = e.message` ... `failure(msg)`), a member-access chain through
# `.record.errors.full_messages` (not just `.message`), and a direct return
# sitting in the SAME clause as an (out-of-scope) array push.
RSpec.describe "check-skill-executor-error-leak.sh (IMP-8552945f2672)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:script) { File.join(repo_root, "scripts/check-skill-executor-error-leak.sh") }

  def scan(executor_body)
    out = nil
    code = nil
    Dir.mktmpdir do |dir|
      skills_dir = File.join(dir, "skills")
      Dir.mkdir(skills_dir)
      File.write(File.join(skills_dir, "fixture_executor.rb"), executor_body)
      o, s = Open3.capture2e({ "SKILL_LEAK_SCAN_DIRS" => skills_dir }, "bash", script)
      out = o
      code = s.exitstatus
    end
    [ out, code ]
  end

  it "the real tree has no live hit (every known direct-return site was fixed alongside this guard)" do
    out, status = Open3.capture2e("bash", script)
    expect(status.exitstatus).to eq(0), "unexpected skill executor error leak(s):\n#{out}"
  end

  # A guard that finds nothing to scan must not read as a pass: an
  # uninitialised extensions/system submodule or a moved skills directory would
  # otherwise be indistinguishable from a clean tree.
  it "FAILS, rather than passing, when there is no skill executor file to scan" do
    Dir.mktmpdir do |dir|
      out, status = Open3.capture2e({ "SKILL_LEAK_SCAN_DIRS" => dir }, "bash", script)
      expect(status.exitstatus).to eq(1), "an empty scan must fail closed; output:\n#{out}"
      expect(out).to include("ZERO")
    end
  end

  # The default scan roots are relative to the repo root the script sits in, so
  # these run a copy of the guard inside a scratch tree.
  def in_scratch_tree
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "scripts"))
      %w[check-skill-executor-error-leak.sh check-skill-executor-error-leak.rb].each do |f|
        FileUtils.cp(File.join(File.dirname(script), f), File.join(root, "scripts", f))
      end
      yield root
    end
  end

  it "passes with a notice on a clone that has no extensions checked out" do
    in_scratch_tree do |root|
      out, status = Open3.capture2e("bash", File.join(root, "scripts/check-skill-executor-error-leak.sh"))
      expect(status.exitstatus).to eq(0), "a clone without the extension has nothing to guard; output:\n#{out}"
      expect(out).to include("not checked out")
    end
  end

  it "FAILS when extensions/system is checked out but holds no skill executor files" do
    in_scratch_tree do |root|
      FileUtils.mkdir_p(File.join(root, "extensions/system/server/app/services/system/ai"))
      out, status = Open3.capture2e("bash", File.join(root, "scripts/check-skill-executor-error-leak.sh"))
      expect(status.exitstatus).to eq(1), "a present extension with no skill files must fail closed; output:\n#{out}"
      expect(out).to include("ZERO")
    end
  end

  it "scans the extension's skill executors once it is checked out" do
    in_scratch_tree do |root|
      skills = File.join(root, "extensions/system/server/app/services/system/ai/skills")
      FileUtils.mkdir_p(skills)
      File.write(File.join(skills, "leaky_executor.rb"), <<~RUBY)
        class LeakyExecutor < BaseSkillExecutor
          def perform(**)
            risky_call
          rescue StandardError => e
            failure(e.message)
          end
        end
      RUBY
      out, status = Open3.capture2e("bash", File.join(root, "scripts/check-skill-executor-error-leak.sh"))
      expect(status.exitstatus).to eq(1), "output:\n#{out}"
      expect(out).to include("LEAK")
    end
  end

  it "reports an empty scan as a pass only in --warn (report-only) mode" do
    Dir.mktmpdir do |dir|
      _out, status = Open3.capture2e({ "SKILL_LEAK_SCAN_DIRS" => dir }, "bash", script, "--warn")
      expect(status.exitstatus).to eq(0)
    end
  end

  it "flags failure(e.message)" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failure(e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a raw e.message forward; output:\n#{out}"
  end

  it "flags e.message interpolated into a static prefix" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failure("Could not create thing: \#{e.message}")
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag an interpolated e.message; output:\n#{out}"
  end

  it "flags a bare { success: false, error: e.message } hash literal" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          { success: false, error: e.message }
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a bare error hash; output:\n#{out}"
  end

  # FIXED (review round 2, IMP-8552945f2672): `e.record.errors.full_messages`
  # is exactly as leaky as `e.message` — expose_service_local_executor.rb and
  # expose_service_public_tcp_executor.rb both had this live shape, missed by
  # the first pass's var_leak_re, found only once this guard was widened.
  it "flags a RecordInvalid rescue forwarding e.record.errors.full_messages" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          thing.save!
        rescue ActiveRecord::RecordInvalid => e
          failure("validation failed: \#{e.record.errors.full_messages.to_sentence}")
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag e.record.errors.full_messages; output:\n#{out}"
  end

  it "flags a bare failure(e.record.errors.full_messages.join(...)) call" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          thing.save!
        rescue ActiveRecord::RecordInvalid => e
          failure(e.record.errors.full_messages.join("; "))
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a full_messages join; output:\n#{out}"
  end

  # The multi-line failure(...) call this guard's first pass could not see:
  # the leak text and the `failure(` token are on different lines, so a
  # per-line scan never finds both on the same line.
  it "flags a failure(...) call whose interpolated message spans multiple lines" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          return failure(
            "the operation could not be completed (\#{e.class}: \#{e.message}). " \\
            "no changes were made — retry once the cause is cleared."
          )
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a multi-line failure(...) call; output:\n#{out}"
  end

  it "flags a heredoc message built from the caught exception" do
    body = <<~'RUBY'
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failure(<<~MSG)
            the operation could not be completed: #{e.message}
          MSG
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a heredoc carrying e.message; output:\n#{out}"
  end

  # `msg = e.message; failure(msg)` — the caught variable's text is aliased
  # to a local before it reaches the caller-facing builder, so a check keyed
  # only on the rescued variable's own name would miss it.
  it "flags a local re-assigned from e.message and then forwarded" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          msg = e.message
          failure(msg)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a local alias of e.message; output:\n#{out}"
  end

  # THE PRE-FIX provision_cluster_executor.rb SHAPE (review round 2): an
  # array-push bookkeeping entry (out of scope) sits in the SAME clause as a
  # direct `return failure(e.message)` (in scope). The first pass's
  # whole-clause `<<`-anywhere skip missed this entirely; only the push
  # STATEMENT'S own line(s) are excluded now, so the direct return next to it
  # is still caught.
  it "flags a direct return sitting in the same clause as an (out-of-scope) array push" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failures << { step: "unhandled", error: "\#{e.class}: \#{e.message}" }
          return failure(e.message, outputs: { node_ids: node_ids })
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1),
      "an adjacent out-of-scope push must not shield an in-scope direct return; output:\n#{out}"
  end

  it "does NOT flag that same shape once the direct return is fixed (push stays as-is)" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failures << { step: "unhandled", error: "\#{e.class}: \#{safe_error_text(e)}" }
          return failure(safe_error_text(e), outputs: { node_ids: node_ids })
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  # THE promote_replica_executor.rb SHAPE (review round 2): a multi-line
  # `return failure(...)` whose interpolated text embeds `#{e.class}:
  # #{e.message}` in the MIDDLE of a hand-authored sentence, not as the
  # whole message. Pins that this guard catches it before the fix and stays
  # quiet after safe_error_text replaces just the parenthetical.
  it "flags promote_replica_executor.rb's pre-fix cutover-rollback shape" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          ::ActiveRecord::Base.transaction { risky_call }
        rescue ::ActiveRecord::ActiveRecordError => e
          Rails.logger.error("[FixtureExecutor] cutover rolled back: \#{e.class}: \#{e.message}")
          return failure(
            "Refusing to report a promote that did not apply: the cutover was rolled back " \\
            "(\#{e.class}: \#{e.message}). No virtual ip moved, no promotion was stamped and no " \\
            "task was dispatched — re-drive with the same operation_id once the cause is cleared."
          )
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag the pre-fix cutover-rollback message; output:\n#{out}"
  end

  it "does NOT flag promote_replica_executor.rb's fixed cutover-rollback shape" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          ::ActiveRecord::Base.transaction { risky_call }
        rescue ::ActiveRecord::ActiveRecordError => e
          Rails.logger.error("[FixtureExecutor] cutover rolled back: \#{e.class}: \#{e.message}")
          return failure(
            "Refusing to report a promote that did not apply: the cutover was rolled back " \\
            "(\#{safe_error_text(e)}). No virtual ip moved, no promotion was stamped and no " \\
            "task was dispatched — re-drive with the same operation_id once the cause is cleared."
          )
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag safe_failure(e) — the fix" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          safe_failure(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag failure(safe_error_text(e)) — the fix, interpolated form" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failure("Could not create thing: \#{safe_error_text(e)}")
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a bare rescue with a hand-authored literal message" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError
          failure("Thing not found")
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a line that mentions logger, not a direct return" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          Rails.logger.error("\#{e.class}: \#{e.message}")
          safe_failure(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  # THE FALSE-POSITIVE TRAP this guard's own audit hit: an array-push
  # spanning two lines (`errors << { ...,\n error: e.message }`) — the `<<`
  # and the leak text are on DIFFERENT lines, so a per-line `<<` check alone
  # would miss the exclusion and false-flag the whole clause.
  it "does NOT flag a multi-line errors << { ... } array push (documented separate gap)" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failures << { step: "reclaim_volume", instance_id: instance.id,
                        volume_id: volume.id, error: e.message }
          false
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0),
      "an array-push bookkeeping entry is a documented separate gap, not this guard's target"
  end

  it "does NOT flag a single-line errors << { ... } array push" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          errors << { resource: "thing", id: thing_id, error: e.message }
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a line carrying a reviewed # skill-error-ok: suppression" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue ::Some::SharedError => e
          failure(e.message) # skill-error-ok: sole raise site names only this account's own id
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0)
  end

  it "does NOT flag a comment that merely mentions the old failure(e.message) shape" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          # This rescue used to be failure(e.message); fixed in IMP-8552945f2672.
          safe_failure(e)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(0), "a whole-line comment mentioning the old pattern must not trip the guard"
  end

  # Review round 3: a subclass-authored failure_* builder is a direct return
  # too — sdwan_ipfix_collector_compose_executor.rb's failure_with_partial put
  # e.message into data.failures[].error of a success:true result, and the
  # old `\bfailure\(` shape never saw it.
  it "flags failure_with_partial(step, e.message)" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          return failure_with_partial("create_collector", e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "should flag a failure_* sibling forwarding e.message; output:\n#{out}"
  end

  it "does NOT flag failure_with_partial routed through safe_error_text" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          return failure_with_partial("create_collector", safe_error_text(e))
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(0), "safe_error_text inside failure_with_partial is the fix; output:\n#{out}"
  end

  # Review round 3: a safe_error_text call on the line used to exempt the
  # WHOLE line, so a raw e.message riding beside it went unseen.
  it "flags e.message sitting beside safe_error_text on the same line" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          failure("\#{safe_error_text(e)} (\#{e.message})")
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "safe_error_text must not mask a raw e.message on its line; output:\n#{out}"
  end

  it "flags e.message passed as an extra key to safe_failure" do
    body = <<~RUBY
      class FixtureExecutor < BaseSkillExecutor
        def perform(**)
          risky_call
        rescue StandardError => e
          safe_failure(e, error: e.message)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "safe_failure's extra keys are still caller-facing; output:\n#{out}"
  end
end

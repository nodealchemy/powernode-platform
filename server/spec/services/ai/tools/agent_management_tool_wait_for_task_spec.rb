# frozen_string_literal: true

require "rails_helper"
require "benchmark"

# IMP-4b2fd4f389d4 — wait_for_task used to hold a Puma thread for up to 300s in
# a sleep loop, with no bound on concurrent waiters (a handful of callers could
# pin every thread and starve heartbeats and /up), a hardcoded terminal-status
# list, and an ERROR when the wait ran out. It now caps one call's wait, answers
# an expired wait as a success carrying done: false and the last status, and
# refuses waiters beyond a per-account (and a server-wide) limit with a named
# reason.
RSpec.describe Ai::Tools::AgentManagementTool, "#wait_for_task" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: %w[ai.agents.read ai.agents.execute]) }
  let(:tool) { described_class.new(account: account, user: user) }

  def wait(task, **extra)
    tool.execute(params: { action: "wait_for_task", task_id: task.task_id }.merge(extra))
  end

  # A task that is still running: the wait has to expire on its own.
  let(:running) { create(:ai_a2a_task, :active, account: account) }

  before do
    # Real polling would make the examples slow; the wait loop itself is under test.
    stub_const("#{described_class}::WAIT_POLL_SECONDS", 0.05)
  end

  describe "a wait that runs out" do
    it "is a success with done: false, timed_out: true and the last status, not an error" do
      result = wait(running, timeout_seconds: 1)

      expect(result[:success]).to be true
      expect(result[:done]).to be false
      expect(result[:timed_out]).to be true
      expect(result[:status]).to eq("active")
      expect(result[:task_id]).to eq(running.task_id)
      expect(result).not_to have_key(:error)
    end

    it "reports the wait it applied, so a caller knows to call again" do
      result = wait(running, timeout_seconds: 1)

      expect(result[:wait_seconds]).to eq(1)
    end

    it "actually waits roughly the requested time and then stops" do
      elapsed = Benchmark.realtime { wait(running, timeout_seconds: 1) }

      expect(elapsed).to be >= 0.9
      expect(elapsed).to be < 3.0
    end
  end

  describe "the cap on one call's wait" do
    it "clamps a huge timeout_seconds to the server cap instead of holding the thread for it" do
      stub_const("#{described_class}::WAIT_MAX_SECONDS", 1)

      elapsed = Benchmark.realtime do
        result = wait(running, timeout_seconds: 9_999)
        expect(result[:wait_seconds]).to eq(1)
      end

      expect(elapsed).to be < 3.0
    end

    it "uses the cap when timeout_seconds is absent or not positive" do
      stub_const("#{described_class}::WAIT_MAX_SECONDS", 1)

      [ nil, 0, -5 ].each do |value|
        result = wait(running, timeout_seconds: value)
        expect(result[:wait_seconds]).to eq(1), "timeout_seconds=#{value.inspect}"
      end
    end

    it "keeps the cap well under any proxy timeout" do
      expect(described_class::WAIT_MAX_SECONDS).to be <= 60
    end
  end

  describe "a task that finishes" do
    it "returns at once with done: true and the result, for every terminal status the model defines" do
      Ai::A2aTask::TERMINAL_STATUSES.each do |status|
        task = create(:ai_a2a_task, account: account, status: status, output: { "result" => "r" },
                                    error_message: (status == "failed" ? "boom" : nil))

        result = nil
        elapsed = Benchmark.realtime { result = wait(task, timeout_seconds: 30) }

        expect(elapsed).to be < 1.0, "#{status} should not wait"
        expect(result).to include(success: true, done: true, status: status, task_id: task.task_id)
        expect(result[:output]).to eq({ "result" => "r" })
        expect(result[:error_message]).to eq("boom") if status == "failed"
      end
    end

    it "takes its terminal set from the model, not a local list" do
      stub_const("Ai::A2aTask::TERMINAL_STATUSES", %w[completed failed cancelled active].freeze)

      expect(wait(running, timeout_seconds: 30)).to include(done: true, status: "active")
    end

    # In production the task is finished by ANOTHER process, and the request's
    # query cache would answer every poll of the same task from the first read.
    # A same-process update clears that cache on its own, so this cannot be shown
    # by finishing the task here (a mutation check confirmed an SQL-count version
    # of this example passed without the fix). Pin the call instead: every read in
    # the wait goes through ActiveRecord::Base.uncached.
    it "reads the task through ActiveRecord::Base.uncached on every poll" do
      task = running
      calls = 0
      allow(tool).to receive(:sleep) { calls += 1 }
      uncached_calls = 0
      allow(ActiveRecord::Base).to receive(:uncached).and_wrap_original do |original, &block|
        uncached_calls += 1
        original.call(&block)
      end

      wait(task, timeout_seconds: 1)

      expect(calls).to be >= 1
      expect(uncached_calls).to eq(calls + 1) # the first look plus one per poll
    end

    it "sees a task that finishes DURING the wait" do
      task = running
      calls = 0
      allow(tool).to receive(:sleep) do
        calls += 1
        task.update!(status: "completed", completed_at: Time.current) if calls == 2
      end

      result = wait(task, timeout_seconds: 30)

      expect(result).to include(done: true, status: "completed")
    end

    it "reports an unknown task as an error, as before" do
      result = tool.execute(params: { action: "wait_for_task", task_id: SecureRandom.uuid })

      expect(result).to include(success: false, error: "Task not found")
    end
  end

  describe "concurrent waiters" do
    let(:limiter) { described_class.wait_limiter }

    before do
      stub_const("#{described_class}::WAIT_MAX_PER_ACCOUNT", 2)
      stub_const("#{described_class}::WAIT_MAX_SERVER_WIDE", 3)
      described_class.reset_wait_limiter!
    end

    after { described_class.reset_wait_limiter! }

    it "refuses the waiter beyond the per-account limit with a named reason, without waiting" do
      2.times { expect(limiter.acquire(account.id)).to eq(:ok) }

      result = nil
      elapsed = Benchmark.realtime { result = wait(running, timeout_seconds: 30) }

      expect(elapsed).to be < 3.0 # refused, not held for the 30s asked for
      expect(result).to include(success: false, reason: "too_many_concurrent_waits", scope: "account")
      expect(result[:max_concurrent]).to eq(2)
      expect(result[:error]).to match(/wait/i)
    end

    it "does not let one account's waiters refuse another account's" do
      2.times { limiter.acquire(account.id) }
      other = create(:account)
      other_user = create(:user, account: other, permissions: %w[ai.agents.read ai.agents.execute])
      other_task = create(:ai_a2a_task, :completed, account: other)

      result = described_class.new(account: other, user: other_user)
                              .execute(params: { action: "wait_for_task", task_id: other_task.task_id })

      expect(result).to include(success: true, done: true)
    end

    it "refuses beyond the server-wide limit too, naming that scope" do
      accounts = Array.new(3) { create(:account) }
      accounts.each { |a| expect(limiter.acquire(a.id)).to eq(:ok) }

      result = wait(running, timeout_seconds: 30)

      expect(result).to include(success: false, reason: "too_many_concurrent_waits", scope: "server")
    end

    it "releases its slot when the wait ends, so the next waiter is served" do
      2.times { wait(running, timeout_seconds: 1) }
      2.times { wait(running, timeout_seconds: 1) }

      expect(limiter.in_use(account.id)).to eq(0)
    end

    it "releases its slot even when the wait raises" do
      allow(tool).to receive(:sleep).and_raise(RuntimeError, "boom")

      expect { wait(running, timeout_seconds: 30) }.to raise_error(RuntimeError, "boom")
      expect(limiter.in_use(account.id)).to eq(0)
    end

    it "counts correctly under real thread contention: never more than the limit at once" do
      stub_const("#{described_class}::WAIT_MAX_PER_ACCOUNT", 5)
      stub_const("#{described_class}::WAIT_MAX_SERVER_WIDE", 50)
      held = Concurrent::AtomicFixnum.new(0)
      peak = Concurrent::AtomicFixnum.new(0)
      granted = Concurrent::AtomicFixnum.new(0)

      Array.new(40) do
        Thread.new do
          next unless limiter.acquire(account.id) == :ok

          granted.increment
          now = held.increment
          peak.update { |p| [ p, now ].max }
          Thread.pass
          held.decrement
          limiter.release(account.id)
        end
      end.each(&:join)

      expect(peak.value).to be <= 5
      expect(granted.value).to be >= 1
      expect(limiter.in_use(account.id)).to eq(0)
    end

    it "takes the default cap for a zero, negative, non-numeric or absent timeout_seconds, and clamps a float" do
      stub_const("#{described_class}::WAIT_MAX_SECONDS", 1)

      [ 0, -3, "abc", nil, "0" ].each do |value|
        expect(wait(running, timeout_seconds: value)[:wait_seconds]).to eq(1), value.inspect
      end
      expect(wait(running, timeout_seconds: 9.9)[:wait_seconds]).to eq(1)
    end

    it "does not take a slot for a task that has already finished" do
      2.times { limiter.acquire(account.id) }
      done = create(:ai_a2a_task, :completed, account: account)

      expect(wait(done, timeout_seconds: 30)).to include(success: true, done: true)
    end
  end

  describe "the declaration" do
    it "describes the new behaviour and no longer promises a 300 second wait or an error on timeout" do
      declared = described_class.action_definitions.fetch("wait_for_task")
      text = [ declared[:description], declared.dig(:parameters, :timeout_seconds, :description) ].join(" ")

      expect(text).to include(described_class::WAIT_MAX_SECONDS.to_s)
      expect(text).to match(/done: false|timed_out/)
      expect(text).not_to include("300")
    end
  end
end

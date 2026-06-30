# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::RalphLoop, type: :model do
  let(:account) { create(:account) }
  let(:loop_record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

  # ==========================================================================
  # Tier-2(c) §5: atomic loop-row state writes. These previously read-modify-
  # wrote without a lock and drifted / lost entries under concurrency.
  # ==========================================================================
  describe "#increment_iteration!" do
    it "increments the iteration counter by one" do
      expect { loop_record.increment_iteration! }
        .to change { loop_record.reload.current_iteration }.from(0).to(1)
    end

    it "recovers from counter drift using the max completed iteration" do
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 5)
      loop_record.increment_iteration!
      expect(loop_record.reload.current_iteration).to eq(5)
    end

    it "serializes the update under a row lock" do
      expect(loop_record).to receive(:with_lock).and_call_original
      loop_record.increment_iteration!
    end
  end

  describe "#add_learning" do
    it "appends a structured learning entry" do
      loop_record.add_learning("Discovered a flaky spec", context: { task_key: "IMP-1" })
      entry = loop_record.reload.learnings.last

      expect(entry["text"]).to eq("Discovered a flaky spec")
      expect(entry["context"]).to eq({ "task_key" => "IMP-1" })
      expect(entry["iteration"]).to eq(loop_record.current_iteration)
    end

    it "preserves prior learnings across successive appends" do
      loop_record.add_learning("first")
      loop_record.add_learning("second")
      texts = loop_record.reload.learnings.map { |l| l["text"] }
      expect(texts).to eq(%w[first second])
    end

    it "appends under a row lock" do
      expect(loop_record).to receive(:with_lock).and_call_original
      loop_record.add_learning("locked append")
    end

    it "scrubs secrets out of the learning text before persisting (G15)" do
      loop_record.add_learning('Set api_key=sk-supersecretvalue123 in the env')
      text = loop_record.reload.learnings.last["text"]
      expect(text).not_to include("sk-supersecretvalue123")
      expect(text).to match(/\[REDACTED/)
    end
  end

  describe "#real_test_execution?" do
    it "is ON by default (G1: the gate is opt-out, not opt-in)" do
      expect(loop_record.real_test_execution?).to be true
    end

    it "stays ON when the flag is set true without a test command (auto-detected)" do
      loop_record.update!(configuration: { "real_test_execution" => true })
      expect(loop_record.real_test_execution?).to be true
    end

    it "is OFF only when explicitly opted out" do
      loop_record.update!(configuration: { "real_test_execution" => false })
      expect(loop_record.real_test_execution?).to be false
    end
  end

  describe "#test_command" do
    it "is nil when unset (TestVerificationService auto-detects the framework)" do
      expect(loop_record.test_command).to be_nil
    end

    it "returns the configured command when present" do
      loop_record.update!(configuration: { "test_command" => "bundle exec rspec" })
      expect(loop_record.test_command).to eq("bundle exec rspec")
    end

    it "treats a blank command as nil" do
      loop_record.update!(configuration: { "test_command" => "  " })
      expect(loop_record.test_command).to be_nil
    end
  end

  describe "#repository_full_name" do
    it "derives owner/repo from an https URL with a .git suffix" do
      loop_record.update!(repository_url: "https://git.example.com/acme/widget.git")
      expect(loop_record.repository_full_name).to eq("acme/widget")
    end

    it "derives owner/repo from an ssh:// URL" do
      loop_record.update!(repository_url: "ssh://git@git.example.com/acme/widget.git")
      expect(loop_record.repository_full_name).to eq("acme/widget")
    end

    it "is nil when no repository_url is set" do
      loop_record.update_column(:repository_url, nil)
      expect(loop_record.repository_full_name).to be_nil
    end
  end
end

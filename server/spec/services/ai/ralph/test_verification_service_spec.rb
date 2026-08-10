# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::TestVerificationService do
  # A stub runner: returns whatever canned result it's constructed with, and
  # records the command/dir it was asked to run.
  def runner_returning(stdout: "", stderr: "", exit_code: 0)
    calls = []
    callable = lambda do |command:, dir:, timeout_seconds:|
      calls << { command: command, dir: dir, timeout_seconds: timeout_seconds }
      { stdout: stdout, stderr: stderr, exit_code: exit_code }
    end
    [callable, calls]
  end

  describe "#detect" do
    subject(:service) { described_class.new(runner: ->(**) { {} }) }

    it "detects rspec from a Gemfile" do
      expect(service.detect(["Gemfile", "app", "spec"]))
        .to eq(framework: "rspec", command: "bundle exec rspec")
    end

    it "detects pytest from pyproject.toml" do
      expect(service.detect(["pyproject.toml", "src"])[:framework]).to eq("pytest")
    end

    it "detects jest from package.json" do
      expect(service.detect(["package.json"])[:framework]).to eq("jest")
    end

    it "detects go and cargo" do
      expect(service.detect(["go.mod"])[:framework]).to eq("gotest")
      expect(service.detect(["Cargo.toml"])[:framework]).to eq("cargo")
    end

    it "prefers the first matching manifest (Gemfile over package.json)" do
      expect(service.detect(["package.json", "Gemfile"])[:framework]).to eq("rspec")
    end

    it "returns nil when no manifest is recognised" do
      expect(service.detect(["README.md", "LICENSE"])).to be_nil
    end
  end

  describe "#parse_counts" do
    subject(:service) { described_class.new(runner: ->(**) { {} }) }

    it "parses rspec summaries" do
      expect(service.parse_counts("rspec", "10 examples, 2 failures, 0 pending"))
        .to eq(passed_count: 8, failed_count: 2)
    end

    it "parses pytest summaries including errors" do
      expect(service.parse_counts("pytest", "5 passed, 1 failed, 1 error in 0.2s"))
        .to eq(passed_count: 5, failed_count: 2)
    end

    it "parses jest summaries" do
      out = "Tests:       1 failed, 7 passed, 8 total"
      expect(service.parse_counts("jest", out)).to eq(passed_count: 7, failed_count: 1)
    end

    it "parses cargo summaries" do
      expect(service.parse_counts("cargo", "test result: ok. 12 passed; 0 failed; 0 ignored"))
        .to eq(passed_count: 12, failed_count: 0)
    end

    it "returns nils when output is unparseable" do
      expect(service.parse_counts("rspec", "boom, segfault")).to eq(passed_count: nil, failed_count: nil)
    end
  end

  describe "#verify" do
    it "reports success on clean exit with zero failures" do
      runner, calls = runner_returning(stdout: "5 examples, 0 failures", exit_code: 0)
      result = described_class.new(runner: runner).verify(dir: "/sandbox", root_entries: ["Gemfile"])

      expect(result).to include(success: true, ran: true, framework: "rspec",
                                passed_count: 5, failed_count: 0, exit_code: 0)
      expect(calls.first).to include(command: "bundle exec rspec", dir: "/sandbox")
    end

    it "reports failure when the suite has failures (clean exit but parsed failures)" do
      runner, = runner_returning(stdout: "5 examples, 2 failures", exit_code: 0)
      result = described_class.new(runner: runner).verify(dir: "/s", root_entries: ["Gemfile"])

      expect(result).to include(success: false, ran: true, failed_count: 2)
    end

    it "reports failure on a non-zero exit even if counts are unparseable" do
      runner, = runner_returning(stderr: "LoadError: boom", exit_code: 1)
      result = described_class.new(runner: runner).verify(dir: "/s", root_entries: ["Gemfile"])

      expect(result).to include(success: false, ran: true, exit_code: 1)
    end

    it "does not run when no framework is detected" do
      runner, calls = runner_returning(exit_code: 0)
      result = described_class.new(runner: runner).verify(dir: "/s", root_entries: ["README.md"])

      expect(result).to include(success: false, ran: false)
      expect(calls).to be_empty
    end

    it "captures runner exceptions as a non-success, non-ran error" do
      raising = ->(**) { raise "worker unreachable" }
      result = described_class.new(runner: raising).verify(dir: "/s", root_entries: ["Gemfile"])

      expect(result).to include(success: false, ran: false)
      expect(result[:error]).to match(/worker unreachable/)
    end

    it "truncates very large output" do
      runner, = runner_returning(stdout: "x" * 50_000, exit_code: 0)
      result = described_class.new(runner: runner).verify(dir: "/s", root_entries: ["Gemfile"])

      expect(result[:output].length).to be <= described_class::MAX_OUTPUT_CHARS
    end
  end

  describe "#evaluate (async callback path)" do
    subject(:service) { described_class.new(runner: ->(**) { {} }) }

    it "builds a success result from raw worker output" do
      result = service.evaluate(framework: "rspec", output: "9 examples, 0 failures", exit_code: 0, command: "bundle exec rspec")
      expect(result).to include(success: true, ran: true, framework: "rspec",
                                passed_count: 9, failed_count: 0, command: "bundle exec rspec")
    end

    it "fails on parsed failures despite a clean exit" do
      result = service.evaluate(framework: "pytest", output: "3 passed, 2 failed", exit_code: 0)
      expect(result).to include(success: false, failed_count: 2)
    end

    it "fails on a non-zero exit even when counts are unparseable" do
      result = service.evaluate(framework: "rspec", output: "segfault", exit_code: 139)
      expect(result).to include(success: false, exit_code: 139)
    end

    it "fails closed on a blank framework even with a clean exit (G1)" do
      result = service.evaluate(framework: nil, output: "everything is fine", exit_code: 0)
      expect(result).to include(success: false, ran: false)
    end
  end

  # IMP-f2b3e9a67d11 — evidence adjudication for the MCP dev-loop bridge.
  # Reuses parse_counts across every framework this service already speaks, so
  # a non-Ruby executor's honest green evidence is never downgraded to
  # attested just for not being rspec-shaped.
  describe ".adjudicate_check_results" do
    def verdict_of(check_results)
      described_class.adjudicate_check_results(check_results)[:verdict]
    end

    it "verifies an rspec green tally" do
      expect(verdict_of({ "rspec" => "90 examples, 0 failures" })).to eq(:verified)
    end

    it "verifies pytest-style green evidence" do
      expect(verdict_of({ "pytest" => "12 passed in 3.4s" })).to eq(:verified)
    end

    it "verifies go-test-style green evidence" do
      expect(verdict_of({ "go_test" => "ok  github.com/x/agent/internal/dockerd  0.029s" })).to eq(:verified)
    end

    it "contradicts a pass whose only tallies fail" do
      expect(verdict_of({ "rspec" => "90 examples, 1 failure" })).to eq(:contradicted)
      expect(verdict_of({ "go_test" => "--- FAIL: TestReconcile (0.01s)" })).to eq(:contradicted)
    end

    it "stays verified when red-first evidence coexists with a green tally" do
      expect(verdict_of({ "rspec" => "90 examples, 0 failures",
                          "red_first" => "5 examples, 5 failures before the fix" })).to eq(:verified)
    end

    it "is unverified for prose-only evidence or none" do
      expect(verdict_of({ "note" => "all good, trust me" })).to eq(:unverified)
      expect(verdict_of(nil)).to eq(:unverified)
    end

    it "does not treat a nothing-ran tally as green evidence" do
      expect(verdict_of({ "rspec" => "0 examples, 0 failures" })).to eq(:unverified)
    end

    it "adjudicates strings inside nested structured evidence" do
      expect(verdict_of({ "rspec" => { "summary" => "12 examples, 0 failures" } })).to eq(:verified)
    end

    # IMP-60f457f6e8a6 — integer counts are BETTER evidence than a prose tally,
    # but deep_string_values dropped every non-String, so honest structured
    # evidence adjudicated :unverified and stranded its offer at approved.
    context "with structured integer counts" do
      it "verifies a green count pair, including prefixed keys" do
        expect(verdict_of({ "examples" => 173, "failures" => 0 })).to eq(:verified)
        expect(verdict_of({ "batch_examples" => 173, "batch_failures" => 0 })).to eq(:verified)
        expect(verdict_of({ "tests" => 20, "failed_count" => 0 })).to eq(:verified)
        expect(verdict_of({ "passed" => 12, "failed" => 0 })).to eq(:verified)
      end

      it "adjudicates a count pair nested inside evidence" do
        expect(verdict_of({ "rspec" => { "examples" => 12, "failures" => 0 } })).to eq(:verified)
      end

      it "contradicts a count pair that shows failures" do
        expect(verdict_of({ "examples" => 173, "failures" => 2 })).to eq(:contradicted)
      end

      it "does not treat a structured nothing-ran tally as green" do
        expect(verdict_of({ "examples" => 0, "failures" => 0 })).to eq(:unverified)
      end

      # The load-bearing guard: this branch WIDENS what counts as verified, and
      # a verified pass auto-applies its offer. One stray zero must never
      # manufacture a green.
      it "requires both counts in the SAME node and ignores non-test zeroes" do
        expect(verdict_of({ "failures" => 0 })).to eq(:unverified)
        expect(verdict_of({ "lint_errors" => 0, "files_total" => 3 })).to eq(:unverified)
        expect(verdict_of({ "suite_a" => { "failures" => 0 },
                            "suite_b" => { "examples" => 9 } })).to eq(:unverified)
      end

      it "does not read a fail-named key as the total" do
        expect(verdict_of({ "failed_examples" => 0, "failures" => 0 })).to eq(:unverified)
      end

      it "ignores non-integer counts" do
        expect(verdict_of({ "examples" => "many", "failures" => 0 })).to eq(:unverified)
      end
    end
  end
end

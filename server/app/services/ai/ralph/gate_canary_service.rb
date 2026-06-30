# frozen_string_literal: true

module Ai
  module Ralph
    # Gate-integrity canary (G11). Gates rot over time: a silently-broken
    # verification gate — e.g. G1's real-test verification regressing to
    # always-pass — would read green forever, fabricating `checks_passed: true`
    # all over again with nothing to notice.
    #
    # This service feeds a FIXED set of known-good and known-bad inputs through
    # the live TestVerification-style gate and asserts each verdict still matches
    # expectation. A gate that starts passing a known-bad input (or failing a
    # known-good one) flips `healthy` to false so the periodic worker job
    # (AiGateCanaryJob) can alert.
    #
    # The logic lives in core (server) so it is unit-testable against the real
    # gate; the worker job is only the periodic trigger + alert. The `gate` is
    # injectable purely so specs can simulate a regressed gate.
    class GateCanaryService
      # Each case feeds (framework, output, exit_code) through the gate's
      # #evaluate and asserts the resulting `success:` equals `expected`.
      # Add cases here to extend the canary — keep them deterministic (no
      # filesystem / no command execution; #evaluate is parse-only).
      CANARY_CASES = [
        # --- known GOOD: a clean run must be trusted as a pass ---
        { name: "rspec_clean_pass",  framework: "rspec",  output: "5 examples, 0 failures",
          exit_code: 0, command: "bundle exec rspec", expected: true },
        { name: "pytest_clean_pass", framework: "pytest", output: "3 passed in 0.12s",
          exit_code: 0, command: "python -m pytest -q", expected: true },

        # --- known BAD: each MUST fail closed ---
        # Non-zero exit is always a failure regardless of parse.
        { name: "nonzero_exit_fails", framework: "rspec", output: "5 examples, 0 failures",
          exit_code: 1, command: "bundle exec rspec", expected: false },
        # Parsed failures with a (lying) clean exit must still fail.
        { name: "rspec_parsed_failures_fail", framework: "rspec", output: "5 examples, 2 failures",
          exit_code: 0, command: "bundle exec rspec", expected: false },
        { name: "pytest_parsed_failures_fail", framework: "pytest", output: "2 failed, 3 passed in 0.2s",
          exit_code: 0, command: "python -m pytest -q", expected: false },
        # The fail-closed invariant: a blank framework + clean exit must NOT pass
        # (the worker could not identify a suite — a green exit code is untrusted).
        { name: "blank_framework_fail_closed", framework: "", output: "everything is fine",
          exit_code: 0, command: nil, expected: false }
      ].freeze

      # gate: any object responding to #evaluate(framework:, output:, exit_code:, command:)
      #   and returning a hash with `success:`. Defaults to the real gate; specs
      #   inject a regressed gate to prove the canary catches rot.
      def initialize(gate: TestVerificationService.new)
        @gate = gate
      end

      # Returns { healthy:, checks: [{ name:, expected:, actual:, ok: }] }.
      # healthy == every check's actual verdict matched its expectation.
      def run
        checks = CANARY_CASES.map do |c|
          actual = evaluate_case(c)
          { name: c[:name], expected: c[:expected], actual: actual, ok: actual == c[:expected] }
        end

        { healthy: checks.all? { |chk| chk[:ok] }, checks: checks }
      end

      private

      def evaluate_case(canary)
        result = @gate.evaluate(
          framework: canary[:framework],
          output: canary[:output],
          exit_code: canary[:exit_code],
          command: canary[:command]
        )
        # Normalise to a strict boolean so `actual == expected` is reliable even
        # if a regressed gate returns a truthy non-boolean.
        result[:success] == true
      rescue StandardError
        # A gate that raises on a canary input is itself broken — treat as a
        # non-pass so the verdict diverges from any `expected: true` case.
        false
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Ralph
    # Runs a repository's REAL test suite in an isolated sandbox and returns a
    # structured pass/fail result — the replacement for the autonomous loop's
    # fabricated `checks_passed: true`.
    #
    # Detection (which test command to run) and parsing (how many passed/failed)
    # are pure and fully unit-tested. Actual command execution is delegated to an
    # injected `runner` — in production the worker-backed TestExecutionBackend
    # (Phase A2), a stub in tests — so this service never shells out directly and
    # honours the server/worker boundary (no Sidekiq, no Open3 on the API host).
    #
    # The caller gates invocation behind a flag (RalphLoop configuration
    # "real_test_execution"); this service is inert until a runner is wired.
    class TestVerificationService
      # Manifest file (at repo root) => test framework + default command.
      # Order matters: the first matching manifest wins.
      FRAMEWORKS = [
        { manifest: "Gemfile",          framework: "rspec",  command: "bundle exec rspec" },
        { manifest: "pytest.ini",       framework: "pytest", command: "python -m pytest -q" },
        { manifest: "pyproject.toml",   framework: "pytest", command: "python -m pytest -q" },
        { manifest: "setup.py",         framework: "pytest", command: "python -m pytest -q" },
        { manifest: "requirements.txt", framework: "pytest", command: "python -m pytest -q" },
        { manifest: "package.json",     framework: "jest",   command: "npm test --silent" },
        { manifest: "go.mod",           framework: "gotest", command: "go test ./..." },
        { manifest: "Cargo.toml",       framework: "cargo",  command: "cargo test" }
      ].freeze

      MAX_OUTPUT_CHARS = 20_000

      # Server-side adjudication of an EXTERNAL executor's self-reported
      # check_results (IMP-f2b3e9a67d11). The MCP dev-loop bridge cannot
      # execute the executor's suite — the code lives in the executor's own
      # checkout — so the enforceable contract is over the evidence itself,
      # parsed with the SAME parse_counts every framework path uses (rspec,
      # pytest, jest, gotest, cargo — one vocabulary, no second regex):
      #
      #   any zero-failure tally       → :verified    (red-first tallies with
      #                                                failures may coexist)
      #   tallies present, ALL failing → :contradicted (the pass is rejected)
      #   no parseable tallies         → :unverified  (recorded as attested;
      #                                                no auto-apply)
      #
      # A parsed passed_count with a nil failed_count reads as green — the
      # frameworks only print failure counts when failures exist — but a tally
      # whose counts show NOTHING ran ("0 examples, 0 failures": a typo'd
      # filter, an empty glob) is not green evidence; it drops to :unverified.
      # Values are size-capped like the runner path's output, and nested
      # hashes/arrays are flattened so structured evidence still adjudicates —
      # both the tally STRINGS inside it and, per deep_count_tallies below, a
      # node's own integer count pair such as {examples: 173, failures: 0}.
      # KNOWN, ACCEPTED LIMITS of a coarse honesty filter: fabricated-but-
      # plausible evidence passes, and the any-green rule means a clean tally
      # under ONE key can mask failing tallies under another (the price of
      # tolerating red-first evidence without per-key naming heuristics). The
      # ungameable backstop remains the revert metric; what IS caught here is
      # a pass whose own evidence shows only failures, or none at all.
      def self.adjudicate_check_results(check_results)
        values = deep_string_values(check_results).map { |v| v[0, MAX_OUTPUT_CHARS] }
        parser = new
        frameworks = FRAMEWORKS.map { |f| f[:framework] }.uniq

        tallies = values.flat_map do |value|
          frameworks.filter_map do |framework|
            counts = parser.parse_counts(framework, value)
            next if counts[:passed_count].nil? && counts[:failed_count].nil?

            { framework: framework, passed: counts[:passed_count], failures: counts[:failed_count].to_i }
          end
        end
        tallies += deep_count_tallies(check_results)

        green = tallies.any? do |t|
          t[:failures].zero? && (t[:passed].nil? || t[:passed].positive?)
        end
        failing = tallies.any? { |t| t[:failures].positive? }

        verdict =
          if green then :verified
          elsif failing then :contradicted
          else :unverified
          end
        { verdict: verdict, tallies: tallies }
      end

      # IMP-60f457f6e8a6: structured integer counts are BETTER evidence than a
      # prose tally, yet deep_string_values drops every non-String, so honest
      # evidence like {examples: 173, failures: 0} parsed to nothing,
      # adjudicated :unverified, and left its offer stranded at approved with
      # no seam to re-supply evidence (43 offers reached that state).
      #
      # This branch WIDENS what counts as :verified, and a verified pass
      # auto-applies its linked offer — so it is deliberately narrow. A node
      # must carry BOTH an integer test-total/passed count AND an integer
      # failure count, read from the SAME hash node so sibling keys under
      # unrelated sections can never be recombined into a green. A lone
      # {"failures" => 0}, or a non-test pair like {"lint_errors" => 0,
      # "files_total" => 3}, stays :unverified.
      # "examples/tests/specs" NAME a test run; "passed/passes" only counts
      # something. Keeping them in one alternation made any {passed:, failed:}
      # pair read as test evidence, so a gate/step/lint summary — shapes an
      # executor legitimately puts in check_results, which is documented only as
      # "Verification evidence" — adjudicated :verified and AUTO-APPLIED its
      # offer with zero tests run. Over-crediting is the dangerous direction:
      # nothing alerts, the funnel just reads as approved-and-applied.
      # They are split so a bare count must earn its scope (see #test_scoped?).
      TEST_NOUN_TOTAL_KEY = /\A(?:\w*_)?(?:examples?|tests?|specs?)(?:_count)?\z/i
      BARE_TOTAL_KEY      = /\A(?:\w*_)?(?:passed|passes)(?:_count)?\z/i
      FAIL_COUNT_KEY      = /\A(?:\w*_)?(?:failures?|failed|errors?)(?:_count)?\z/i
      # A fail count with no qualifier, or one sharing the total's qualifier, is
      # the suite's own. Anything else ("secret_scan_errors", "tsc_errors") is a
      # DIFFERENT check reported alongside — see #relevant_failures.
      # errors_outside_of_examples is RSpec's own JSON key for "files failed to
      # load" — a SUITE-level error count, not a different check's, and the single
      # commonest "0 failures but nothing really ran" shape. It does not end in a
      # fail noun, so the end-anchored pattern below excluded it from the failure
      # set while /fail|error/ still barred it from being the total: the node then
      # adjudicated {passed: 10, failures: 0} and auto-applied the offer.
      PLAIN_FAIL_KEY = /\A(?:(?:failures?|failed|errors?)(?:_count)?|errors_outside_of_examples)\z/i
      # The \w*_ prefix on the total accepts any qualifier, including ones that
      # invert the meaning: "skipped_specs"/"pending_examples" counted as the
      # PASSED total and adjudicated verified on evidence that zero tests passed.
      NON_PASSING_PREFIX = /\A(?:skipped|pending|filtered|deleted|ignored|todo|disabled)_/i

      # Scope requires a RUNNER NAME, not a test-sounding word. Generic tokens
      # (test/spec/suite) let "test_plan", "spec_review" and a gate nested under
      # "specs" re-open the bare-count hole this exists to close — a plan or a
      # review is not a test run. Framework names are unambiguous, and are read
      # from FRAMEWORKS so a new runner stays in sync.
      TEST_FRAMEWORK_NAMES = FRAMEWORKS.map { |f| f[:framework] }.uniq.freeze

      # Scope is inherited from ANY ancestor, not just the immediate parent:
      # runner -> summary -> counts is one of the commonest evidence layouts, and
      # keying on the closest ancestor alone ("summary") strands it as unverified.
      # Separators are stripped rather than split on, so "go_test" normalises to
      # "gotest" and matches, while "latest" still cannot match anything.
      #
      # EQUALITY, not include?: a substring test grants scope to any key merely
      # CONTAINING a runner's name, so "rspec_migration_plan" and
      # "cargo_cult_refactor" qualified — re-opening the bare-count hole from the
      # other side, and contradicting this file's own rule that a plan or a review
      # is not a test run.
      def self.test_scoped?(ancestors)
        ancestors.any? do |key|
          normalized = key.to_s.downcase.gsub(/[^a-z0-9]/, "")
          TEST_FRAMEWORK_NAMES.include?(normalized)
        end
      end
      private_class_method :test_scoped?

      def self.deep_count_tallies(value, depth = 0, ancestors = [])
        return [] if depth > 4

        case value
        when Hash
          nested = value.flat_map { |k, v| deep_count_tallies(v, depth + 1, ancestors + [k.to_s]) }
          (tally = hash_node_tally(value, ancestors)) ? nested.unshift(tally) : nested
        when Array then value.flat_map { |v| deep_count_tallies(v, depth + 1, ancestors) }
        else []
        end
      end
      private_class_method :deep_count_tallies

      # A single hash node's own integer counts, or nil when it is not a tally.
      # The total must not itself be fail-named ("failed_examples" is a failure
      # count wearing a total's noun, never the denominator).
      def self.hash_node_tally(hash, ancestors = [])
        ints = hash.filter_map { |k, v| [k.to_s, v] if v.is_a?(Integer) }.to_h
        candidates = ints.reject { |k, _| k.match?(/fail|error/i) || k.match?(NON_PASSING_PREFIX) }
        # Prefer a test noun when the node carries both; picking by hash order
        # let a bare "passed" shadow a qualifying "examples" in the same node and
        # reject the whole tally.
        total_key, total = candidates.find { |k, _| k.match?(TEST_NOUN_TOTAL_KEY) } ||
                           candidates.find { |k, _| k.match?(BARE_TOTAL_KEY) }
        failures = total_key && relevant_failures(ints, total_key).max
        return nil if total.nil? || failures.nil?
        # A bare passed/passes total is only test evidence when some enclosing key
        # names a test runner; unscoped, it is any pass/fail counter at all.
        return nil if total_key.match?(BARE_TOTAL_KEY) && !test_scoped?(ancestors)

        { framework: "structured", passed: total, failures: failures }
      end
      private_class_method :hash_node_tally

      # The failure counts belonging to THIS suite: unqualified ones, plus any
      # sharing the total's qualifier ("batch_examples" pairs with
      # "batch_failures"). Taking the max over every fail-named key instead made
      # a green suite reported beside an unrelated counter — {examples: 120,
      # failures: 0, secret_scan_errors: 1} — adjudicate :contradicted, which
      # HARD-REFUSES the executor's pass and strands the task in_progress. A
      # gitleaks or tsc count is a different check, not this suite's failures.
      # Returning [] (so #max is nil, so no tally) is the safe direction: a lone
      # unrelated error count credits nothing rather than contradicting.
      def self.relevant_failures(ints, total_key)
        prefix = total_key[/\A(\w*?_)(?=examples?|tests?|specs?|passed|passes)/i, 1]
        ints.select do |k, _|
          # PLAIN_FAIL_KEY first: FAIL_COUNT_KEY is end-anchored on a fail noun, so
          # it rejects errors_outside_of_examples and would gate it out before the
          # suite-level check below ever ran.
          next true if k.match?(PLAIN_FAIL_KEY)
          next false unless k.match?(FAIL_COUNT_KEY)

          prefix && k.downcase.start_with?(prefix.downcase)
        end.values
      end
      private_class_method :relevant_failures

      # Strings from arbitrarily nested hash/array evidence, depth-capped.
      def self.deep_string_values(value, depth = 0)
        return [] if depth > 4

        case value
        when String then [ value ]
        when Hash   then value.values.flat_map { |v| deep_string_values(v, depth + 1) }
        when Array  then value.flat_map { |v| deep_string_values(v, depth + 1) }
        else []
        end
      end
      private_class_method :deep_string_values

      # runner: a callable responding to #call(command:, dir:, timeout_seconds:)
      #   and returning { stdout:, stderr:, exit_code: }. Optional — only #verify
      #   needs it; the async callback uses #evaluate (parse-only, no runner).
      def initialize(runner: nil)
        @runner = runner
      end

      # root_entries: filenames present at the repo root (so detection needs no
      #   filesystem access and stays unit-testable).
      # dir: the isolated checkout path the runner should execute in.
      def verify(dir:, root_entries:, timeout_seconds: 600)
        detected = detect(root_entries)
        return not_run("No recognised test framework at repo root") unless detected

        raw = @runner.call(command: detected[:command], dir: dir, timeout_seconds: timeout_seconds)
        output = "#{raw[:stdout]}\n#{raw[:stderr]}".strip
        evaluate(framework: detected[:framework], output: output, exit_code: raw[:exit_code], command: detected[:command])
      rescue StandardError => e
        Rails.logger.error("[TestVerification] #{e.class}: #{e.message}")
        { success: false, ran: false, framework: nil, command: nil, passed_count: nil,
          failed_count: nil, exit_code: nil, summary: nil, output: nil, error: e.message }
      end

      # Build the structured pass/fail result from raw test output. Shared by
      # #verify (synchronous runner path) and the async worker callback, which
      # already has the framework + raw output + exit code in hand.
      #
      # Success requires a clean exit AND, when counts parsed, zero failures.
      # A clean exit with unparseable output is trusted (exit 0); a non-zero
      # exit is always a failure regardless of parse.
      def evaluate(framework:, output:, exit_code:, command: nil)
        # Fail-closed: a blank framework means the worker could not identify (or
        # auto-detect) a suite — a clean exit code must NOT be trusted as a pass.
        return not_run("No test framework reported") if framework.blank?

        exit_code = exit_code.to_i
        counts = parse_counts(framework, output.to_s)
        failed = counts[:failed_count]
        success = exit_code.zero? && (failed.nil? || failed.zero?)

        {
          success: success,
          ran: true,
          framework: framework,
          command: command,
          passed_count: counts[:passed_count],
          failed_count: failed,
          exit_code: exit_code,
          summary: build_summary(framework, counts, exit_code),
          output: output.to_s[0, MAX_OUTPUT_CHARS],
          error: nil
        }
      end

      # Returns { framework:, command: } or nil.
      def detect(root_entries)
        entries = Array(root_entries).map(&:to_s)
        spec = FRAMEWORKS.find { |f| entries.include?(f[:manifest]) }
        spec && { framework: spec[:framework], command: spec[:command] }
      end

      # Returns { passed_count:, failed_count: } — either may be nil when the
      # framework's output could not be parsed.
      def parse_counts(framework, output)
        case framework
        when "rspec"
          if (m = output.match(/(\d+)\s+examples?,\s+(\d+)\s+failures?/))
            { passed_count: m[1].to_i - m[2].to_i, failed_count: m[2].to_i }
          else
            blank_counts
          end
        when "pytest"
          passed = output[/(\d+)\s+passed/, 1]&.to_i
          failed = output[/(\d+)\s+failed/, 1]&.to_i
          errored = output[/(\d+)\s+errors?/, 1]&.to_i
          total_failed = [failed, errored].compact.sum if failed || errored
          { passed_count: passed, failed_count: total_failed }
        when "jest"
          # "Tests:       1 failed, 7 passed, 8 total"
          failed = output[/Tests:.*?(\d+)\s+failed/m, 1]&.to_i
          passed = output[/Tests:.*?(\d+)\s+passed/m, 1]&.to_i
          { passed_count: passed, failed_count: failed }
        when "gotest"
          # Go prints FAIL/ok per package; count FAIL lines as failures.
          failed = output.scan(/^(?:--- FAIL|FAIL\b)/).size
          { passed_count: nil, failed_count: failed.positive? ? failed : (output.match?(/^ok\b/) ? 0 : nil) }
        when "cargo"
          # "test result: ok. 12 passed; 0 failed; ..."
          if (m = output.match(/test result:.*?(\d+)\s+passed;\s+(\d+)\s+failed/m))
            { passed_count: m[1].to_i, failed_count: m[2].to_i }
          else
            blank_counts
          end
        else
          blank_counts
        end
      end

      private

      def blank_counts
        { passed_count: nil, failed_count: nil }
      end

      def not_run(reason)
        { success: false, ran: false, framework: nil, command: nil, passed_count: nil,
          failed_count: nil, exit_code: nil, summary: reason, output: nil, error: reason }
      end

      def build_summary(framework, counts, exit_code)
        p = counts[:passed_count]
        f = counts[:failed_count]
        if p || f
          "#{framework}: #{p || '?'} passed, #{f || '?'} failed (exit #{exit_code})"
        else
          "#{framework}: exit #{exit_code} (counts unparsed)"
        end
      end
    end
  end
end

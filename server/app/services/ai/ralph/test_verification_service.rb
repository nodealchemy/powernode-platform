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

      # runner: a callable responding to #call(command:, dir:, timeout_seconds:)
      #   and returning { stdout:, stderr:, exit_code: }.
      def initialize(runner:)
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
        exit_code = raw[:exit_code].to_i
        counts = parse_counts(detected[:framework], output)

        # Success requires a clean exit AND, when we could parse counts, zero
        # failures. A clean exit with unparseable output is trusted (exit 0);
        # a non-zero exit is always a failure regardless of parse.
        failed = counts[:failed_count]
        success = exit_code.zero? && (failed.nil? || failed.zero?)

        {
          success: success,
          ran: true,
          framework: detected[:framework],
          command: detected[:command],
          passed_count: counts[:passed_count],
          failed_count: failed,
          exit_code: exit_code,
          summary: build_summary(detected[:framework], counts, exit_code),
          output: output[0, MAX_OUTPUT_CHARS],
          error: nil
        }
      rescue StandardError => e
        Rails.logger.error("[TestVerification] #{e.class}: #{e.message}")
        { success: false, ran: false, framework: nil, command: nil, passed_count: nil,
          failed_count: nil, exit_code: nil, summary: nil, output: nil, error: e.message }
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

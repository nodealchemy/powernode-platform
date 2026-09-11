# frozen_string_literal: true

module Ai
  module Codebase
    class StaticAnalysisService
      # argv, never a shell string: no quoting to get wrong, and nothing a path
      # can inject into.
      LINTER_CONFIGS = {
        ruby: {
          argv: %w[bundle exec rubocop --format json],
          name: "RuboCop",
          extensions: %w[.rb .rake]
        },
        typescript: {
          argv: %w[npx tsc --noEmit --pretty false],
          name: "TypeScript",
          extensions: %w[.ts .tsx]
        },
        javascript_lint: {
          argv: %w[npx eslint --format json],
          name: "ESLint",
          extensions: %w[.js .jsx .ts .tsx]
        }
      }.freeze

      # Seconds, per linter run, ENFORCED (D1 review M3: it used to be defined
      # and never used). The whole process group is killed at the deadline.
      TIMEOUT = 120

      # The most linter output, in bytes, that is ever parsed (D1 re-verify
      # M2). A fixed 1 MB used to cut the server repository's 3.2 MB rubocop
      # report into a parse error, and a cut tsc report would parse as a
      # complete one. Output over the limit is not parsed at all: it reads as
      # `output_truncated`, a did-not-measure status. Operator configuration,
      # so it lives under the private discovery prefix; the leased runner is
      # handed the same value, and the MCP verb's local run obeys it too.
      OUTPUT_LIMIT_SETTING = "ai.improvement_discovery_output_limit_bytes"
      DEFAULT_OUTPUT_LIMIT = 16 * 1024 * 1024

      # A CLEAN ENVIRONMENT (D1 review H1). A subprocess used to inherit the
      # Rails process's environment, BUNDLE_GEMFILE and RUBYOPT included, so
      # `bundle exec rubocop` resolved against the SERVER's bundle even when run
      # inside another checkout, and a production server bundle has no rubocop.
      # The child now gets only these variables, taken from the environment as
      # it was BEFORE Bundler touched it, plus whatever a linter sets itself
      # (rubocop sets BUNDLE_GEMFILE to the working copy's own Gemfile).
      ENV_ALLOWLIST = %w[PATH HOME LANG LC_ALL TMPDIR GEM_HOME GEM_PATH].freeze

      # Statuses a linter summary can carry that mean "did not inspect the
      # code". Callers must never read these as clean.
      NOT_MEASURED_STATUSES = %w[timeout unavailable no_output parse_error error no_gemfile no_tsconfig unknown_linter
                                 output_truncated].freeze

      def self.timeout_seconds
        TIMEOUT
      end

      def self.output_limit_bytes
        configured = ::SiteSetting.get(OUTPUT_LIMIT_SETTING).to_i
        configured.positive? ? configured : DEFAULT_OUTPUT_LIMIT
      end

      def initialize(base_path:)
        @base_path = File.expand_path(base_path)
      end

      # Run static analysis on the codebase or a subdirectory.
      # @param path [String|nil] Subdirectory relative to base_path
      # @param linters [Array<String>|nil] Specific linters to run (nil = auto-detect)
      # @return [Hash] Diagnostics and summary
      def analyze(path: nil, linters: nil)
        target = path ? File.join(@base_path, path) : @base_path
        requested_linters = linters ? linters.map(&:to_sym) : detect_linters(target)

        all_diagnostics = []
        linter_results = {}

        requested_linters.each do |linter_key|
          config = LINTER_CONFIGS[linter_key]
          next unless config

          result = run_linter(linter_key, config, target)
          linter_results[config[:name]] = result[:summary]
          all_diagnostics.concat(result[:diagnostics])
        end

        errors = all_diagnostics.count { |d| d[:severity] == "error" }
        warnings = all_diagnostics.count { |d| d[:severity] == "warning" }

        {
          success: true,
          diagnostics: all_diagnostics.first(200), # Cap output
          summary: {
            total: all_diagnostics.size,
            errors: errors,
            warnings: warnings,
            linters: linter_results
          },
          truncated: all_diagnostics.size > 200
        }
      end

      # PARSING, SEPARATE FROM RUNNING (D1b). A linter's raw output becomes the
      # same diagnostics whether it ran in this process (the MCP verb) or on a
      # leased runner that handed it back (improvement discovery). `base_path`
      # is the directory the linter ran in, so reported paths come back
      # relative to the repository root either way.
      #
      # Never raises: output that cannot be read is a `parse_error`, which is
      # a did-not-measure status, never a clean one.
      #
      # @param linter_key [Symbol, String] :ruby | :typescript | :javascript_lint
      # @param output [String] the linter's stdout (tsc: stdout and stderr)
      # @param exitstatus [Integer, nil]
      # @return [Hash] {diagnostics:, summary:}
      def self.parse_output(linter_key, output:, exitstatus:, base_path:)
        new(base_path: base_path).parse_output(linter_key, output, exitstatus)
      end

      def parse_output(linter_key, output, exitstatus)
        output = output.to_s
        return truncated if output.bytesize > self.class.output_limit_bytes

        case linter_key.to_s
        when "ruby" then parse_rubocop(output)
        when "typescript" then parse_tsc(output, exitstatus)
        when "javascript_lint" then parse_eslint(output)
        else { diagnostics: [], summary: { status: "unknown_linter" } }
        end
      rescue StandardError
        { diagnostics: [], summary: { status: "parse_error" } }
      end

      private

      def detect_linters(target)
        linters = []

        # Check for Ruby
        linters << :ruby if File.exist?(File.join(find_project_root(target), "Gemfile"))

        # Check for TypeScript
        linters << :typescript if File.exist?(File.join(find_project_root(target), "tsconfig.json"))

        # Check for ESLint config
        eslint_configs = %w[.eslintrc .eslintrc.js .eslintrc.json .eslintrc.yml eslint.config.js eslint.config.mjs]
        linters << :javascript_lint if eslint_configs.any? { |c| File.exist?(File.join(find_project_root(target), c)) }

        linters
      end

      def run_linter(linter_key, config, target)
        case linter_key
        when :ruby then run_rubocop(config, target)
        when :typescript then run_tsc(config, target)
        when :javascript_lint then run_eslint(config, target)
        else { diagnostics: [], summary: { status: "unknown_linter" } }
        end
      rescue => e
        { diagnostics: [], summary: { status: "error", message: e.message } }
      end

      def run_rubocop(config, target)
        project_root = find_project_root(target)
        gemfile = File.join(project_root, "Gemfile")
        return { diagnostics: [], summary: { status: "no_gemfile" } } unless File.exist?(gemfile)

        run = execute_command(config[:argv] + [ target ], chdir: project_root, env: { "BUNDLE_GEMFILE" => gemfile })
        return not_run(run) unless run[:status] == :ran

        parse_rubocop(run[:output])
      end

      def parse_rubocop(output)
        return { diagnostics: [], summary: { status: "no_output" } } if output.blank?

        parsed = JSON.parse(output) rescue nil
        return { diagnostics: [], summary: { status: "parse_error" } } unless parsed.is_a?(Hash)

        diagnostics = []
        (parsed["files"] || []).each do |file_entry|
          file_path = relative_path(file_entry["path"])
          (file_entry["offenses"] || []).each do |offense|
            diagnostics << {
              file: file_path,
              line: offense.dig("location", "start_line"),
              column: offense.dig("location", "start_column"),
              severity: rubocop_severity(offense["severity"]),
              message: offense["message"],
              rule: offense["cop_name"],
              linter: "RuboCop"
            }
          end
        end

        {
          diagnostics: diagnostics,
          summary: {
            status: "completed",
            files_inspected: parsed.dig("summary", "inspected_file_count") || 0,
            offenses: parsed.dig("summary", "offense_count") || 0
          }
        }
      end

      def run_tsc(config, target)
        project_root = find_project_root(target)
        tsconfig = File.join(project_root, "tsconfig.json")
        return { diagnostics: [], summary: { status: "no_tsconfig" } } unless File.exist?(tsconfig)

        run = execute_command(config[:argv], chdir: project_root, merge_stderr: true)
        return not_run(run) unless run[:status] == :ran

        parse_tsc(run[:output], run[:exitstatus])
      end

      def parse_tsc(output, exitstatus)
        if output.blank?
          # Clean only on a zero exit. A tsc that failed without printing
          # anything, or whose exit status never arrived, is not a project with
          # no type errors.
          return { diagnostics: [], summary: { status: "clean", errors: 0 } } if exitstatus == 0

          return { diagnostics: [], summary: { status: "no_output" } }
        end

        diagnostics = []
        output.each_line do |line|
          # Format: file(line,col): error TS1234: message
          if line =~ /\A(.+?)\((\d+),(\d+)\):\s+(error|warning)\s+(TS\d+):\s+(.+)/
            diagnostics << {
              file: relative_path(Regexp.last_match(1)),
              line: Regexp.last_match(2).to_i,
              column: Regexp.last_match(3).to_i,
              severity: Regexp.last_match(4),
              message: Regexp.last_match(6).strip,
              rule: Regexp.last_match(5),
              linter: "TypeScript"
            }
          end
        end

        {
          diagnostics: diagnostics,
          summary: { status: "completed", errors: diagnostics.size }
        }
      end

      def run_eslint(config, target)
        project_root = find_project_root(target)
        run = execute_command(config[:argv] + [ target ], chdir: project_root)
        return not_run(run) unless run[:status] == :ran

        parse_eslint(run[:output])
      end

      def parse_eslint(output)
        return { diagnostics: [], summary: { status: "no_output" } } if output.blank?

        parsed = JSON.parse(output) rescue nil
        return { diagnostics: [], summary: { status: "parse_error" } } unless parsed.is_a?(Array)

        diagnostics = []
        parsed.each do |file_entry|
          file_path = relative_path(file_entry["filePath"])
          (file_entry["messages"] || []).each do |msg|
            diagnostics << {
              file: file_path,
              line: msg["line"],
              column: msg["column"],
              severity: msg["severity"] == 2 ? "error" : "warning",
              message: msg["message"],
              rule: msg["ruleId"],
              linter: "ESLint"
            }
          end
        end

        {
          diagnostics: diagnostics,
          summary: {
            status: "completed",
            errors: diagnostics.count { |d| d[:severity] == "error" },
            warnings: diagnostics.count { |d| d[:severity] == "warning" }
          }
        }
      end

      # Runs argv in `chdir` with a clean environment and an enforced deadline.
      #
      # @return [Hash] {status: :ran, output:, exitstatus:} |
      #   {status: :timeout} (process group killed) | {status: :unavailable}
      #   (the program is not on PATH) | {status: :output_truncated} (it
      #   printed more than output_limit_bytes)
      def execute_command(argv, chdir:, env: {}, merge_stderr: false)
        base = defined?(::Bundler) ? ::Bundler.unbundled_env : ENV.to_h
        child_env = base.slice(*ENV_ALLOWLIST).merge(env)
        reader, writer = IO.pipe
        pid = Process.spawn(child_env, *argv, chdir: chdir, in: File::NULL, out: writer,
                            err: merge_stderr ? writer : File::NULL,
                            pgroup: true, unsetenv_others: true)
        writer.close

        output = +""
        limit = self.class.output_limit_bytes
        overflow = false
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + self.class.timeout_seconds
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            kill_group(pid)
            return { status: :timeout }
          end
          next unless IO.select([ reader ], nil, nil, remaining)

          chunk = reader.read_nonblock(65_536, exception: false)
          break if chunk.nil?
          next if chunk == :wait_readable

          # Keep draining past the limit so a chatty linter cannot block on a
          # full pipe, but keep nothing once it is exceeded: a cut report is
          # not parsed (see OUTPUT_LIMIT_SETTING).
          next if overflow

          if output.bytesize + chunk.bytesize > limit
            overflow = true
            output = +""
          else
            output << chunk
          end
        end

        _, status = Process.wait2(pid)
        return { status: :output_truncated } if overflow

        { status: :ran, output: output, exitstatus: status.exitstatus }
      rescue Errno::ENOENT
        { status: :unavailable }
      ensure
        reader&.close unless reader.nil? || reader.closed?
        writer&.close unless writer.nil? || writer.closed?
      end

      def kill_group(pid)
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        nil
      ensure
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        end
      end

      def not_run(run)
        Rails.logger.warn("[StaticAnalysis] linter did not run: #{run[:status]}")
        { diagnostics: [], summary: { status: run[:status].to_s } }
      end

      def truncated
        { diagnostics: [], summary: { status: "output_truncated" } }
      end

      def rubocop_severity(severity)
        case severity
        when "error", "fatal" then "error"
        when "warning" then "warning"
        else "info"
        end
      end

      def find_project_root(path)
        current = File.directory?(path) ? path : File.dirname(path)
        while current != "/"
          return current if File.exist?(File.join(current, "Gemfile")) ||
                            File.exist?(File.join(current, "package.json")) ||
                            File.exist?(File.join(current, ".git"))
          current = File.dirname(current)
        end
        @base_path
      end

      # A linter reports paths relative to the directory it ran in (rubocop,
      # tsc) or absolute (eslint). Both resolve against @base_path, never
      # against this process's working directory, which is not where the
      # linter ran.
      def relative_path(path)
        Pathname.new(File.expand_path(path.to_s, @base_path)).relative_path_from(Pathname.new(@base_path)).to_s
      rescue ArgumentError
        path
      end
    end
  end
end

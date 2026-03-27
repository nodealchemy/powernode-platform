# frozen_string_literal: true

module Ai
  module Codebase
    class StaticAnalysisService
      LINTER_CONFIGS = {
        ruby: {
          command: "bundle exec rubocop --format json",
          name: "RuboCop",
          extensions: %w[.rb .rake]
        },
        typescript: {
          command: "npx tsc --noEmit --pretty false",
          name: "TypeScript",
          extensions: %w[.ts .tsx]
        },
        javascript_lint: {
          command: "npx eslint --format json",
          name: "ESLint",
          extensions: %w[.js .jsx .ts .tsx]
        }
      }.freeze

      TIMEOUT = 120 # seconds

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

        output = execute_command("cd #{Shellwords.escape(project_root)} && #{config[:command]} #{Shellwords.escape(target)} 2>/dev/null")
        return { diagnostics: [], summary: { status: "no_output" } } if output.blank?

        parsed = JSON.parse(output) rescue nil
        return { diagnostics: [], summary: { status: "parse_error" } } unless parsed

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

        output = execute_command("cd #{Shellwords.escape(project_root)} && #{config[:command]} 2>&1")
        return { diagnostics: [], summary: { status: "clean", errors: 0 } } if output.blank?

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
        output = execute_command("cd #{Shellwords.escape(project_root)} && #{config[:command]} #{Shellwords.escape(target)} 2>/dev/null")
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

      def execute_command(command)
        IO.popen(command, err: [:child, :out]) do |io|
          io.read(1_048_576) # 1MB max
        end
      rescue Errno::ENOENT, Errno::EPIPE => e
        Rails.logger.warn "[StaticAnalysis] Command failed: #{e.message}"
        nil
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

      def relative_path(path)
        Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(@base_path)).to_s
      rescue ArgumentError
        path
      end
    end
  end
end

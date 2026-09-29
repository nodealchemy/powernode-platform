# frozen_string_literal: true

require "open3"

module Devops
  # A narrow `git` runner for the dev-merge job (Devops::IncrementMergeService).
  #
  #   * argv only, never a shell string, so a ref cannot become a command;
  #   * one bare repository (--git-dir), no working tree and no checkout;
  #   * the host's git config is ignored (no url.insteadOf, no credential
  #     helper, no prompt), so what runs is what this file says;
  #   * credentials travel as an http.extraHeader through GIT_CONFIG_* env,
  #     never in a URL or argv, and every secret is scrubbed from output;
  #   * `git submodule` is REFUSED outright. `git submodule sync` rewrites a
  #     submodule's remote from .gitmodules and drops a private upstream, and
  #     nothing this job does needs any submodule command: a pointer bump
  #     moves one gitlink through plumbing.
  class GitCli
    Result = Struct.new(:success, :stdout, :stderr, keyword_init: true) do
      def success?
        success
      end
    end

    class Refused < StandardError; end
    class Timeout < StandardError; end

    FORBIDDEN_SUBCOMMANDS = %w[submodule].freeze
    DEFAULT_TIMEOUT = 300

    BASE_ENV = {
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_ASKPASS" => "true",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => File::NULL,
      "LC_ALL" => "C"
    }.freeze

    attr_reader :git_dir, :commands

    def initialize(git_dir:, timeout: DEFAULT_TIMEOUT)
      @git_dir = git_dir
      @timeout = timeout
      @commands = []
    end

    # @param auth_header [String, nil] a full "Authorization: ..." header
    # @param secrets [Array<String>] values to scrub from stdout/stderr
    def run(*args, env: {}, stdin: nil, auth_header: nil, secrets: [])
      args = args.map(&:to_s)
      refuse_forbidden!(args)
      @commands << args

      full_env = BASE_ENV.merge(env).merge(auth_env(auth_header))
      stdout, stderr, status = capture(full_env, [ "git", "--git-dir", git_dir, *args ], stdin)
      scrub = Array(secrets).compact.map(&:to_s).reject(&:empty?)
      scrub << auth_header.to_s unless auth_header.to_s.empty?
      Result.new(success: status.success?, stdout: scrubbed(stdout, scrub), stderr: scrubbed(stderr, scrub))
    end

    private

    def refuse_forbidden!(args)
      hit = args.find { |a| FORBIDDEN_SUBCOMMANDS.include?(a) }
      raise Refused, "git #{hit} is never run by the dev-merge job" if hit
    end

    def auth_env(header)
      return {} if header.to_s.empty?

      { "GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "http.extraHeader", "GIT_CONFIG_VALUE_0" => header }
    end

    def capture(env, argv, stdin)
      Open3.popen3(env, *argv) do |i, o, e, wait|
        i.write(stdin) if stdin
        i.close
        out_reader = Thread.new { o.read }
        err_reader = Thread.new { e.read }
        unless wait.join(@timeout)
          Process.kill("KILL", wait.pid)
          raise Timeout, "git #{argv[3]} timed out after #{@timeout}s"
        end
        [ out_reader.value.to_s, err_reader.value.to_s, wait.value ]
      end
    end

    def scrubbed(text, secrets)
      secrets.reduce(text) { |acc, secret| acc.gsub(secret, "[REDACTED]") }
    end
  end
end

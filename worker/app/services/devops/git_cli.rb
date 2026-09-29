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
  #   * transports are an allowlist, https by default (protocol.allow=never
  #     plus protocol.<name>.allow=always), and redirects are not followed,
  #     so the header cannot be sent in clear, to a redirect target, to a
  #     local path, or over the host's own SSH keys;
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
    DEFAULT_PROTOCOLS = %w[https].freeze

    BASE_ENV = {
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_ASKPASS" => "true",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => File::NULL,
      "LC_ALL" => "C"
    }.freeze

    attr_reader :git_dir, :commands

    def initialize(git_dir:, timeout: DEFAULT_TIMEOUT, allowed_protocols: DEFAULT_PROTOCOLS)
      @git_dir = git_dir
      @timeout = timeout
      @allowed_protocols = Array(allowed_protocols).map(&:to_s)
      @commands = []
    end

    # @param auth_header [String, nil] a full "Authorization: ..." header
    # @param secrets [Array<String>] values to scrub from stdout/stderr
    def run(*args, env: {}, stdin: nil, auth_header: nil, secrets: [])
      args = args.map(&:to_s)
      refuse_forbidden!(args)
      @commands << args

      full_env = BASE_ENV.merge(env).merge(config_env(auth_header))
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

    # One GIT_CONFIG_COUNT block carrying the transport policy and, when
    # given, the auth header.
    def config_env(header)
      pairs = [ %w[protocol.allow never], %w[http.followRedirects false] ]
      pairs += @allowed_protocols.map { |name| [ "protocol.#{name}.allow", "always" ] }
      pairs << [ "http.extraHeader", header ] unless header.to_s.empty?

      pairs.each_with_index.with_object({ "GIT_CONFIG_COUNT" => pairs.size.to_s }) do |((key, value), i), env|
        env["GIT_CONFIG_KEY_#{i}"] = key
        env["GIT_CONFIG_VALUE_#{i}"] = value
      end
    end

    def capture(env, argv, stdin)
      # Its own process group, so a timeout also kills git's transport helper
      # (git-remote-https), which inherited the auth header in its env.
      Open3.popen3(env, *argv, pgroup: true) do |i, o, e, wait|
        i.write(stdin) if stdin
        i.close
        out_reader = Thread.new { o.read }
        err_reader = Thread.new { e.read }
        unless wait.join(@timeout)
          Process.kill("KILL", -wait.pid)
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

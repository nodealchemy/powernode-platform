# frozen_string_literal: true

require "json"
require "shellwords"

module Powernode
  # The platform's version and build identity, as the RUNNING process can
  # truthfully state it. Nothing in the tree hand-maintains a version: it is
  # derived from release tags (X.Y.Z, no "v").
  #
  # Sources, in order:
  #
  # 1. BUILD_INFO.json — written at build time (module build stage15.sh, or the
  #    Docker build from POWERNODE_BUILD_INFO_JSON), or wherever
  #    POWERNODE_BUILD_INFO points. It carries the resolved `version`, the
  #    commit, the branch/tag and a `release` verdict. This is the only
  #    identity a deployed node has: the staged tree ships WITHOUT .git.
  # 2. `git describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'` (local
  #    development only).
  # 3. "0.0.0-dev.0[+sha]" with a warning.
  #
  # VERSION FORMAT, by build type:
  #   exact tag                      -> X.Y.Z
  #   on release/X.Y.Z, hotfix/X.Y.Z -> X.Y.Z-rc.N+sha
  #   anything else                  -> <latest tag, minor+1, patch 0>-dev.N+sha
  #   no tags reachable              -> 0.0.0-dev.0[+sha]
  # (N = commits since the latest tag.)
  #
  # DISPLAY CONTRACT (mirrored by frontend/src/shared/services/admin/versionApi.ts):
  #   release build         -> "X.Y.Z"      (exact X.Y.Z tag, built from master's tip)
  #   any other known build -> "<7-char sha>"
  #   no identity at all    -> "0.0.0-dev"
  # `release` is consistency-checked here (tag == version) rather than trusted
  # from the file alone, so a stale or inconsistent BUILD_INFO cannot promote
  # itself. (BUILD_INFO is not tamper-proof: anyone who can write it can set
  # both fields.)
  class Version
    BUILD_INFO_FILE = File.expand_path("../BUILD_INFO.json", __dir__)
    RELEASE_TAG     = /\A\d+\.\d+\.\d+\z/
    SEMVER          = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
    DESCRIBE        = /\A(\d+)\.(\d+)\.(\d+)-(\d+)-g([0-9a-f]+)\z/
    RELEASE_BRANCH  = %r{\A(?:release|hotfix)/(\d+\.\d+\.\d+)\z}
    DESCRIBE_CMD    = "describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'"
    FALLBACK        = "0.0.0-dev.0"
    UNKNOWN         = "unknown"

    class << self
      def current
        @current ||= build_info_version || git_version || fallback_version
      end

      # The plain X.Y.Z core of #current (what federation compares and sends).
      def core_version = "#{major}.#{minor}.#{patch}"

      # Pure: maps `git describe --long` output and a branch name to a version.
      # Returns nil when the describe output is not usable.
      def version_from_describe(describe, branch)
        m = DESCRIBE.match(describe.to_s.strip)
        return nil unless m

        major, minor, patch, ahead, sha = m.captures
        return "#{major}.#{minor}.#{patch}" if ahead.to_i.zero?

        sha = sha[0, 7]
        if (rb = RELEASE_BRANCH.match(branch.to_s))
          "#{rb[1]}-rc.#{ahead}+#{sha}"
        else
          "#{major}.#{minor.to_i + 1}.0-dev.#{ahead}+#{sha}"
        end
      end

      def major = version_parts[0].to_i
      def minor = version_parts[1].to_i

      def patch = version_parts[2].to_i

      # "1.2.3-beta.1" -> "beta.1"; "0.3.0-dev.4+abc" -> "dev.4"; "1.2.3" -> nil. (It used to split on "."
      # first, so a plain X.Y.Z answered its patch digit and "beta.1" lost
      # its ".1".)
      def prerelease
        current[/\A\d+\.\d+\.\d+-([^+]+)/, 1]
      end

      # --- build identity ------------------------------------------------

      # Parsed BUILD_INFO.json, or {} when none is present/readable.
      def build_info
        @build_info ||= begin
          path = ENV.fetch("POWERNODE_BUILD_INFO", BUILD_INFO_FILE)
          File.exist?(path) ? JSON.parse(File.read(path)) : {}
        rescue JSON::ParserError, SystemCallError
          {}
        end
      end

      def git_tag
        tag = build_info["tag"].to_s
        tag.match?(RELEASE_TAG) ? tag : nil
      end

      # True only for an artifact whose exact tag equals this version and
      # which the build recorded as master's tip. Both halves are required.
      def release?
        build_info["release"] == true && git_tag == current
      end

      # 7-char short sha from the build identity, then the local checkout.
      def short_sha
        @short_sha ||= build_info["short_sha"].to_s.presence ||
                       build_info["sha"].to_s[0, 7].presence ||
                       git_output("rev-parse --short HEAD")
      end

      def git_commit
        short_sha || UNKNOWN
      end

      def git_branch
        @git_branch ||= begin
          branch = build_info["branch"].to_s.presence || git_output("rev-parse --abbrev-ref HEAD")
          # A detached HEAD prints the literal "HEAD", which is not a branch.
          branch.nil? || branch == "HEAD" ? UNKNOWN : branch
        end
      end

      # What the UI shows. See the DISPLAY CONTRACT above.
      def display_version
        return current if release?
        return short_sha if short_sha

        "#{core_version}-dev"
      end

      # Build timestamp when the build recorded one; otherwise the moment this
      # process first asked (pre-existing behaviour, kept for old artifacts).
      def build_date
        @build_date ||= build_info["built_at"].to_s.presence || Time.current.iso8601
      end

      def semantic_version
        {
          version: current,
          display: display_version,
          major: major,
          minor: minor,
          patch: patch,
          prerelease: prerelease,
          release: release?,
          short_sha: short_sha,
          git_commit: git_commit,
          git_branch: git_branch,
          git_tag: git_tag,
          built_at: build_info["built_at"].to_s.presence,
          build_date: build_date
        }
      end

      def full_version_info
        {
          **semantic_version,
          build_source: build_info["source"].to_s.presence || (short_sha ? "git" : "none"),
          rails_version: Rails.version,
          ruby_version: RUBY_VERSION,
          environment: Rails.env
        }
      end

      # Drop every memo (specs, and anything that rewrites BUILD_INFO in place).
      def reset!
        @current = @build_info = @short_sha = @git_branch = @build_date = @version_parts = @warned = nil
      end

      private

      def build_info_version
        v = build_info["version"].to_s
        v.match?(SEMVER) ? v : nil
      end

      def git_version
        version_from_describe(git_output(DESCRIBE_CMD), git_branch_name)
      end

      def git_branch_name
        build_info["branch"].to_s.presence || git_output("rev-parse --abbrev-ref HEAD")
      end

      def fallback_version
        unless @warned
          @warned = true
          warn "Powernode::Version: no BUILD_INFO.json and no reachable release tag; reporting #{FALLBACK}"
        end
        short_sha ? "#{FALLBACK}+#{short_sha}" : FALLBACK
      end

      # The local-checkout fallback, run from the server tree. Returns nil (never raises) when git or a
      # repository is absent — the deployed tree has neither.
      def git_output(args)
        out = `git -C #{Shellwords.escape(File.expand_path("..", __dir__))} #{args} 2>/dev/null`.strip
        out.presence
      rescue StandardError
        nil
      end

      # The X.Y.Z half only; the prerelease rides after the first "-".
      def version_parts
        @version_parts ||= current.split(/[-+]/, 2).first.split(".")
      end
    end
  end
end

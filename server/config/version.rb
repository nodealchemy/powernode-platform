# frozen_string_literal: true

require "json"

module Powernode
  # The platform's version and build identity, as the RUNNING process can
  # truthfully state it.
  #
  # Two sources, in order:
  #
  # 1. BUILD_INFO.json — written by the module build
  #    (extensions/system/scripts/module-build/stage15.sh) next to VERSION,
  #    or wherever POWERNODE_BUILD_INFO points. It carries the commit the
  #    artifact was assembled from, the branch/tag the remote had for it, and
  #    a `release` verdict. This is the only identity a deployed node has: the
  #    staged tree ships WITHOUT .git, so the git fallback below is
  #    structurally "unknown" there.
  # 2. The local git checkout (development only).
  #
  # DISPLAY CONTRACT (mirrored by frontend/src/shared/services/admin/versionApi.ts):
  #   release build         -> "X.Y.Z"      (exact X.Y.Z tag == VERSION, built from master's tip)
  #   any other known build -> "<7-char sha>"
  #   no identity at all    -> "X.Y.Z-dev"
  # `release` is re-derived here from tag == VERSION rather than trusted from
  # the file, so a stale or hand-edited BUILD_INFO cannot promote itself.
  class Version
    VERSION_FILE    = File.expand_path("../VERSION", __dir__)
    BUILD_INFO_FILE = File.expand_path("../BUILD_INFO.json", __dir__)
    RELEASE_TAG     = /\A\d+\.\d+\.\d+\z/
    UNKNOWN         = "unknown"

    class << self
      def current
        @current ||= File.exist?(VERSION_FILE) ? File.read(VERSION_FILE).strip : "0.0.1-dev"
      end

      def major = version_parts[0].to_i
      def minor = version_parts[1].to_i

      def patch
        base_patch, _prerelease = version_parts[2].to_s.split("-", 2)
        base_patch.to_i
      end

      def prerelease
        version_parts[2]&.split("-", 2)&.last
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

      # True only for an artifact whose exact tag equals this VERSION and
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
        @git_branch ||= build_info["branch"].to_s.presence ||
                        git_output("rev-parse --abbrev-ref HEAD") ||
                        UNKNOWN
      end

      # What the UI shows. See the DISPLAY CONTRACT above.
      def display_version
        return current if release?
        return short_sha if short_sha

        current.end_with?("-dev") ? current : "#{current}-dev"
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
        @current = @build_info = @short_sha = @git_branch = @build_date = @version_parts = nil
      end

      private

      # The local-checkout fallback. Returns nil (never raises) when git or a
      # repository is absent — the deployed tree has neither.
      def git_output(args)
        out = `git #{args} 2>/dev/null`.strip
        out.presence
      rescue StandardError
        nil
      end

      def version_parts
        @version_parts ||= current.split(".")
      end
    end
  end
end

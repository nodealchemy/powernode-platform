# frozen_string_literal: true

require 'json'
require 'shellwords'

class PowernodeWorker
  # The worker's version, resolved exactly like Powernode::Version on the
  # server (server/config/version.rb) -- the worker cannot require server code,
  # so this is the small shared reader. Nothing is hand-maintained; versions
  # come from release tags:
  #
  #   1. BUILD_INFO.json (worker/BUILD_INFO.json or POWERNODE_BUILD_INFO),
  #      written at build time (module build / Docker build);
  #   2. `git describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'` (dev only);
  #   3. "0.0.0-dev.0".
  #
  # Format: exact tag -> X.Y.Z; release/X.Y.Z or hotfix/X.Y.Z -> X.Y.Z-rc.N+sha;
  # otherwise latest tag with minor+1 -> X.(Y+1).0-dev.N+sha.
  module BuildVersion
    BUILD_INFO_FILE = File.expand_path('../BUILD_INFO.json', __dir__)
    SEMVER = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
    DESCRIBE = /\A(\d+)\.(\d+)\.(\d+)-(\d+)-g([0-9a-f]+)\z/
    RELEASE_BRANCH = %r{\A(?:release|hotfix)/(\d+\.\d+\.\d+)\z}
    DESCRIBE_CMD = "describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'"
    FALLBACK = '0.0.0-dev.0'

    class << self
      def current
        @current ||= resolve
      end

      def resolve(build_info_path: ENV.fetch('POWERNODE_BUILD_INFO', BUILD_INFO_FILE))
        from_build_info(build_info_path) ||
          version_from_describe(git_output(DESCRIBE_CMD), git_output('rev-parse --abbrev-ref HEAD')) ||
          fallback
      end

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

      private

      def from_build_info(path)
        return nil unless File.exist?(path)

        version = JSON.parse(File.read(path))['version'].to_s
        version.match?(SEMVER) ? version : nil
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def fallback
        warn "PowernodeWorker::BuildVersion: no BUILD_INFO.json and no reachable release tag; reporting #{FALLBACK}"
        FALLBACK
      end

      def git_output(args)
        out = `git -C #{Shellwords.escape(File.expand_path('..', __dir__))} #{args} 2>/dev/null`.strip
        out.empty? ? nil : out
      rescue StandardError
        nil
      end
    end
  end
end

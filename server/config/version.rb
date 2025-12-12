# frozen_string_literal: true

module Powernode
  class Version
    VERSION_FILE = File.expand_path("../../VERSION", __dir__)

    def self.current
      @current ||= File.exist?(VERSION_FILE) ? File.read(VERSION_FILE).strip : "0.0.1-dev"
    end

    def self.major
      version_parts[0].to_i
    end

    def self.minor
      version_parts[1].to_i
    end

    def self.patch
      base_patch, prerelease = version_parts[2].split("-", 2)
      base_patch.to_i
    end

    def self.prerelease
      version_parts[2]&.split("-", 2)&.last
    end

    def self.semantic_version
      {
        version: current,
        major: major,
        minor: minor,
        patch: patch,
        prerelease: prerelease,
        build_date: build_date,
        git_commit: git_commit
      }
    end

    def self.build_date
      @build_date ||= Time.current.iso8601
    end

    def self.git_commit
      @git_commit ||= begin
        `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown"
      rescue StandardError
        "unknown"
      end
    end

    def self.git_branch
      @git_branch ||= begin
        `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip.presence || "unknown"
      rescue StandardError
        "unknown"
      end
    end

    def self.full_version_info
      {
        **semantic_version,
        git_branch: git_branch,
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        environment: Rails.env
      }
    end

    private

    def self.version_parts
      @version_parts ||= current.split(".")
    end
  end
end

# frozen_string_literal: true

module Shared
  # Persistent enable/disable state for extensions, readable from Rails, the
  # worker, and the Vite build. The state is stored at the project root in
  # `config/extensions_state.json` so all three loaders can read it without
  # database access at boot time.
  #
  # File format:
  #   { "disabled": ["example-extension", "supply-chain"] }
  #
  # Missing or malformed file => empty disabled list (extension stays enabled).
  class ExtensionStateStore
    DEFAULT_STATE = { "disabled" => [] }.freeze

    class << self
      # Absolute path to the state file at the project root.
      def path
        Rails.root.join("..", "config", "extensions_state.json").expand_path
      end

      # Read the current state. Returns DEFAULT_STATE on any error.
      def read
        return DEFAULT_STATE.dup unless File.exist?(path)

        parsed = JSON.parse(File.read(path))
        parsed["disabled"] = Array(parsed["disabled"]).map(&:to_s)
        parsed
      rescue JSON::ParserError, IOError, SystemCallError => e
        Rails.logger.warn("[ExtensionStateStore] Failed to read #{path}: #{e.message}") if defined?(Rails)
        DEFAULT_STATE.dup
      end

      def disabled?(slug)
        read.fetch("disabled", []).include?(slug.to_s)
      end

      # Atomically update the disabled list for a slug. Writes via temp file +
      # rename so concurrent readers never see a half-written file.
      def set_disabled!(slug, disabled:)
        slug = slug.to_s
        state = read
        list = Array(state["disabled"]).map(&:to_s)

        list = if disabled
                 (list + [slug]).uniq.sort
               else
                 list - [slug]
               end

        state["disabled"] = list
        write_atomic(state)
        state
      end

      private

      def write_atomic(state)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}"
        File.write(tmp, JSON.pretty_generate(state) + "\n")
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp.to_s)
      end
    end
  end
end

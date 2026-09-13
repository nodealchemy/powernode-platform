# frozen_string_literal: true

module Platform
  module Status
    # THE CORE CONTRIBUTOR SET, registered with ONE line from a boot hook
    # (config/initializers/platform_status_contributors.rb).
    #
    #   Platform::Status::Contributors.register_all!
    #
    # ── WHY A GLOB AND NOT A LIST ───────────────────────────────────────────
    # A hand-maintained list is a file two people edit to add two unrelated
    # kinds, which is a merge conflict on every increment that adds a
    # contributor. Globbing the directory means adding a kind is adding ONE
    # file that nobody else touches. The system extension's
    # `System::Status::Contributors.register_all!` (B1) is the same shape, for
    # the same reason.
    #
    # ── WHAT COUNTS AS A CONTRIBUTOR ────────────────────────────────────────
    # A class in this namespace that defines its own `KIND` constant. The
    # `false` on `const_defined?` is load-bearing: without it every subclass of
    # a contributor would inherit its parent's KIND and silently re-register
    # under the wrong key. Files that are helpers rather than contributors
    # (EnumConditions) define no KIND and are skipped.
    #
    # ── IDEMPOTENCE ─────────────────────────────────────────────────────────
    # `to_prepare` fires on every code reload, so this runs many times per
    # process. Registry.register is last-write-wins, so a second call REPLACES
    # each contributor with the freshly loaded class rather than duplicating or
    # raising — which is also what makes a reloaded contributor take effect in
    # development instead of serving stale code.
    module Contributors
      CONTRIBUTOR_GLOB = "app/services/platform/status/contributors/*.rb"

      class << self
        # @return [Array<String>] the kinds registered, sorted
        def register_all!
          contributor_classes.map do |klass|
            Registry.register(klass::KIND, klass.new)
            klass::KIND
          end.sort
        end

        # Every contributor class in this namespace, resolved through the
        # autoloader (never `require`) so reloading works and Zeitwerk stays
        # the single owner of the constant.
        def contributor_classes
          Dir[Rails.root.join(CONTRIBUTOR_GLOB)].sort.filter_map do |path|
            constant = "#{name}::#{File.basename(path, '.rb').camelize}".safe_constantize
            next unless constant.is_a?(Class)
            next unless constant.const_defined?(:KIND, false)

            constant
          end
        end
      end
    end
  end
end

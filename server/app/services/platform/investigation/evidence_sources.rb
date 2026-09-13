# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord
  # class in app/models. Zeitwerk resolves the namespace from that file
  # before loading this child, so `class` here is a reopen and `module`
  # would be a TypeError.
  class Investigation
    # WHERE EVIDENCE COMES FROM (design §5.3).
    #
    # Core assembles the evidence it owns — the component's conditions, its
    # dependency chain, its `Platform::StatusEvent`s, and matching learnings.
    # Two of the classes the design names are NOT core's to read:
    #
    #   - recent module changes and promotions, and
    #   - `RemediationOutcome` history,
    #
    # both of which live in the system extension. Core does not name it, does
    # not require it, and does not fall back to "the extension is probably
    # there". It opens a seam and takes whatever registers.
    #
    # PULL, NEVER PUSH. The extension reaches into core from its own engine's
    # `to_prepare` and offers a source; core never calls a named downstream.
    # Reverse that and core acquires a dependency on every evidence producer
    # that will ever exist.
    #
    #   Platform::Investigation::EvidenceSources.register(:module_changes) do |component_kind:, component_ref:, account:, window:|
    #     [ { summary: "...", occurred_at: ..., ref: ... } ]
    #   end
    #
    # A source returns an ARRAY of evidence items; anything else is coerced to
    # one. Each item should carry at least `summary` and `occurred_at`.
    #
    # ── A SOURCE THAT RAISES IS EVIDENCE THAT IS MISSING, NOT AN ABORT ──────
    # It is logged, recorded under `errors` in the assembled evidence, and the
    # other sources still run. That matters more here than in most seams: the
    # confidence rule discounts by the number of INDEPENDENT evidence classes,
    # so a class that silently vanished would quietly RAISE confidence in
    # whatever survived. Recording the failure keeps the gap visible.
    module EvidenceSources
      extend ::Powernode::HandlerRegistry

      class << self
        # Collects from every registered source.
        #
        # @return [Hash] `{ collected: {name => [items]}, errors: {name => msg} }`
        def collect(component_kind:, component_ref:, account:, window:)
          collected = {}
          errors = {}

          handlers.dup.each do |name, handler|
            items = handler.call(component_kind: component_kind, component_ref: component_ref,
                                 account: account, window: window)
            collected[name.to_s] = Array(items)
          rescue StandardError => e
            errors[name.to_s] = "#{e.class}: #{e.message}"
            Rails.logger.error("[Platform::Investigation] evidence source #{name} failed: #{e.class}: #{e.message}")
          end

          { collected: collected, errors: errors }
        end

        private

        def handler_noun
          "investigation evidence source"
        end
      end
    end
  end
end

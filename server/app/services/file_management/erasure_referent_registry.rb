# frozen_string_literal: true

module FileManagement
  # Core-side seam for the tables that reference file_objects through a
  # NO ACTION foreign key with no inverse association (IMP-d97f6e3bbc2b).
  # Core owns the registry and the handler contract and never names an
  # extension; whoever owns a referencing table registers a handler in its
  # boot initializer (the Devops::ContainerLifecycleRegistry inversion-of-
  # control pattern). With nothing registered (core mode) nothing holds and
  # nothing is released — and a referent nobody registered is still safe,
  # because FileManagement::Erasure catches the FK violation inside the
  # per-file transaction and reports the file as held.
  #
  # Handler contract: any callable responding to #call(action, payload).
  #
  #   call(:holds, file_object_ids)  -> { file_object_id => reason }
  #       Asked per file, read-only, inside that file's erasure transaction
  #       after its row lock and before any destruction (so a pointer set
  #       after the batch was selected is still seen). The handler names
  #       every id it refuses to let go of, with a reason string the erasure
  #       reports verbatim (an empty reason is replaced by
  #       "held_by_<handler name>"). Return {} to hold nothing. The ids
  #       argument stays an array so a handler can answer for many at once.
  #
  #   call(:release, file_object)    -> ignored
  #       Called INSIDE that file's erasure transaction, immediately before
  #       the destroy. The handler drops its own references to the file
  #       (e.g. nullifies a column). A raise here rolls that one file's
  #       erasure back and reports it as failed.
  #
  # A handler picks ONE posture per table: release (its reference is a
  # convenience pointer the row can live without) or hold (its reference
  # binds a platform artifact that must not vanish underneath it). Core's
  # own chat-attachment referent releases (config/initializers/
  # file_erasure_referents.rb); an extension's boot-image referents hold.
  #
  # Unlike the lifecycle registry, handler errors are NOT swallowed: an
  # erasure that cannot establish what holds a file must not destroy it
  # (that file is reported as failed), and a release that failed must roll
  # the destroy back. The registered names travel with every result
  # (Result#referents_consulted) so an audit row can tell "no handler" from
  # "no holds". Example (in an
  # extension's boot initializer — core never references the extension):
  #
  #   FileManagement::ErasureReferentRegistry.register(:boot_images) do |action, payload|
  #     MyExt::BootImageReferents.call(action, payload)
  #   end
  #
  # The register / unregister / registered? / names / handlers / reset!
  # surface is the shared ::Powernode::HandlerRegistry shape; @handlers
  # memoizes on this module, so this registry's state is its own.
  module ErasureReferentRegistry
    extend ::Powernode::HandlerRegistry

    ACTIONS = %i[holds release].freeze

    class << self
      # Every id at least one handler refuses to release, with the first
      # handler's reason. Handlers are asked in registration order.
      def holds(file_object_ids)
        ids = Array(file_object_ids)
        return {} if ids.empty?

        handlers.each_with_object({}) do |(name, handler), held|
          (handler.call(:holds, ids) || {}).each do |id, reason|
            held[id] ||= reason.presence || "held_by_#{name}"
          end
        end
      end

      # Lets every handler drop its references to one file. Runs inside the
      # caller's transaction; a raise propagates.
      def release(file_object)
        handlers.each_value { |handler| handler.call(:release, file_object) }
        nil
      end

      private

      def handler_noun
        "erasure referent handler"
      end
    end
  end
end

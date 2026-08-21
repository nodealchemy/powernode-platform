# frozen_string_literal: true

module Powernode
  # The shared Symbol-keyed handler-registry shape (IMP-ab3fc7bd9499).
  #
  # Several core seams are the same inversion-of-control registry: core owns the
  # registry and the handler contract and never names an extension; extensions
  # (or the worker) inject callables at boot; with nothing registered, core mode
  # behaves as if the seam were absent. This module is that shape, extracted once
  # so the copies cannot drift apart.
  #
  # `extend` it from the registry module — the methods land on the registry's
  # singleton, and `@handlers` memoizes on the EXTENDING module, so every
  # registry keeps a private store and one registry's `reset!` never touches
  # another's:
  #
  #   module MyRegistry
  #     extend ::Powernode::HandlerRegistry
  #
  #     class << self
  #       private
  #
  #       # The noun used in the ArgumentError raised by .register.
  #       def handler_noun
  #         "my handler"
  #       end
  #     end
  #   end
  #
  # Extenders keep their own constant name, their own error wording, and are
  # free to add methods of their own (e.g. a fan-out `notify`). The noun hook is
  # private, so a registry's PUBLIC surface is exactly register / unregister /
  # registered? / names / handlers / reset! plus whatever it declares itself.
  module HandlerRegistry
    # Register (or replace) a handler by name. Accepts a callable argument or a
    # block. Returns the symbolized name.
    def register(name, callable = nil, &block)
      handler = callable || block
      unless handler.respond_to?(:call)
        raise ArgumentError, "#{handler_noun} for #{name.inspect} must respond to #call"
      end

      handlers[name.to_sym] = handler
      name.to_sym
    end

    def unregister(name)
      handlers.delete(name.to_sym)
    end

    def registered?(name)
      handlers.key?(name.to_sym)
    end

    def names
      handlers.keys
    end

    # The live name => callable map. Returned by reference; callers iterate it
    # read-only.
    def handlers
      @handlers ||= {}
    end

    # Clears all registered handlers (test isolation / re-boot).
    def reset!
      @handlers = {}
    end

    private

    # Overridden by each extender to keep its own ArgumentError wording, which
    # is part of that registry's observable contract.
    def handler_noun
      "handler"
    end
  end
end

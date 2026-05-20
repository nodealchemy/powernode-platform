# frozen_string_literal: true

# Redact ActiveRecord::Encryption internals from `inspect` output.
#
# Why this exists
# ---------------
# Ruby's default `Object#inspect` lists every instance variable. When an
# exception is raised on one of these objects the runtime calls `inspect`
# on the receiver and embeds the result in the exception message — that's
# how `NoMethodError#message` gets its "for #<...>" tail. Without this
# patch, exception messages from anywhere in the encryption stack —
# including third-party gems, debuggers, backtrace tooling, log line
# interpolation — can dump:
#
#   - Config#@primary_key                       (32-char hex)
#   - Config#@deterministic_key                 (32-char hex)
#   - Config#@key_derivation_salt               (32-char hex)
#   - Context (via @key_generator.@key_derivation_salt + @key_provider keys)
#   - Key#@secret                               (binary derived key bytes)
#   - KeyProvider / DerivedSecretKeyProvider#@keys
#   - Scheme#@context_properties (hash containing all of the above)
#   - KeyGenerator#@key_derivation_salt
#
# This file replaces each class's `inspect` with a metadata-only form so
# the secret material never makes it into a string regardless of who
# constructs the message. The objects themselves still work normally —
# only their textual representation is sanitized.
#
# Before: an attacker only had to provoke any NoMethodError on a
# Context-receiving call. After: they would need direct memory access to
# the Ruby process; serialized form is mute.
#
# Loaded eagerly from `config/initializers/encryption.rb` so the patch is
# in place before any encryption code can run.

require "active_record/encryption"

module Powernode
  module Security
    # Single source of truth for the redacted-inspect format. Returns a
    # string that conveys class identity + structural metadata but no
    # secret bytes.
    def self.redacted_inspect(receiver, fields = {})
      meta = fields.compact.map { |k, v| "#{k}=#{v}" }.join(" ")
      meta = " #{meta}" unless meta.empty?
      "#<#{receiver.class.name}#{meta} [REDACTED]>"
    end

    # Mixed into AR encryption classes via prepend; subclass overrides
    # `redacted_inspect_fields` to expose non-secret metadata only.
    module RedactedInspect
      def inspect
        ::Powernode::Security.redacted_inspect(self, redacted_inspect_fields)
      rescue StandardError
        "#<#{self.class.name} [REDACTED — inspect raised]>"
      end

      def redacted_inspect_fields
        {}
      end
    end
  end
end

ActiveRecord::Encryption::Config.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    {
      primary_set:        !primary_key.nil?,
      deterministic_set:  !deterministic_key.nil?,
      salt_set:           !key_derivation_salt.nil?,
      previous_schemes:   Array(previous_schemes).size
    }
  rescue StandardError
    {}
  end
})

ActiveRecord::Encryption::Context.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    {
      key_provider_class:  key_provider&.class&.name,
      key_generator_class: key_generator&.class&.name,
      cipher_class:        cipher&.class&.name,
      encryptor_class:     encryptor&.class&.name,
      frozen_encryption:   !!frozen_encryption
    }
  rescue StandardError
    {}
  end
})

ActiveRecord::Encryption::Key.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    { secret_bytesize: secret.respond_to?(:bytesize) ? secret.bytesize : nil }
  rescue StandardError
    {}
  end
})

ActiveRecord::Encryption::KeyGenerator.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    { hash_digest_class: hash_digest_class&.name }
  rescue StandardError
    {}
  end
})

ActiveRecord::Encryption::Scheme.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    {
      key_provider_class: (@key_provider_param&.class&.name rescue nil),
      previous_schemes:   (Array(@previous_schemes).size rescue 0)
    }
  rescue StandardError
    {}
  end
})

ActiveRecord::Encryption::KeyProvider.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    { key_count: (Array(@keys).size rescue 0) }
  rescue StandardError
    {}
  end
})

# DerivedSecretKeyProvider inherits from KeyProvider so it picks up the
# prepended inspect automatically, but include it directly too in case
# Rails ever reverses the inheritance.
ActiveRecord::Encryption::DerivedSecretKeyProvider.prepend(Module.new {
  include ::Powernode::Security::RedactedInspect
  def redacted_inspect_fields
    { key_count: (Array(@keys).size rescue 0) }
  rescue StandardError
    {}
  end
})

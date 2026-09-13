# frozen_string_literal: true

module Ai
  # THE secret-KEY scrubber for free-form jsonb that a read surface serializes.
  #
  # Extracted verbatim from Ai::DataSources::ConfigPortabilityService, which had
  # been the only holder of it. It is a seam, not a copy: the portability
  # manifest and the MCP provider read surface answer the same question — "this
  # column is operator-editable and untyped, what in it must never ride out" —
  # and two answers to that question would drift apart the first time a key name
  # was added to one of them.
  #
  # DROPS the entry; it does not mask it. That is the deliberate difference from
  # Ai::SensitiveParams, which replaces the VALUE with "[FILTERED]" and keeps the
  # key. Both are correct for their surface:
  #
  #   - SensitiveParams masks, because an approval card is read by an operator
  #     who needs to see that a token was present in order to judge the request.
  #   - This drops, because an export manifest and an agent-facing read have no
  #     such reader. Leaving "api_key": "[FILTERED]" in a provider payload states
  #     that the provider carries an inline api_key — an inventory of where the
  #     secrets are, handed to whoever can call the verb.
  #
  # Do not add a third. If a surface needs masking, call SensitiveParams; if it
  # needs dropping, call this.
  module SecretKeyScrubber
    # ── DENYLIST: substrings that mark a key as secret-bearing ───────────────
    # Applied to every key, nested ones included. NOTE that a path-valued key
    # like token_file survives here (it contains none of these substrings) and
    # is dropped only if an exact-name rule catches it — see SECRET_KEY_EXACT.
    SECRET_KEY_SUBSTRINGS = %w[
      secret password passwd credential private mnemonic seed_phrase
      access_key secret_key client_secret api_secret web_identity_token
    ].freeze

    # Exact key names that are ALWAYS secret even though their substring is not
    # caught above (e.g. a bare "token" / "key" / "apikey" / "api_key").
    SECRET_KEY_EXACT = %w[
      token key apikey api_key auth jwt bearer signature passphrase
    ].freeze

    module_function

    # Recursively scrub a value so no secret-keyed entry survives inside a
    # nested Hash/Array that rode in under an allowlisted parent key. Scalars
    # pass through untouched: a bare value carries no key to judge it by.
    def scrub_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), acc|
          next if secret_key?(k.to_s)

          acc[k.to_s] = scrub_value(v)
        end
      when Array
        value.map { |v| scrub_value(v) }
      else
        value
      end
    end

    # True when a key name looks secret-bearing. Checks the exact-name set
    # first (catches a bare "token"/"key"), then the substring denylist. Used as
    # defense-in-depth ON TOP OF whatever allowlist the caller applies.
    def secret_key?(key)
      k = key.to_s.downcase
      return true if SECRET_KEY_EXACT.include?(k)

      SECRET_KEY_SUBSTRINGS.any? { |needle| k.include?(needle) }
    end
  end
end

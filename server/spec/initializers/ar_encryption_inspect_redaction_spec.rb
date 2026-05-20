# frozen_string_literal: true

require "rails_helper"

# Verifies that no AR::Encryption class leaks key material through
# `inspect` or via exception messages that include inspect-of-receiver.
# A regression in this file means a fix to one of the patched classes
# (Config, Context, Key, KeyGenerator, Scheme, KeyProvider,
# DerivedSecretKeyProvider) silently un-redacted — fix it before merging.
RSpec.describe "ActiveRecord::Encryption inspect redaction" do
  # A 32-char hex marker we can grep for in inspect/error output. If any
  # of these characters appears in the inspect string, the redaction is
  # broken — the secret_marker is built from a constant we control so we
  # don't depend on whatever's in the real config.
  let(:secret_marker) { "a" * 32 }

  describe "Config#inspect" do
    it "does NOT include primary_key, deterministic_key, or key_derivation_salt values" do
      cfg = ActiveRecord::Encryption::Config.new
      cfg.primary_key         = secret_marker
      cfg.deterministic_key   = secret_marker
      cfg.key_derivation_salt = secret_marker
      out = cfg.inspect
      expect(out).not_to include(secret_marker)
      expect(out).to include("[REDACTED]")
      # Metadata should still be present.
      expect(out).to include("primary_set=true")
      expect(out).to include("deterministic_set=true")
      expect(out).to include("salt_set=true")
    end
  end

  describe "Key#inspect" do
    it "does NOT include @secret bytes" do
      key = ActiveRecord::Encryption::Key.new(secret_marker)
      out = key.inspect
      expect(out).not_to include(secret_marker)
      expect(out).to include("[REDACTED]")
      expect(out).to include("secret_bytesize=32")
    end
  end

  describe "KeyGenerator#inspect" do
    it "does NOT include @key_derivation_salt" do
      gen = ActiveRecord::Encryption::KeyGenerator.new(hash_digest_class: OpenSSL::Digest::SHA256)
      gen.instance_variable_set(:@key_derivation_salt, secret_marker)
      out = gen.inspect
      expect(out).not_to include(secret_marker)
      expect(out).to include("[REDACTED]")
    end
  end

  describe "KeyProvider / DerivedSecretKeyProvider #inspect" do
    it "does NOT include @keys (the per-key derived secrets)" do
      key = ActiveRecord::Encryption::Key.new(secret_marker)
      provider = ActiveRecord::Encryption::KeyProvider.new([ key ])
      out = provider.inspect
      expect(out).not_to include(secret_marker)
      expect(out).to include("[REDACTED]")
      expect(out).to include("key_count=1")
    end
  end

  describe "exception receiver inspect" do
    # The key threat: NoMethodError#message embeds inspect-of-receiver.
    # If a config object is the receiver of an undefined method, the
    # exception message must not contain key material.
    it "NoMethodError on a Config with key set does NOT leak the key" do
      cfg = ActiveRecord::Encryption::Config.new
      cfg.primary_key = secret_marker
      begin
        cfg.this_method_does_not_exist!
      rescue NoMethodError => e
        expect(e.message).not_to include(secret_marker)
      end
    end

    it "NoMethodError on a Key does NOT leak the secret" do
      key = ActiveRecord::Encryption::Key.new(secret_marker)
      begin
        key.this_method_does_not_exist!
      rescue NoMethodError => e
        expect(e.message).not_to include(secret_marker)
      end
    end
  end
end

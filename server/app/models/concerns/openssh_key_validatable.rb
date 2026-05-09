# frozen_string_literal: true

# Shared OpenSSH `authorized_keys` line predicate. Used by `User` and
# `System::Node` so both surfaces validate operator-supplied pubkeys against
# the same regex — and both filter to OpenSSH format on read so PEM-PKIX
# blobs / arbitrary garbage never leak into a real `authorized_keys` file
# (sshd would silently drop those lines anyway).
module OpensshKeyValidatable
  extend ActiveSupport::Concern

  # OpenSSH authorized_keys lines start with an algorithm identifier
  # followed by whitespace and the base64 key blob, optionally followed
  # by a comment. The `ssh-` algorithms cover legacy + modern; the
  # `ecdsa-sha2-*` and `sk-` (FIDO2 hardware-backed) cover the rest of
  # the OpenSSH supported set.
  OPENSSH_AUTHORIZED_KEY_PREFIX = /\A(ssh-(rsa|ed25519|dss)|ecdsa-sha2-\S+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)\s+\S+/.freeze

  class_methods do
    def openssh_authorized_key?(line)
      line.to_s.match?(OPENSSH_AUTHORIZED_KEY_PREFIX)
    end
  end

  def openssh_authorized_key?(line)
    self.class.openssh_authorized_key?(line)
  end
end

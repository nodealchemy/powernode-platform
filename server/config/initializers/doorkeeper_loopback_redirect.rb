# frozen_string_literal: true

# RFC 8252 §7.3 — loopback redirect matching for the `localhost` hostname.
#
# Doorkeeper's URIChecker already strips the port when comparing two loopback
# redirect URIs, so an OS-assigned ephemeral callback port matches the registered
# one:
#
#     if loopback_uri?(url) && loopback_uri?(client_url)
#       url.port = nil; client_url.port = nil
#     end
#
# …but its loopback test is `IPAddr.new(uri.host).loopback?`, which only classifies
# the IP literals 127.0.0.1 / ::1 and RAISES (→ rescued to false) for the hostname
# "localhost". Native OAuth clients — including Claude Code's MCP daemon — register
# `http://localhost:<ephemeral-port>/callback` and pick a fresh port on each launch.
# Without recognising `localhost` as loopback, the port is never stripped, the
# exact-match fails on every new port, and the client is forced to register a brand
# new OAuth client (Dynamic Client Registration) and re-authenticate through the
# browser on every launch / server reboot.
#
# This widens loopback detection to also accept the `localhost` hostname — the same
# host set our own Dynamic Client Registration endpoint already allows
# (Api::V1::Oauth::RegistrationsController::LOOPBACK_HOSTS). IP-literal behaviour is
# unchanged (still delegated to IPAddr). Defined in an initializer so it runs after
# the doorkeeper gem has loaded the original URIChecker, overriding it.
module Doorkeeper
  module OAuth
    module Helpers
      module URIChecker
        # Loopback hostnames that are not IP literals, so IPAddr cannot classify them.
        LOOPBACK_HOSTNAMES = %w[localhost].freeze

        def self.loopback_uri?(uri)
          return true if LOOPBACK_HOSTNAMES.include?(uri.host)

          IPAddr.new(uri.host).loopback?
        rescue IPAddr::Error, IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end

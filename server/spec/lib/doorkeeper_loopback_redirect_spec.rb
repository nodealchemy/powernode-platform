# frozen_string_literal: true

require "rails_helper"

# Reproduction + guard for the MCP OAuth "re-auth on every launch/reboot" bug.
#
# Claude Code (and other RFC 8252 native clients) register a loopback redirect
# `http://localhost:<ephemeral-port>/callback` and use a DIFFERENT OS-assigned
# port on each launch. Doorkeeper's URIChecker strips the port when comparing two
# loopback redirect URIs (RFC 8252 §7.3) — but only when its loopback test passes,
# and that test (`IPAddr.new(host).loopback?`) raises for the `localhost` hostname,
# so the port was never stripped for `localhost`. The exact-match then failed on
# every new port, forcing the client to register a brand-new OAuth client and
# re-authenticate. config/initializers/doorkeeper_loopback_redirect.rb widens
# loopback detection to include the `localhost` hostname.
RSpec.describe Doorkeeper::OAuth::Helpers::URIChecker do
  describe ".loopback_uri?" do
    it "treats the localhost hostname as loopback" do
      expect(described_class.loopback_uri?(URI.parse("http://localhost:1234/cb"))).to be true
    end

    it "still treats the 127.0.0.1 IP literal as loopback" do
      expect(described_class.loopback_uri?(URI.parse("http://127.0.0.1:1234/cb"))).to be true
    end

    it "does not treat a non-loopback host as loopback" do
      expect(described_class.loopback_uri?(URI.parse("http://example.com:1234/cb"))).to be false
    end
  end

  describe ".valid_for_authorization? (RFC 8252 §7.3 ephemeral loopback ports)" do
    it "accepts a localhost redirect on a DIFFERENT port than registered" do
      expect(
        described_class.valid_for_authorization?(
          "http://localhost:2222/callback", "http://localhost:1111/callback"
        )
      ).to be true
    end

    it "accepts a 127.0.0.1 redirect on a different port (already worked)" do
      expect(
        described_class.valid_for_authorization?(
          "http://127.0.0.1:2222/callback", "http://127.0.0.1:1111/callback"
        )
      ).to be true
    end

    it "still rejects a localhost redirect whose PATH differs" do
      expect(
        described_class.valid_for_authorization?(
          "http://localhost:2222/evil", "http://localhost:1111/callback"
        )
      ).to be false
    end

    it "still rejects a non-loopback host with a mismatched port" do
      expect(
        described_class.valid_for_authorization?(
          "http://example.com:2222/cb", "http://example.com:1111/cb"
        )
      ).to be false
    end
  end
end

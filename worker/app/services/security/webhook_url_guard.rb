# frozen_string_literal: true

require 'uri'
require 'ipaddr'
require 'resolv'

module Security
  # SSRF guard for OUTBOUND, user-configured webhook deliveries.
  #
  # User/DB-supplied webhook URLs are attacker-controllable. Without validation a
  # webhook pointed at http://127.0.0.1, http://169.254.169.254/ (cloud instance
  # metadata), http://localhost, or any RFC1918 address lets the worker POST to
  # internal services on the worker's behalf — reaching internal admin endpoints,
  # exfiltrating instance-metadata credentials, or port-scanning via response
  # timing. This guard resolves the host to its IP(s) (defeating DNS-rebinding,
  # where a name resolves public at registration but private at delivery time)
  # and refuses loopback / link-local / private / unspecified / multicast /
  # reserved destinations.
  #
  # Scope: this guards ONLY the user-configured outbound webhook deliveries. It is
  # NOT applied to fixed, trusted-host callouts (the backend API client, Gitea /
  # registry, configured LLM/MCP integrations) whose targets are not attacker
  # controlled.
  #
  # Self-hosted deployments that legitimately need to deliver to an internal host
  # can opt specific hostnames in via the WEBHOOK_ALLOWED_INTERNAL_HOSTS env var
  # (comma-separated). The default posture is deny-internal.
  module WebhookUrlGuard
    class UnsafeUrlError < StandardError; end

    # A vetted delivery target: the parsed URI plus the single IP that was
    # actually resolved-and-checked. Callers MUST connect to +ip+ (pinning)
    # while keeping the URI's host as the Host header / TLS SNI, so a DNS
    # rebind between this check and connect time cannot redirect the socket to
    # an internal address (TOCTOU / DNS-rebinding closure).
    VettedTarget = Struct.new(:uri, :ip, keyword_init: true)

    ALLOWED_SCHEMES = %w[http https].freeze

    # Hostnames that, by definition, point at an internal/metadata target.
    BLOCKED_HOSTNAMES = %w[localhost metadata.google.internal].freeze

    # CIDR ranges that must never be reachable from a user-configured webhook.
    # Covers the IPv4/IPv6 loopback, link-local (incl. the 169.254.169.254 cloud
    # metadata IP), private (RFC1918 / unique-local), unspecified, CGNAT,
    # documentation, multicast and reserved space.
    INTERNAL_RANGES = [
      IPAddr.new('0.0.0.0/8'),          # "this" network / unspecified source
      IPAddr.new('10.0.0.0/8'),         # RFC1918 private
      IPAddr.new('100.64.0.0/10'),      # RFC6598 CGNAT
      IPAddr.new('127.0.0.0/8'),        # loopback
      IPAddr.new('169.254.0.0/16'),     # link-local (incl. 169.254.169.254 metadata)
      IPAddr.new('172.16.0.0/12'),      # RFC1918 private
      IPAddr.new('192.0.0.0/24'),       # IETF protocol assignments
      IPAddr.new('192.0.2.0/24'),       # TEST-NET-1 (documentation)
      IPAddr.new('192.168.0.0/16'),     # RFC1918 private
      IPAddr.new('198.18.0.0/15'),      # benchmarking
      IPAddr.new('198.51.100.0/24'),    # TEST-NET-2 (documentation)
      IPAddr.new('203.0.113.0/24'),     # TEST-NET-3 (documentation)
      IPAddr.new('224.0.0.0/4'),        # multicast
      IPAddr.new('240.0.0.0/4'),        # reserved (incl. 255.255.255.255 broadcast)
      IPAddr.new('::/128'),             # IPv6 unspecified
      IPAddr.new('::1/128'),            # IPv6 loopback
      IPAddr.new('64:ff9b::/96'),       # NAT64
      IPAddr.new('fc00::/7'),           # IPv6 unique-local (private)
      IPAddr.new('fe80::/10'),          # IPv6 link-local
      IPAddr.new('ff00::/8')            # IPv6 multicast
    ].freeze

    module_function

    # Returns true when +url+ is safe to deliver to, false otherwise.
    def safe?(url)
      validate!(url)
      true
    rescue UnsafeUrlError
      false
    end

    # Validates +url+, returning the parsed URI when safe. Raises UnsafeUrlError
    # (a controlled, rescuable error) when the destination is internal/disallowed.
    def validate!(url)
      vet!(url).uri
    end

    # Validates +url+ and returns the VettedTarget the caller MUST pin to (the
    # parsed URI plus the exact IP that was checked). Raises UnsafeUrlError when
    # the destination is internal/disallowed. Prefer this over +safe?+ on the
    # outbound delivery path: pinning the connection to the returned IP is what
    # actually closes the DNS-rebind TOCTOU window that +safe?+ alone leaves open.
    def vetted_target!(url)
      vet!(url)
    end

    # Non-raising wrapper around +vetted_target!+. Returns the VettedTarget when
    # safe, or nil when the destination is internal/disallowed.
    def vetted_target(url)
      vetted_target!(url)
    rescue UnsafeUrlError
      nil
    end

    # --- internals -----------------------------------------------------------

    # Resolves and validates +url+ exactly once, returning a VettedTarget whose
    # +ip+ is the single resolved address the caller must connect to. This is the
    # shared core behind +validate!+, +safe?+ and +vetted_target!+ so the
    # classification logic never diverges.
    def vet!(url)
      uri = parse(url)

      scheme = uri.scheme&.downcase
      unless ALLOWED_SCHEMES.include?(scheme)
        raise UnsafeUrlError, "scheme not allowed: #{uri.scheme.inspect}"
      end

      host = uri.host
      raise UnsafeUrlError, 'missing host' if host.nil? || host.empty?

      normalized = normalize_host(host)
      opted_in = allowed_internal_hosts.include?(normalized)

      # Operator opt-in escape hatch for self-hosted internal delivery skips the
      # blocked-hostname and internal-range checks — but we still resolve so the
      # connection can be pinned to a concrete vetted IP.
      raise UnsafeUrlError, "blocked hostname: #{host}" if !opted_in && blocked_hostname?(normalized)

      addresses = resolve(normalized)

      if opted_in
        # Best-effort pin for the operator escape hatch: opted-in hosts are
        # explicitly trusted, and some resolve only via NSS/mDNS mechanisms that
        # Ruby's Resolv can't see. Keep the pre-pinning behavior (nil ip → the
        # caller lets Net::HTTP resolve) rather than hard-blocking a trusted host
        # we merely failed to pre-resolve here.
        return VettedTarget.new(uri: uri, ip: addresses.first&.to_s)
      end

      raise UnsafeUrlError, "unable to resolve host: #{host}" if addresses.empty?

      addresses.each do |addr|
        raise UnsafeUrlError, "resolves to internal address: #{addr}" if internal_ip?(addr)
      end

      VettedTarget.new(uri: uri, ip: addresses.first.to_s)
    end

    def parse(url)
      URI.parse(url.to_s)
    rescue URI::InvalidURIError => e
      raise UnsafeUrlError, "invalid URL: #{e.message}"
    end

    # Lowercase + strip the trailing FQDN dot and IPv6 brackets.
    def normalize_host(host)
      host.downcase.sub(/\.\z/, '').delete_prefix('[').delete_suffix(']')
    end

    def allowed_internal_hosts
      ENV.fetch('WEBHOOK_ALLOWED_INTERNAL_HOSTS', '')
         .split(',')
         .map { |h| normalize_host(h.strip) }
         .reject(&:empty?)
    end

    def blocked_hostname?(host)
      return true if BLOCKED_HOSTNAMES.include?(host)

      # *.localhost is reserved and always resolves to loopback (RFC6761).
      host.end_with?('.localhost')
    end

    # Resolve +host+ to IPAddr(s). IP literals are used directly; names are
    # resolved via DNS at delivery time (every A/AAAA record is checked so a
    # multi-record rebind can't slip a private address past us).
    def resolve(host)
      begin
        return [IPAddr.new(host)]
      rescue IPAddr::InvalidAddressError
        # not an IP literal — fall through to DNS resolution
      end

      Resolv.getaddresses(host).filter_map do |addr|
        IPAddr.new(addr)
      rescue IPAddr::InvalidAddressError
        nil
      end
    rescue Resolv::ResolvError, SocketError
      []
    end

    def internal_ip?(ip)
      # Evaluate IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1) as its native IPv4.
      ip = ip.native if ip.ipv4_mapped?

      return true if INTERNAL_RANGES.any? { |range| range.include?(ip) }

      ip.loopback? || ip.private? || ip.link_local?
    rescue StandardError
      # Fail closed: anything we cannot positively classify is treated as unsafe.
      true
    end
  end
end

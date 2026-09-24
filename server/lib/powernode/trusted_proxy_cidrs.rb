# frozen_string_literal: true

require "ipaddr"

module Powernode
  # Parses the TRUSTED_PROXY_CIDRS env var into IPAddr instances for
  # config.action_dispatch.trusted_proxies (server/config/application.rb).
  #
  # Extracted out of application.rb's class body specifically so a spec can
  # exercise the parsing rules directly — application.rb itself runs once, at
  # boot, before RSpec's world exists, so nothing there can be re-invoked from
  # a spec with a different env value.
  #
  # Deliberately forgiving on read: a blank entry (trailing/double comma) is
  # dropped silently, and an unparseable entry is logged and dropped rather
  # than raising. A typo in this env var must never crash boot — the worst
  # case is that one hop stays untrusted, which fails closed (identical to
  # leaving the var unset for that hop).
  module TrustedProxyCidrs
    module_function

    # Returns an Array of IPAddr, or [] if raw is blank or every entry was
    # invalid. `logger` defaults to Kernel#warn (STDERR) rather than
    # Rails.logger: this runs during Application class body evaluation,
    # before the app's own logger is guaranteed configured.
    def parse(raw, logger: ->(msg) { warn(msg) })
      return [] if raw.blank?

      raw.split(",").filter_map do |entry|
        entry = entry.strip
        next if entry.blank?

        begin
          IPAddr.new(entry)
        rescue IPAddr::Error => e
          logger.call("[TRUSTED_PROXY_CIDRS] skipping invalid entry #{entry.inspect}: #{e.message}")
          nil
        end
      end
    end
  end
end

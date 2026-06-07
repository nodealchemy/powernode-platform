# frozen_string_literal: true

require "uri"

module Ai
  module DataSources
    # robots.txt politeness for governed outbound data-source fetches (Phase 5).
    #
    # Only consulted when data_source.respect_robots is true (off by default, so
    # existing sources incur zero overhead). For a given absolute URL the service:
    #
    #   1. resolves the URL's host and fetches its /robots.txt through the same
    #      SSRF-guarded Faraday connection the QueryService uses
    #      (HttpConnectionFactory.build) — robots fetches obey the exact same
    #      egress pinning / size cap / timeout policy as a real fetch;
    #   2. parses the records for OUR User-Agent (the contactable UA the factory
    #      advertises, longest-matching User-Agent group, then the "*" group) into
    #      ordered Allow/Disallow rules plus a Crawl-delay;
    #   3. caches the PARSED rules in Redis (DB 0, shared client) under a per-host
    #      key with a TTL so repeated polls don't refetch robots.txt every tick.
    #
    # DEFAULT ALLOW: a missing robots.txt (404), an empty body, a fetch failure
    # (timeout / transport / SSRF rejection / oversized), or a Redis fault all
    # resolve to "allowed" — robots is advisory politeness, never a hard gate that
    # could wedge a source on an unrelated network blip. A robots.txt that loads
    # and explicitly Disallows the path is the ONLY thing that returns false.
    #
    # Path matching follows the de-facto robots spec used by Google/Bing:
    #   - the longest matching rule (Allow or Disallow) wins;
    #   - on an exact length tie, Allow wins over Disallow;
    #   - "*" wildcards and a trailing "$" anchor are honored;
    #   - an empty Disallow value ("Disallow:") means "allow everything".
    class RobotsService
      # Redis namespace for cached parsed robots rules (Redis DB 0, shared client).
      REDIS_NAMESPACE = "data_source_robots"

      # How long parsed robots rules live in Redis. A day is the conventional
      # robots cache horizon (Google recracls roughly daily); short enough that an
      # operator un-disallowing a path is honored within a day, long enough that a
      # realtime monitor doesn't refetch robots.txt on every tick.
      CACHE_TTL_SECONDS = 86_400

      # Cache horizon for a negative (fetch-failed / missing) result so a flaky
      # robots endpoint isn't hammered every tick while still re-probing sooner
      # than a successful parse would.
      NEGATIVE_CACHE_TTL_SECONDS = 900

      # Bound how much of robots.txt we parse. Real robots files are tiny; this is
      # a belt-and-suspenders cap on top of the connection's response-size guard.
      MAX_ROBOTS_BYTES = 512 * 1024

      def initialize(data_source, agent: nil)
        @data_source = data_source
        @agent = agent
      end

      # Is +url+ permitted by the host's robots.txt for our User-Agent?
      #
      # Returns true (DEFAULT ALLOW) on any failure to obtain or parse rules, and
      # whenever respect_robots is off. Returns false ONLY when a successfully
      # parsed robots.txt explicitly disallows the request path.
      def allowed?(url)
        return true unless respect_robots?

        uri = parse_uri(url)
        return true if uri.nil? || uri.host.blank?

        rules = rules_for(uri)
        return true if rules.nil? # fetch/parse failure => default allow

        path = request_path(uri)
        path_allowed?(rules, path)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] allowed? failed (default allow) for #{safe_slug}: #{e.message}")
        true
      end

      # Effective crawl-delay in whole seconds, or nil when none applies.
      #
      # Precedence: the robots.txt Crawl-delay for our User-Agent group (when a
      # robots.txt was fetched and carried one) takes priority; otherwise the
      # source's configured crawl_delay_seconds. Returns nil when neither is set
      # so the caller can fall back to its own default interval.
      def crawl_delay
        from_robots = robots_crawl_delay
        return from_robots if from_robots

        configured = data_source_crawl_delay_seconds
        configured&.positive? ? configured : nil
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] crawl_delay failed for #{safe_slug}: #{e.message}")
        nil
      end

      private

      attr_reader :data_source, :agent

      def respect_robots?
        data_source.respond_to?(:respect_robots) && data_source.respect_robots == true
      rescue StandardError
        false
      end

      def data_source_crawl_delay_seconds
        return nil unless data_source.respond_to?(:crawl_delay_seconds)

        value = data_source.crawl_delay_seconds
        Integer(value, exception: false)
      rescue StandardError
        nil
      end

      # The Crawl-delay parsed from the cached robots rules for our UA group, or
      # nil. Reads the same cached/fetched rules allowed? uses (keyed by host), so
      # it does not trigger a second fetch when a base URL host is available.
      def robots_crawl_delay
        uri = parse_uri(data_source_base_url)
        return nil if uri.nil? || uri.host.blank?

        rules = rules_for(uri)
        return nil if rules.nil?

        delay = rules["crawl_delay"]
        delay&.positive? ? delay : nil
      rescue StandardError
        nil
      end

      def data_source_base_url
        data_source.respond_to?(:api_base_url) ? data_source.api_base_url : nil
      end

      # Fetch (or read cached) parsed robots rules for +uri+'s host. Returns a
      # parsed-rules Hash, or nil to signal "could not obtain rules => default
      # allow". A successfully-fetched-but-empty/missing robots.txt is cached as a
      # permissive ruleset (empty rules => allow everything) rather than nil so we
      # don't refetch a known-absent robots.txt every call.
      def rules_for(uri)
        cache_key = robots_cache_key(uri)

        cached = read_cached_rules(cache_key)
        return cached_value(cached) unless cached.nil?

        fetched = fetch_and_parse(uri)
        if fetched.nil?
          write_cached_rules(cache_key, negative_marker, NEGATIVE_CACHE_TTL_SECONDS)
          return nil
        end

        write_cached_rules(cache_key, fetched, CACHE_TTL_SECONDS)
        fetched
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] rules_for failed (default allow): #{e.message}")
        nil
      end

      # Sentinel persisted for a fetch-failed/missing robots.txt so a known-absent
      # file isn't refetched every call. read path maps it back to nil (=> default
      # allow) via cached_value.
      NEGATIVE_MARKER = { "__robots_unavailable" => true }.freeze

      # Translate a cached entry back into the rules_for contract: the negative
      # marker becomes nil (default allow), anything else is the parsed rules.
      def cached_value(cached)
        return nil if cached.is_a?(Hash) && cached["__robots_unavailable"] == true

        cached
      end

      def negative_marker
        NEGATIVE_MARKER
      end

      # GET <scheme>://<host>[:port]/robots.txt through the SSRF-guarded connection.
      # Returns parsed rules on a 2xx body, an empty (permissive) ruleset on a 404
      # / empty body, or nil on any fault (=> default allow).
      def fetch_and_parse(uri)
        robots_url = robots_url_for(uri)
        conn = Ai::DataSources::HttpConnectionFactory.build(data_source: data_source, agent: agent)
        response = conn.get(robots_url)

        status = response.respond_to?(:status) ? response.status.to_i : 0
        # 4xx (incl. 404 "no robots.txt") => crawl freely. 5xx / other => treat as
        # unavailable (nil) so we don't cache a server error as permanent allow.
        return empty_rules if status == 404 || (status >= 400 && status < 500)
        return nil unless status.between?(200, 299)

        body = response.body.to_s
        return empty_rules if body.strip.empty?

        parse_robots(body.byteslice(0, MAX_ROBOTS_BYTES).to_s)
      rescue Ai::DataSources::HttpConnectionFactory::SsrfError,
             Ai::DataSources::HttpConnectionFactory::ResponseTooLargeError => e
        Rails.logger.info("[DataSources::RobotsService] robots fetch blocked/oversized (default allow): #{e.class}")
        nil
      rescue Faraday::Error, Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.info("[DataSources::RobotsService] robots fetch failed (default allow): #{e.class}")
        nil
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] robots fetch error (default allow): #{e.message}")
        nil
      end

      # Parse robots.txt into the rules for OUR User-Agent. Groups records by
      # User-Agent; selects the longest User-Agent token that prefix-matches our
      # UA (case-insensitively), falling back to the "*" group. Returns:
      #   { "rules" => [{ "allow" => Bool, "pattern" => String }, ...],
      #     "crawl_delay" => Integer|nil }
      def parse_robots(body)
        groups = group_by_user_agent(body)
        selected = select_group(groups)
        selected || empty_rules
      end

      # Build { ua_token => { rules: [...], crawl_delay: Int|nil } } from the file.
      # A blank line does NOT reset the current group's agents — we accumulate
      # directives under whichever User-Agent line(s) most recently preceded them,
      # which matches how the major crawlers coalesce consecutive UA lines.
      def group_by_user_agent(body)
        groups = Hash.new { |h, k| h[k] = { rules: [], crawl_delay: nil } }
        current_agents = []
        expecting_rules = false

        body.each_line do |raw|
          line = strip_comment(raw).strip
          next if line.empty?

          field, value = split_directive(line)
          next if field.nil?

          case field
          when "user-agent"
            # A User-Agent line after rules starts a new group block.
            if expecting_rules
              current_agents = []
              expecting_rules = false
            end
            current_agents << value.downcase
          when "disallow"
            expecting_rules = true
            apply_to_agents(groups, current_agents) { |g| g[:rules] << { "allow" => false, "pattern" => value } }
          when "allow"
            expecting_rules = true
            apply_to_agents(groups, current_agents) { |g| g[:rules] << { "allow" => true, "pattern" => value } }
          when "crawl-delay"
            expecting_rules = true
            delay = parse_delay(value)
            apply_to_agents(groups, current_agents) { |g| g[:crawl_delay] = delay if delay }
          end
        end

        groups
      end

      def apply_to_agents(groups, agents)
        agents = ["*"] if agents.empty?
        agents.each { |ua| yield groups[ua] }
      end

      # Pick the most specific matching group for our UA: the longest User-Agent
      # token that is a case-insensitive prefix of our UA, else the "*" group, else
      # permissive empty rules.
      def select_group(groups)
        ua = our_user_agent.downcase
        specific = groups.keys
                         .reject { |token| token == "*" }
                         .select { |token| token.present? && ua.include?(token) }
                         .max_by(&:length)

        chosen = specific || (groups.key?("*") ? "*" : nil)
        return nil if chosen.nil?

        group = groups[chosen]
        { "rules" => group[:rules], "crawl_delay" => group[:crawl_delay] }
      end

      # Longest-match wins; Allow beats Disallow on a length tie. An empty pattern
      # ("Disallow:") matches nothing (i.e. allows everything). No matching rule =>
      # allowed.
      def path_allowed?(rules, path)
        list = rules.is_a?(Hash) ? Array(rules["rules"]) : []
        return true if list.empty?

        best = nil
        list.each do |rule|
          pattern = rule["pattern"].to_s
          next if pattern.empty? # empty Disallow => no restriction

          length = match_length(pattern, path)
          next if length.nil?

          if best.nil? ||
             length > best[:length] ||
             (length == best[:length] && rule["allow"] && !best[:allow])
            best = { length: length, allow: rule["allow"] == true }
          end
        end

        best.nil? ? true : best[:allow]
      end

      # Return the length of +pattern+ (its specificity, counting non-wildcard
      # characters as the spec dictates) when it matches +path+, else nil.
      # Supports "*" (any run) and a trailing "$" end-anchor.
      def match_length(pattern, path)
        regex = pattern_to_regex(pattern)
        return nil unless regex.match?(path)

        # Specificity = pattern length excluding the wildcard/anchor metacharacters,
        # so a longer literal prefix outranks a short wildcard rule.
        pattern.delete("*$").length
      end

      def pattern_to_regex(pattern)
        anchored_end = pattern.end_with?("$")
        core = anchored_end ? pattern[0..-2] : pattern

        escaped = core.split("*", -1).map { |seg| Regexp.escape(seg) }.join(".*")
        source = "\\A#{escaped}"
        source += "\\z" if anchored_end
        Regexp.new(source)
      end

      # The contactable User-Agent the connection factory advertises — robots
      # matching must use the SAME UA we send on real fetches.
      def our_user_agent
        Ai::DataSources::HttpConnectionFactory.user_agent(agent)
      rescue StandardError
        "Powernode"
      end

      def empty_rules
        { "rules" => [], "crawl_delay" => nil }
      end

      # ----------------------------------------------------------------------
      # parsing helpers
      # ----------------------------------------------------------------------

      def strip_comment(line)
        idx = line.index("#")
        idx ? line[0...idx] : line
      end

      def split_directive(line)
        key, _, value = line.partition(":")
        return [nil, nil] if value.nil?

        [key.strip.downcase, value.strip]
      end

      def parse_delay(value)
        # Crawl-delay may be fractional ("0.5"); round UP to whole seconds so we
        # never under-wait, and clamp to >= 1 when any positive delay is declared.
        num = Float(value, exception: false)
        return nil if num.nil? || num <= 0

        [num.ceil, 1].max
      end

      # ----------------------------------------------------------------------
      # URL helpers
      # ----------------------------------------------------------------------

      def parse_uri(url)
        return nil if url.blank?

        uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        uri
      rescue URI::InvalidURIError
        nil
      end

      def robots_url_for(uri)
        port = explicit_port(uri)
        host = port ? "#{uri.host}:#{port}" : uri.host
        "#{uri.scheme}://#{host}/robots.txt"
      end

      # Include the port only when it is non-default for the scheme.
      def explicit_port(uri)
        return nil if uri.port.nil?
        default = uri.scheme == "https" ? 443 : 80
        uri.port == default ? nil : uri.port
      end

      # robots rules are PER HOST (scheme + host + port), per the spec.
      def request_path(uri)
        path = uri.path.to_s
        path = "/" if path.empty?
        uri.query.present? ? "#{path}?#{uri.query}" : path
      end

      def robots_cache_key(uri)
        port = explicit_port(uri)
        authority = port ? "#{uri.host}:#{port}" : uri.host
        "#{REDIS_NAMESPACE}:#{uri.scheme}:#{authority}"
      end

      # ----------------------------------------------------------------------
      # Redis (parsed-rules cache) — fully isolated; a Redis fault degrades to a
      # live fetch (and ultimately default-allow), never an exception.
      # ----------------------------------------------------------------------

      def read_cached_rules(key)
        client = redis
        return nil unless client

        raw = client.get(key)
        return nil if raw.nil?

        JSON.parse(raw)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] robots cache read failed: #{e.message}")
        nil
      end

      def write_cached_rules(key, value, ttl)
        client = redis
        return unless client

        client.setex(key, ttl, value.to_json)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RobotsService] robots cache write failed: #{e.message}")
        nil
      end

      def redis
        Powernode::Redis.client
      rescue StandardError
        nil
      end

      def safe_slug
        data_source.respond_to?(:slug) ? data_source.slug : "unknown"
      rescue StandardError
        "unknown"
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module Ai
  module DataSources
    # Outbound pagination driver for the data-source fetch pipeline.
    #
    # The Paginator walks an upstream's pages and concatenates the decoded
    # canonical records into a single set, so the QueryService can keep returning
    # ONE FetchEnvelope regardless of how many physical requests were needed.
    #
    # It is deliberately I/O-free: it does NOT sign, dispatch, decode, or touch
    # quota itself. The QueryService owns all of that (credentials, signing,
    # SSRF-guarded dispatch, circuit breaker, decode) and injects two callbacks:
    #
    #   fetch_page.call(params)  => the FULL Faraday-style response for `params`
    #                               (the QueryService's existing build->sign->
    #                               dispatch path, run with page-augmented params)
    #   decode_page.call(resp)   => Array<Hash> canonical records for that response
    #   check_quota.call         => truthy (a quota descriptor) when the NEXT page
    #                               must be skipped; falsy/nil when allowed
    #
    # OFF BY DEFAULT: when endpoint.pagination is blank the Paginator is never
    # constructed by the QueryService (the single-request path is unchanged). When
    # constructed, #enabled? still guards a misconfigured/empty config so an
    # accidental wiring is a safe no-op rather than a behavior change.
    #
    # Supported strategies (endpoint.pagination["type"]):
    #
    #   "offset" — &<offset_param>=N&<limit_param>=L ; advance offset by limit
    #              (or by the page's record count when limit is unknown).
    #   "page"   — &<page_param>=N (&<limit_param>=L) ; advance page by 1 from
    #              start_page (default 1).
    #   "cursor" — &<cursor_param>=C where the next cursor is read from the decoded
    #              BODY at cursor_path (dotted/pointer path into the raw JSON). Stops
    #              when the cursor is absent/blank/unchanged.
    #   "link"   — follow the RFC 5988 Link header rel="next" URL from each response
    #              (no param math); stops when no rel="next" is present.
    #
    # Universal stop conditions (any one halts the walk):
    #   * max_pages reached (hard-capped at HARD_MAX_PAGES regardless of config),
    #   * a page returned zero records (an empty page means we've run off the end),
    #   * the strategy's own terminator (no next cursor / no next link),
    #   * the per-page quota check vetoes the next page (partial result is kept),
    #   * a page fetch/decoded as a failure (non-2xx / transport) — the records
    #     gathered so far are returned and the LAST response is surfaced so the
    #     QueryService records the real outcome.
    class Paginator
      # Pagination strategy tokens (endpoint.pagination["type"]).
      TYPE_OFFSET = "offset"
      TYPE_PAGE   = "page"
      TYPE_CURSOR = "cursor"
      TYPE_LINK   = "link"

      SUPPORTED_TYPES = [TYPE_OFFSET, TYPE_PAGE, TYPE_CURSOR, TYPE_LINK].freeze

      # Absolute ceiling on pages per fetch, independent of (and capping) the
      # endpoint's configured max_pages. A safety rail against a runaway upstream.
      HARD_MAX_PAGES = 20

      # Default page size used for offset advancement when no limit is configured
      # and the first page's record count cannot inform the stride.
      DEFAULT_PAGE_SIZE = 100

      # @param endpoint [Ai::DataSourceEndpoint] carries the pagination config
      # @param base_params [Hash] caller params (string-keyed) for page 1
      # @param fetch_page [Proc] params -> response (QueryService dispatch path)
      # @param decode_page [Proc] response -> Array<Hash> canonical records
      # @param check_quota [Proc] -> quota descriptor (truthy) to veto next page
      # @param logger [#warn] optional logger (defaults to Rails.logger)
      def initialize(endpoint:, base_params:, fetch_page:, decode_page:, check_quota: nil, logger: nil)
        @endpoint = endpoint
        @base_params = (base_params || {}).transform_keys(&:to_s)
        @fetch_page = fetch_page
        @decode_page = decode_page
        @check_quota = check_quota
        @logger = logger || Rails.logger
        @config = normalize_config(endpoint.respond_to?(:pagination) ? endpoint.pagination : nil)
      end

      # True only when a usable pagination config is present. The QueryService
      # checks this (in addition to gating construction on a non-blank config) so a
      # blank/garbage config is an explicit no-op rather than a single odd request.
      def enabled?
        @config.present? && SUPPORTED_TYPES.include?(@config["type"])
      end

      # Run the page walk. Returns:
      #   {
      #     records:        Array<Hash> concatenated canonical records,
      #     pages_fetched:  Integer,
      #     last_response:  the final response object (for provenance/accounting),
      #     first_response: the first response object,
      #     stopped_reason: String token (why the walk ended),
      #     truncated:      Boolean (hit max_pages with more likely available)
      #   }
      #
      # Never raises: a callback error ends the walk and returns what was gathered.
      def each_page
        records = []
        pages = 0
        first_response = nil
        last_response = nil
        cursor = nil
        next_link = nil
        stopped = "completed"

        while pages < max_pages
          params = page_params(pages, cursor)
          response =
            if next_link
              @fetch_page.call(@base_params.merge(absolute_url_override(next_link)))
            else
              @fetch_page.call(params)
            end
          last_response = response
          first_response ||= response
          pages += 1

          page_records = safe_decode(response)
          records.concat(page_records)

          # A failed page (non-2xx / transport) terminates the walk; the partial
          # records + this response are returned so the caller records the outcome.
          unless success_response?(response)
            stopped = "page_failed"
            break
          end

          if page_records.empty?
            stopped = "empty_page"
            break
          end

          # Strategy terminators + next-page coordinates.
          cursor, next_link, terminator = advance(@config["type"], response, page_records, cursor)
          if terminator
            stopped = terminator
            break
          end

          # Quota veto BEFORE issuing the next request — keep the partial result.
          if pages < max_pages && (quota = vetoed_by_quota?)
            stopped = "quota:#{quota_label(quota)}"
            break
          end
        end

        stopped = "max_pages" if pages >= max_pages && stopped == "completed"

        {
          records: records,
          pages_fetched: pages,
          first_response: first_response,
          last_response: last_response,
          stopped_reason: stopped,
          truncated: stopped == "max_pages"
        }
      end

      private

      attr_reader :endpoint, :config

      # Effective page cap: configured max_pages clamped to [1, HARD_MAX_PAGES].
      def max_pages
        configured = config["max_pages"].to_i
        return HARD_MAX_PAGES if configured <= 0

        [configured, HARD_MAX_PAGES].min
      end

      # Compute the params for page index `page_index` (0-based) under the active
      # strategy. Cursor strategy injects the current cursor; link strategy does
      # not use params (handled via absolute URL override in #each_page).
      def page_params(page_index, cursor)
        case config["type"]
        when TYPE_OFFSET then offset_params(page_index)
        when TYPE_PAGE   then page_number_params(page_index)
        when TYPE_CURSOR then cursor_params(cursor)
        else @base_params.dup
        end
      end

      def offset_params(page_index)
        limit = page_size
        offset = page_index * limit
        params = @base_params.dup
        params[offset_param] = offset.to_s
        params[limit_param] = limit.to_s if limit_param && limit.positive?
        params
      end

      def page_number_params(page_index)
        params = @base_params.dup
        params[page_param] = (start_page + page_index).to_s
        params[limit_param] = page_size.to_s if limit_param && page_size.positive?
        params
      end

      # First page carries no cursor (or a caller-provided seed); later pages carry
      # the cursor surfaced from the previous body.
      def cursor_params(cursor)
        params = @base_params.dup
        params[cursor_param] = cursor.to_s if cursor.present?
        params
      end

      # Returns [next_cursor, next_link, terminator]. terminator is a stop token
      # String when the strategy has no further pages, else nil.
      def advance(type, response, _page_records, current_cursor)
        case type
        when TYPE_CURSOR
          next_cursor = extract_cursor(response)
          return [nil, nil, "no_cursor"] if next_cursor.blank?
          return [nil, nil, "cursor_unchanged"] if next_cursor == current_cursor

          [next_cursor, nil, nil]
        when TYPE_LINK
          link = extract_next_link(response)
          return [nil, nil, "no_next_link"] if link.blank?

          [nil, link, nil]
        else
          # offset / page advance purely by index; no terminator beyond the
          # universal empty-page / max-pages guards.
          [nil, nil, nil]
        end
      end

      # --- cursor extraction (from the decoded body) --------------------------

      # Read the next cursor from the response BODY at the configured cursor_path.
      # Parses JSON lazily (cursor pagination is JSON in practice). A missing path
      # or non-JSON body yields nil (the walk stops cleanly).
      def extract_cursor(response)
        path = config["cursor_path"]
        return nil if path.blank?

        body = parsed_body(response)
        return nil if body.nil?

        value = resolve_path(body, path)
        value.nil? ? nil : value.to_s
      rescue StandardError => e
        @logger.warn("[DataSources::Paginator] cursor extraction failed: #{e.message}")
        nil
      end

      def parsed_body(response)
        raw = response_body(response)
        return nil if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def resolve_path(node, path)
        segments(path).reduce(node) do |current, key|
          break nil if current.nil?

          case current
          when Hash then current.key?(key) ? current[key] : current[key.to_s]
          when Array then (idx = Integer(key, exception: false)) ? current[idx] : nil
          end
        end
      end

      def segments(path)
        str = path.to_s
        if str.start_with?("/")
          str.split("/").reject(&:empty?)
        else
          str.split(".").reject(&:empty?)
        end
      end

      # --- link header (RFC 5988) --------------------------------------------

      # Pull the rel="next" URL out of the Link response header, if any.
      def extract_next_link(response)
        header = response_header(response, "link")
        return nil if header.blank?

        parse_link_header(header)["next"]
      rescue StandardError => e
        @logger.warn("[DataSources::Paginator] link header parse failed: #{e.message}")
        nil
      end

      # Minimal RFC 5988 Link parser: <url>; rel="next", <url>; rel="prev"
      def parse_link_header(header)
        header.split(",").each_with_object({}) do |part, memo|
          segment = part.strip
          url = segment[/\A<([^>]+)>/, 1]
          rel = segment[/rel\s*=\s*"?([^";]+)"?/, 1]
          memo[rel.strip.downcase] = url if url && rel
        end
      end

      # The QueryService's fetch_page callback resolves params -> request; for link
      # following we hand it the absolute next URL via a reserved param the service
      # recognizes (so the same callback handles both modes).
      def absolute_url_override(url)
        { ABSOLUTE_URL_PARAM => url }
      end

      # Reserved param key carrying an already-resolved absolute next-page URL into
      # the QueryService dispatch callback (link-following mode). Double-underscore
      # namespaced so it never collides with a real query parameter.
      ABSOLUTE_URL_PARAM = "__paginate_absolute_url"

      # --- quota --------------------------------------------------------------

      def vetoed_by_quota?
        return nil unless @check_quota

        @check_quota.call
      rescue StandardError => e
        @logger.warn("[DataSources::Paginator] quota check failed (allowing): #{e.message}")
        nil
      end

      def quota_label(quota)
        return quota[:limit] || quota["limit"] || "exceeded" if quota.is_a?(Hash)

        "exceeded"
      end

      # --- decode + response shape helpers ------------------------------------

      def safe_decode(response)
        records = @decode_page.call(response)
        records.is_a?(Array) ? records : []
      rescue StandardError => e
        @logger.warn("[DataSources::Paginator] page decode failed: #{e.message}")
        []
      end

      def success_response?(response)
        status = response_status(response)
        status.to_i.between?(200, 299)
      rescue StandardError
        false
      end

      def response_status(response)
        return response.status if response.respond_to?(:status)

        response.is_a?(Hash) ? (response[:status] || response["status"]) : nil
      end

      def response_body(response)
        return response.body if response.respond_to?(:body)

        response.is_a?(Hash) ? (response[:body] || response["body"]) : nil
      end

      def response_header(response, name)
        headers = response.respond_to?(:headers) ? response.headers : nil
        return nil unless headers

        headers[name] || headers[name.capitalize] || headers[name.upcase] ||
          headers[name.split("-").map(&:capitalize).join("-")]
      end

      # --- config param accessors ---------------------------------------------

      def offset_param
        config["offset_param"].presence || "offset"
      end

      def limit_param
        config["limit_param"].presence
      end

      def page_param
        config["page_param"].presence || "page"
      end

      def cursor_param
        config["cursor_param"].presence || "cursor"
      end

      def start_page
        value = config["start_page"]
        value.nil? ? 1 : value.to_i
      end

      # Page size for offset/page strides: explicit limit wins, else the default.
      def page_size
        explicit = config["limit"] || config["page_size"]
        size = explicit.to_i
        size.positive? ? size : DEFAULT_PAGE_SIZE
      end

      # Coerce the stored pagination column into a string-keyed Hash; nil/garbage
      # collapses to {} so #enabled? is false.
      def normalize_config(raw)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value
        end.tap { |cfg| cfg["type"] = cfg["type"].to_s.strip.downcase if cfg["type"] }
      end
    end
  end
end

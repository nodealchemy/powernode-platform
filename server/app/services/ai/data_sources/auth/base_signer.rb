# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # Shared request-mutation helpers for outbound signers.
      #
      # Signers must work against either a Faraday::Connection (when a caller
      # signs a long-lived connection's default headers/params) or a plain
      # request-env Hash produced by an Adapter
      # ({ method:, url:, headers:, query:, body: }). This base abstracts the
      # two so concrete signers only express *what* to inject, not *where*.
      #
      # Subclasses implement #sign!(conn_or_env, credential:, config:) and use
      # the protected put_header / put_query / read helpers below to mutate the
      # request in place.
      class BaseSigner
        def sign!(_conn_or_env, credential:, config:)
          raise NotImplementedError, "#{self.class}#sign! must be implemented"
        end

        protected

        # Set (overwrite) a request header on either target shape.
        def put_header(target, name, value)
          return if value.nil?

          if faraday_connection?(target)
            target.headers[name] = value
          else
            headers = (target[:headers] ||= {})
            headers[name] = value
          end
        end

        # Merge a query parameter onto either target shape.
        def put_query(target, name, value)
          return if value.nil?

          if faraday_connection?(target)
            target.params[name] = value
          else
            query = (target[:query] ||= {})
            query[name] = value
          end
        end

        # Read the current headers as a plain Hash (best-effort; used by
        # signers that must incorporate existing headers into a signature).
        def read_headers(target)
          if faraday_connection?(target)
            target.headers.to_h
          else
            (target[:headers] || {}).to_h
          end
        end

        # Resolve the absolute request URL for signature schemes (SigV4) that
        # canonicalize the URL. Combines a Faraday connection's url_prefix with
        # any per-request path, or reads :url straight off an env Hash.
        def read_url(target)
          if faraday_connection?(target)
            target.url_prefix.to_s
          else
            target[:url].to_s
          end
        end

        def read_method(target)
          if faraday_connection?(target)
            "GET"
          else
            (target[:method] || "GET").to_s.upcase
          end
        end

        def read_body(target)
          if faraday_connection?(target)
            nil
          else
            target[:body]
          end
        end

        def faraday_connection?(target)
          defined?(Faraday::Connection) && target.is_a?(Faraday::Connection)
        end
      end
    end
  end
end

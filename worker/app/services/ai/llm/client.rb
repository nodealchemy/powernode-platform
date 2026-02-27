# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'response'

module Ai
  module Llm
    # Worker-side LLM client -- all provider logic inline (OpenAI, Anthropic, Ollama).
    class Client
      OPENAI_COMPATIBLE = %w[openai groq mistral azure grok cohere deepseek].freeze
      ANTHROPIC_VERSION = "2023-06-01"

      class RequestError < StandardError
        attr_reader :status_code
        def initialize(message, status_code: nil) = (@status_code = status_code; super(message))
      end

      attr_reader :provider_type

      def self.for_credentials(provider_type:, api_key:, base_url: nil, provider_name: nil)
        new(provider_type: provider_type, api_key: api_key, base_url: base_url, provider_name: provider_name)
      end

      def initialize(provider_type:, api_key:, base_url: nil, provider_name: nil)
        @provider_type = provider_type.to_s.downcase
        @api_key = api_key
        @base_url = resolve_base_url(base_url)
        @provider_name_value = provider_name || @provider_type
        @headers = build_headers
      end

      def complete(messages:, model:, **opts)
        with_circuit_breaker(model) do
          case provider_format
          when :openai
            body = build_openai_body(messages, model, **opts)
            s, p, _ = http_post(openai_url, body)
            s == 200 ? parse_openai_response(p, model) : openai_handle_error(s, p)
          when :anthropic
            body = build_anthropic_body(messages, model, **opts)
            s, p, _ = http_post(anthropic_url, body)
            s == 200 ? parse_anthropic_response(p, model) : anthropic_handle_error(s, p)
          when :ollama
            body = build_ollama_body(messages, model, stream: false, **opts)
            r = HTTParty.post(ollama_url, headers: @headers, body: body.to_json, timeout: 300)
            r.code == 200 ? parse_ollama_response(JSON.parse(r.body), model) : ollama_handle_error(r.code, r.parsed_response)
          end
        end
      end

      def stream(messages:, model:, **opts, &block)
        raise ArgumentError, "Block required for streaming" unless block_given?
        with_circuit_breaker(model) do
          case provider_format
          when :openai    then stream_openai(messages, model, **opts, &block)
          when :anthropic then stream_anthropic(messages, model, **opts, &block)
          when :ollama    then stream_ollama(messages, model, **opts, &block)
          end
        end
      end

      def complete_with_tools(messages:, tools:, model:, **opts)
        with_circuit_breaker(model) do
          case provider_format
          when :openai
            body = build_openai_body(messages, model, **opts)
            body[:tools] = tools.map { |t| { type: "function", function: { name: t[:name], description: t[:description], parameters: t[:parameters], strict: t[:strict] || false }.compact } }
            body[:tool_choice] = opts[:tool_choice] || "auto"
            s, p, _ = http_post(openai_url, body)
            s == 200 ? parse_openai_response(p, model) : openai_handle_error(s, p)
          when :anthropic
            body = build_anthropic_body(messages, model, **opts)
            body[:tools] = tools.map { |t| { name: t[:name], description: t[:description], input_schema: t[:parameters] || t[:input_schema] } }
            body[:tool_choice] = opts[:tool_choice] ? anthropic_tool_choice(opts[:tool_choice]) : { type: "auto" }
            s, p, _ = http_post(anthropic_url, body)
            s == 200 ? parse_anthropic_response(p, model) : anthropic_handle_error(s, p)
          when :ollama
            body = build_ollama_body(messages, model, stream: false, **opts)
            body[:tools] = tools.map { |t| { type: "function", function: { name: t[:name], description: t[:description], parameters: t[:parameters] } } }
            r = HTTParty.post(ollama_url, headers: @headers, body: body.to_json, timeout: 300)
            r.code == 200 ? parse_ollama_response(JSON.parse(r.body), model) : ollama_handle_error(r.code, r.parsed_response)
          end
        end
      end

      def complete_structured(messages:, schema:, model:, **opts)
        with_circuit_breaker(model) do
          case provider_format
          when :openai
            body = build_openai_body(messages, model, **opts)
            body[:response_format] = { type: "json_schema", json_schema: { name: schema[:name] || "response", schema: schema[:schema] || schema, strict: true } }
            s, p, _ = http_post(openai_url, body)
            s == 200 ? parse_openai_response(p, model) : openai_handle_error(s, p)
          when :anthropic
            body = build_anthropic_body(messages, model, **opts)
            body[:output_config] = { format: { type: "json", schema: schema[:schema] || schema } }
            s, p, _ = http_post(anthropic_url, body)
            s == 200 ? parse_anthropic_response(p, model) : anthropic_handle_error(s, p)
          when :ollama
            body = build_ollama_body(messages, model, stream: false, **opts)
            body[:format] = schema[:schema] || schema
            r = HTTParty.post(ollama_url, headers: @headers, body: body.to_json, timeout: 300)
            r.code == 200 ? parse_ollama_response(JSON.parse(r.body), model) : ollama_handle_error(r.code, r.parsed_response)
          end
        end
      end

      def provider_name = @provider_name_value

      private

      def provider_format
        return :anthropic if @provider_type == "anthropic"
        return :ollama if @provider_type == "ollama"
        :openai
      end
      def resolve_base_url(url)
        case provider_format
        when :anthropic then (url || "https://api.anthropic.com/v1").to_s.sub(/\/+\z/, "")
        when :ollama    then (url || "http://localhost:11434").to_s.sub(/\/+\z/, "")
        else                 (url || "https://api.openai.com/v1").to_s.sub(/\/+\z/, "")
        end
      end
      def build_headers
        base = { "Content-Type" => "application/json", "User-Agent" => "Powernode-AI/2.0" }
        case provider_format
        when :anthropic then base.merge("x-api-key" => @api_key, "anthropic-version" => ANTHROPIC_VERSION)
        when :ollama    then @api_key.present? ? base.merge("Authorization" => "Bearer #{@api_key}") : base
        else                 base.merge("Authorization" => "Bearer #{@api_key}")
        end
      end
      def openai_url = "#{@base_url}/chat/completions"
      def anthropic_url = "#{@base_url}/messages"
      def ollama_url = @base_url.end_with?("/api") ? "#{@base_url}/chat" : "#{@base_url}/api/chat"
      def http_post(url, body)
        r = HTTParty.post(url, headers: @headers, body: body.to_json, timeout: 120)
        [r.code, r.parsed_response, r.headers]
      end
      def http_stream(url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 300
        http.open_timeout = 30
        req = Net::HTTP::Post.new(uri.request_uri)
        @headers.each { |k, v| req[k] = v }
        req.body = body.to_json
        http.request(req) do |resp|
          raise RequestError.new("HTTP #{resp.code}: #{resp.body}", status_code: resp.code.to_i) unless resp.is_a?(Net::HTTPSuccess)
          yield resp
        end
      end

      def parse_sse_stream(response)
        buf = ""
        response.read_body do |chunk|
          buf += chunk
          while (i = buf.index("\n\n"))
            buf[0...i].split("\n").each do |line|
              next unless line.start_with?("data: ")
              d = line[6..]
              next if d == "[DONE]"
              yield JSON.parse(d) rescue logger.warn("[LLM] SSE parse error")
            end
            buf = buf[(i + 2)..]
          end
        end
      end
      def parse_ndjson_stream(response)
        buf = ""
        response.read_body do |chunk|
          buf += chunk
          while (i = buf.index("\n"))
            line = buf[0...i].strip
            buf = buf[(i + 1)..]
            next if line.empty?
            yield JSON.parse(line) rescue logger.warn("[LLM] NDJSON parse error")
          end
        end
      end
      def parse_anthropic_sse(response)
        buf = ""
        evt = nil
        response.read_body do |chunk|
          buf += chunk
          while (i = buf.index("\n\n"))
            buf[0...i].split("\n").each do |line|
              if line.start_with?("event: ") then evt = line[7..]
              elsif line.start_with?("data: ")
                yield evt, JSON.parse(line[6..]) rescue logger.warn("[LLM] Anthropic SSE parse error")
              end
            end
            buf = buf[(i + 2)..]
          end
        end
      end

      def build_response(attrs) = Response.new(attrs.merge(provider: provider_name))
      def build_error_response(error, status_code: nil)
        Response.new(content: nil, provider: provider_name, finish_reason: "error",
                     raw_response: { error: error, status_code: status_code })
      end
      def safe_parse_json(str)
        return str unless str.is_a?(String)
        JSON.parse(str) rescue str
      end
      def with_circuit_breaker(model)
        yield
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
             Net::ReadTimeout, Net::OpenTimeout => e
        logger.error "[LLM] Connection failed (#{provider_name}/#{model}): #{e.message}"
        Response.new(content: nil, provider: provider_name, finish_reason: "error",
                     raw_response: { error: "Connection failed: #{e.message}" })
      end

      def logger = @logger ||= PowernodeWorker.application.logger
      def ts = Time.current.iso8601

      # -- OpenAI -------
      def build_openai_body(messages, model, **opts)
        sys_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
        other = messages.reject { |m| (m[:role] || m["role"]) == "system" }
        sys = sys_msgs.map { |m| m[:content] || m["content"] }.join("\n")
        sys = [sys, opts[:system_prompt]].reject(&:blank?).join("\n") if opts[:system_prompt].present?
        fm = []
        fm << { role: "system", content: sys } if sys.present?
        other.each { |m| fm << openai_normalize_message(m) }
        body = { model: model, messages: fm, max_tokens: opts[:max_tokens] || 4096, temperature: opts[:temperature] || 0.7 }
        %i[top_p stop presence_penalty frequency_penalty].each { |k| body[k] = opts[k] if opts[k] }
        body
      end

      def openai_normalize_message(msg)
        role = msg[:role] || msg["role"]
        result = { role: role, content: msg[:content] || msg["content"] }
        result[:tool_call_id] = msg[:tool_call_id] || msg["tool_call_id"] if role == "tool"
        raw = msg[:tool_calls] || msg["tool_calls"]
        result[:tool_calls] = raw.map { |tc| openai_normalize_tool_call(tc) } if raw
        result
      end

      def openai_normalize_tool_call(tc)
        return tc if tc[:type] == "function" || tc["type"] == "function"
        args = tc[:arguments] || tc["arguments"] || {}
        args = args.to_json unless args.is_a?(String)
        { id: tc[:id] || tc["id"], type: "function", function: { name: tc[:name] || tc["name"], arguments: args } }
      end

      def parse_openai_response(parsed, model)
        ch = parsed.dig("choices", 0) || {}
        msg = ch["message"] || {}
        tcs = (msg["tool_calls"] || []).map { |tc| { id: tc["id"], name: tc.dig("function", "name"), arguments: safe_parse_json(tc.dig("function", "arguments")) } }
        u = parsed["usage"] || {}
        build_response(content: msg["content"], tool_calls: tcs, finish_reason: ch["finish_reason"],
                       model: parsed["model"] || model, raw_response: parsed,
                       usage: { prompt_tokens: u["prompt_tokens"] || 0, completion_tokens: u["completion_tokens"] || 0,
                                cached_tokens: u.dig("prompt_tokens_details", "cached_tokens") || 0, total_tokens: u["total_tokens"] || 0 })
      end

      def openai_handle_error(status, parsed)
        m = parsed.is_a?(Hash) ? (parsed.dig("error", "message") || parsed["error"] || "Unknown error") : parsed.to_s
        m = m.to_json if m.is_a?(Hash)
        build_error_response("#{m} (HTTP #{status})", status_code: status)
      end

      def stream_openai(messages, model, **opts)
        body = build_openai_body(messages, model, **opts).merge(stream: true, stream_options: { include_usage: true })
        acc = ""; tc_buf = {}; usage = {}; sid = SecureRandom.uuid; fin = nil
        yield Chunk.new(type: :stream_start, stream_id: sid, timestamp: ts)
        http_stream(openai_url, body) do |resp|
          parse_sse_stream(resp) do |p|
            c = p.dig("choices", 0); next unless c
            d = c["delta"] || {}
            if d["content"]
              acc += d["content"]
              yield Chunk.new(type: :content_delta, content: d["content"], stream_id: sid, timestamp: ts)
            end
            (d["tool_calls"] || []).each do |tc|
              idx = tc["index"]
              if tc["id"]
                tc_buf[idx] = { id: tc["id"], name: tc.dig("function", "name"), arguments: "" }
                yield Chunk.new(type: :tool_call_start, tool_call_id: tc["id"], tool_call_name: tc.dig("function", "name"), stream_id: sid, timestamp: ts)
              end
              if tc.dig("function", "arguments")
                tc_buf[idx][:arguments] += tc["function"]["arguments"]
                yield Chunk.new(type: :tool_call_delta, tool_call_id: tc_buf[idx][:id], tool_call_args_delta: tc["function"]["arguments"], stream_id: sid, timestamp: ts)
              end
            end
            fin = c["finish_reason"] if c["finish_reason"]
            if p["usage"]
              usage = { prompt_tokens: p["usage"]["prompt_tokens"], completion_tokens: p["usage"]["completion_tokens"],
                        cached_tokens: p["usage"].dig("prompt_tokens_details", "cached_tokens") || 0, total_tokens: p["usage"]["total_tokens"] }
            end
          end
        end
        tc_buf.each_value { |tc| yield Chunk.new(type: :tool_call_end, tool_call_id: tc[:id], stream_id: sid, timestamp: ts) }
        yield Chunk.new(type: :stream_end, done: true, usage: usage, stream_id: sid, timestamp: ts)
        ntcs = tc_buf.values.map { |tc| { id: tc[:id], name: tc[:name], arguments: safe_parse_json(tc[:arguments]) } }
        build_response(content: acc.presence, tool_calls: ntcs, finish_reason: fin, model: model, usage: usage, stream_id: sid)
      rescue RequestError => e
        yield Chunk.new(type: :error, content: e.message, stream_id: sid, timestamp: ts)
        build_error_response(e.message, status_code: e.status_code)
      end

      # -- Anthropic -------

      def build_anthropic_body(messages, model, **opts)
        sys_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
        other = messages.reject { |m| (m[:role] || m["role"]) == "system" }
        sys = sys_msgs.map { |m| m[:content] || m["content"] }.join("\n")
        sys = [sys, opts[:system_prompt]].reject(&:blank?).join("\n") if opts[:system_prompt].present?
        body = { model: model, messages: other.map { |m| anthropic_normalize_message(m) }, max_tokens: opts[:max_tokens] || 4096 }
        if sys.present?
          body[:system] = opts[:cache_system_prompt] ? [{ type: "text", text: sys, cache_control: { type: "ephemeral" } }] : sys
        end
        body[:temperature] = opts[:temperature] if opts[:temperature]
        body[:top_p] = opts[:top_p] if opts[:top_p]
        body[:stop_sequences] = opts[:stop] if opts[:stop]
        body[:thinking] = { type: "enabled", budget_tokens: opts[:thinking_budget] } if opts[:thinking_budget]
        body
      end

      def anthropic_normalize_message(msg)
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        if role == "tool"
          return { role: "user", content: [{ type: "tool_result", tool_use_id: msg[:tool_call_id] || msg["tool_call_id"],
                                             content: content.is_a?(String) ? content : content.to_json }] }
        end
        if role == "assistant" && (raw = msg[:tool_calls] || msg["tool_calls"])
          blocks = []
          blocks << { type: "text", text: content } if content.present?
          raw.each do |tc|
            name = tc[:name] || tc["name"] || tc.dig(:function, :name) || tc.dig("function", "name")
            input = tc[:arguments] || tc["arguments"] || tc.dig(:function, :arguments) || tc.dig("function", "arguments") || {}
            input = JSON.parse(input) if input.is_a?(String)
            blocks << { type: "tool_use", id: tc[:id] || tc["id"], name: name, input: input }
          end
          return { role: "assistant", content: blocks }
        end
        { role: role, content: content }
      end

      def parse_anthropic_response(parsed, model)
        blocks = parsed["content"] || []
        text = blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join
        think = blocks.select { |b| b["type"] == "thinking" }.map { |b| b["thinking"] }.join
        tcs = blocks.select { |b| b["type"] == "tool_use" }.map { |b| { id: b["id"], name: b["name"], arguments: b["input"] } }
        u = parsed["usage"] || {}
        build_response(content: text.presence, tool_calls: tcs, finish_reason: parsed["stop_reason"],
                       model: parsed["model"] || model, raw_response: parsed, thinking_content: think.presence,
                       usage: { prompt_tokens: u["input_tokens"] || 0, completion_tokens: u["output_tokens"] || 0,
                                cached_tokens: u["cache_read_input_tokens"] || 0,
                                total_tokens: (u["input_tokens"] || 0) + (u["output_tokens"] || 0) })
      end

      def anthropic_handle_error(status, parsed)
        m = if parsed.is_a?(Hash)
              ev = parsed["error"]
              ev.is_a?(Hash) ? (ev["message"] || ev.to_json) : (ev || "Unknown error")
            else parsed.to_s end
        m = m.to_json if m.is_a?(Hash)
        build_error_response("#{m} (HTTP #{status})", status_code: status)
      end

      def anthropic_tool_choice(c)
        case c
        when "auto" then { type: "auto" }
        when "none" then { type: "none" }
        when "required", "any" then { type: "any" }
        when Hash then c
        else { type: "tool", name: c.to_s }
        end
      end

      def stream_anthropic(messages, model, **opts)
        body = build_anthropic_body(messages, model, **opts).merge(stream: true)
        acc = ""; tcs = []; cur = nil; usage = {}; sid = SecureRandom.uuid; fin = nil; think = ""
        yield Chunk.new(type: :stream_start, stream_id: sid, timestamp: ts)
        http_stream(anthropic_url, body) do |resp|
          parse_anthropic_sse(resp) do |evt, p|
            case evt
            when "content_block_start"
              if p.dig("content_block", "type") == "tool_use"
                cur = { id: p.dig("content_block", "id"), name: p.dig("content_block", "name"), arguments: "" }
                yield Chunk.new(type: :tool_call_start, tool_call_id: cur[:id], tool_call_name: cur[:name], stream_id: sid, timestamp: ts)
              end
            when "content_block_delta"
              d = p["delta"] || {}
              case d["type"]
              when "text_delta"
                acc += d["text"]
                yield Chunk.new(type: :content_delta, content: d["text"], stream_id: sid, timestamp: ts)
              when "input_json_delta"
                if cur
                  cur[:arguments] += d["partial_json"].to_s
                  yield Chunk.new(type: :tool_call_delta, tool_call_id: cur[:id], tool_call_args_delta: d["partial_json"], stream_id: sid, timestamp: ts)
                end
              when "thinking_delta"
                think += d["thinking"].to_s
                yield Chunk.new(type: :thinking_delta, content: d["thinking"], stream_id: sid, timestamp: ts)
              end
            when "content_block_stop"
              if cur
                tcs << { id: cur[:id], name: cur[:name], arguments: safe_parse_json(cur[:arguments]) }
                yield Chunk.new(type: :tool_call_end, tool_call_id: cur[:id], stream_id: sid, timestamp: ts)
                cur = nil
              end
            when "message_delta"
              fin = p.dig("delta", "stop_reason")
              usage[:completion_tokens] = p["usage"]["output_tokens"] if p["usage"]
            when "message_start"
              if p.dig("message", "usage")
                usage[:prompt_tokens] = p["message"]["usage"]["input_tokens"]
                usage[:cached_tokens] = p["message"]["usage"]["cache_read_input_tokens"] || 0
              end
            end
          end
        end
        usage[:total_tokens] = (usage[:prompt_tokens] || 0) + (usage[:completion_tokens] || 0)
        yield Chunk.new(type: :stream_end, done: true, usage: usage, stream_id: sid, timestamp: ts)
        build_response(content: acc.presence, tool_calls: tcs, finish_reason: fin, model: model,
                       usage: usage, thinking_content: think.presence, stream_id: sid)
      rescue RequestError => e
        yield Chunk.new(type: :error, content: e.message, stream_id: sid, timestamp: ts)
        build_error_response(e.message, status_code: e.status_code)
      end

      # -- Ollama -------

      def build_ollama_body(messages, model, stream: false, **opts)
        fm = messages.map do |m|
          role = m[:role] || m["role"]; content = m[:content] || m["content"]
          role == "tool" ? { role: "tool", content: content.is_a?(String) ? content : content.to_json } : { role: role, content: content }
        end
        body = { model: model, messages: fm, stream: stream }
        options = {}
        options[:temperature] = opts[:temperature] if opts[:temperature]
        options[:num_predict] = opts[:max_tokens] if opts[:max_tokens]
        body[:options] = options if options.any?
        body[:keep_alive] = opts[:keep_alive] if opts[:keep_alive]
        body
      end

      def parse_ollama_response(parsed, model)
        msg = parsed["message"] || {}
        tcs = (msg["tool_calls"] || []).map { |tc| { id: SecureRandom.uuid, name: tc.dig("function", "name"), arguments: tc.dig("function", "arguments") || {} } }
        build_response(content: msg["content"], tool_calls: tcs, raw_response: parsed,
                       finish_reason: parsed["done"] ? "stop" : "length", model: parsed["model"] || model,
                       usage: { prompt_tokens: parsed["prompt_eval_count"] || 0, completion_tokens: parsed["eval_count"] || 0,
                                total_tokens: (parsed["prompt_eval_count"] || 0) + (parsed["eval_count"] || 0) })
      end

      def ollama_handle_error(status, parsed)
        m = parsed.is_a?(Hash) ? (parsed["error"] || "Unknown error") : parsed.to_s
        build_error_response("#{m} (HTTP #{status})", status_code: status)
      end

      def stream_ollama(messages, model, **opts)
        body = build_ollama_body(messages, model, stream: true, **opts)
        acc = ""; tcs = []; usage = {}; sid = SecureRandom.uuid
        yield Chunk.new(type: :stream_start, stream_id: sid, timestamp: ts)
        uri = URI.parse(ollama_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"; http.read_timeout = 300; http.open_timeout = 30
        req = Net::HTTP::Post.new(uri.request_uri)
        @headers.each { |k, v| req[k] = v }; req.body = body.to_json
        http.request(req) do |resp|
          unless resp.is_a?(Net::HTTPSuccess)
            yield Chunk.new(type: :error, content: "HTTP #{resp.code}", stream_id: sid, timestamp: ts)
            return build_error_response("HTTP #{resp.code}", status_code: resp.code.to_i)
          end
          parse_ndjson_stream(resp) do |p|
            if p.dig("message", "content")
              acc += p["message"]["content"]
              yield Chunk.new(type: :content_delta, content: p["message"]["content"], stream_id: sid, timestamp: ts)
            end
            (p.dig("message", "tool_calls") || []).each do |tc|
              t = { id: SecureRandom.uuid, name: tc.dig("function", "name"), arguments: tc.dig("function", "arguments") || {} }
              tcs << t
              yield Chunk.new(type: :tool_call_start, tool_call_id: t[:id], tool_call_name: t[:name], stream_id: sid, timestamp: ts)
              yield Chunk.new(type: :tool_call_end, tool_call_id: t[:id], stream_id: sid, timestamp: ts)
            end
            if p["done"]
              usage = { prompt_tokens: p["prompt_eval_count"] || 0, completion_tokens: p["eval_count"] || 0,
                        total_tokens: (p["prompt_eval_count"] || 0) + (p["eval_count"] || 0) }
            end
          end
        end
        yield Chunk.new(type: :stream_end, done: true, usage: usage, stream_id: sid, timestamp: ts)
        build_response(content: acc.presence, tool_calls: tcs, finish_reason: "stop", model: model, usage: usage, stream_id: sid)
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
        yield Chunk.new(type: :error, content: e.message, stream_id: sid, timestamp: ts)
        build_error_response("Ollama connection failed: #{e.message}")
      end
    end
  end
end

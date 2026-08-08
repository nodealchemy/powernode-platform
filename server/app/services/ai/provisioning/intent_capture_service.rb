# frozen_string_literal: true

module Ai
  module Provisioning
    # Translates natural language operator input into a structured Project Brief.
    #
    # The brief is the canonical input to PlanComposerService. It captures intent,
    # use case, scale, regions, compliance, budget cap, latency targets, data
    # residency, and an optional preferred provider.
    #
    # `capture` is the cold-start entry — convert raw NL into a brief Hash plus
    # the list of fields that still need clarification.
    #
    # `refine` accepts a partially-populated brief plus a clarification utterance
    # and merges new field values in.
    #
    # `classify` is the cheap intent-type prefilter the Concierge uses to decide
    # whether a message should route to the provisioning flow at all. A regex
    # match returns immediately; ambiguous inputs fall through to a low-token
    # LLM call when an `llm_client` is available.
    #
    # All LLM access is funneled through #extract_brief_from_llm and
    # #classify_with_llm so test specs can stub the seam while real merge,
    # normalization, and missing-field logic still runs.
    class IntentCaptureService
      # Supplies resolve_service_agent — used to attribute this service's LLM
      # calls to an agent so they are recorded (IMP 019fe1da).
      include AgentBackedService

      BRIEF_SCHEMA = {
        intent: :string,
        use_case: :string,
        scale: { initial: :integer, target: :integer, growth_profile: :string },
        regions: :array,
        compliance: :array,
        budget_cap_usd_monthly: :float,
        latency_targets_ms: { p99: :integer },
        data_residency: :array,
        preferred_provider: :string_or_nil,
        # M3 "Run My Code" fields — populated when the operator references a
        # Git repo and wants its code deployed onto the provisioned instance.
        # All optional: when null, the plan stays a pure provisioning plan and
        # PlanComposerService skips the deploy_app_code step.
        repo_url: :string_or_nil,
        branch: :string_or_nil,
        start_command: :string_or_nil,
        runtime_hint: :string_or_nil # node|python|ruby|go|docker|java|none
      }.freeze

      REQUIRED_FIELDS = %i[intent use_case scale regions budget_cap_usd_monthly].freeze

      INTENT_KEYWORDS = /\b(?:provision|deploy|host|stack|cluster|database|scale|migrate)\b/i.freeze

      INTENT_PROVISION = "provision_infrastructure"
      INTENT_GENERAL = "general_chat"

      DEFAULT_TEMPERATURE = 0.2
      DEFAULT_MAX_TOKENS = 1024
      CLASSIFY_MAX_TOKENS = 64

      # The provider catalog is supplied by the system extension. Core mode has
      # none, and its absence has a defined meaning throughout this subsystem
      # (see PlanComposerService#resolve_provider_choice): "no providers
      # configured", not "reject everything". Extracted as a predicate so the
      # core-mode path is directly testable without unloading the extension.
      def self.provider_catalog_available?
        defined?(::System::Provider).present?
      end

      attr_reader :account, :user, :conversation

      def initialize(account:, user:, conversation: nil)
        @account = account
        @user = user
        @conversation = conversation
      end

      # Convert a free-text utterance into a structured brief.
      # Merges the LLM's extracted fields onto an optional `prior_brief` so
      # repeated passes converge on a complete brief.
      def capture(natural_language:, prior_brief: nil)
        base = normalize_brief(prior_brief)
        @cap_exceeded_payload = nil
        extracted = extract_brief_from_llm(
          natural_language: natural_language,
          prior_brief: base,
          mode: :capture
        ) || {}

        merged = deep_merge_brief(base, normalize_brief(extracted))
        coerced = coerce_brief(merged)

        result = { brief: coerced, missing_fields: missing_fields_for(coerced) }
        result.merge!(cap_exceeded_attributes) if @cap_exceeded_payload
        result
      end

      # Apply a clarification utterance against an existing brief.
      # Re-runs extraction with the brief as context and merges the new fields.
      def refine(brief:, clarification:)
        base = normalize_brief(brief)
        @cap_exceeded_payload = nil
        extracted = extract_brief_from_llm(
          natural_language: clarification,
          prior_brief: base,
          mode: :refine
        ) || {}

        merged = deep_merge_brief(base, normalize_brief(extracted))
        coerced = coerce_brief(merged)

        result = { brief: coerced, missing_fields: missing_fields_for(coerced) }
        result.merge!(cap_exceeded_attributes) if @cap_exceeded_payload
        result
      end

      # Cheap intent classification. Regex prefilter handles the obvious cases
      # without an LLM round-trip; ambiguous inputs optionally fall through to
      # a low-token LLM call when a client is available. Returns at minimum
      # `{ intent_type: "general_chat", confidence: 0.3 }` so callers always
      # get a structured result.
      def classify(natural_language:)
        text = natural_language.to_s
        return { intent_type: INTENT_GENERAL, confidence: 0.0 } if text.strip.empty?

        if text.match?(INTENT_KEYWORDS)
          return { intent_type: INTENT_PROVISION, confidence: regex_confidence(text) }
        end

        llm_result = classify_with_llm(text)
        return llm_result if llm_result

        { intent_type: INTENT_GENERAL, confidence: 0.3 }
      end

      private

      # ----- LLM seams (stubbed in specs) ------------------------------------

      # Returns a Hash of brief fields parsed from the LLM response, or nil.
      # The brief assembly logic in #capture/#refine remains real even when
      # this method is stubbed.
      #
      # CostCapGuard gates the LLM call: when the account has burned through
      # its daily LLM allowance we return nil so the caller falls back to the
      # prior brief and surfaces an upgrade prompt via the missing_fields list.
      def extract_brief_from_llm(natural_language:, prior_brief:, mode:)
        client = llm_client
        return nil unless client

        guard = ::Ai::Provisioning::CostCapGuard.allow?(account: account)
        if guard.cap_exceeded?
          @cap_exceeded_payload = guard.payload
          Rails.logger.warn(
            "[IntentCaptureService] LLM cost cap exceeded for account=#{account&.id} " \
              "(spent=$#{guard.payload[:spent]}, cap=$#{guard.payload[:cap]})"
          )
          return nil
        end

        prompt = build_brief_prompt(natural_language, prior_brief, mode)
        response = safe_complete(
          client,
          messages: [{ role: "user", content: prompt }],
          max_tokens: DEFAULT_MAX_TOKENS,
          temperature: DEFAULT_TEMPERATURE
        )
        return nil unless response&.success?

        parse_brief_json(response.content)
      end

      # Returns { intent_type:, confidence: } from a low-token LLM call,
      # or nil when no client is configured / the call fails.
      def classify_with_llm(natural_language)
        client = llm_client
        return nil unless client

        prompt = build_classify_prompt(natural_language)
        response = safe_complete(
          client,
          messages: [{ role: "user", content: prompt }],
          max_tokens: CLASSIFY_MAX_TOKENS,
          temperature: 0.0
        )
        return nil unless response&.success?

        parse_classify_json(response.content)
      end

      # Lazy-initialized; stubbable via `allow(service).to receive(:llm_client)`.
      def llm_client
        @llm_client ||= build_llm_client
      end

      # Wrapped so every LLM call this service makes lands an Ai::AgentExecution
      # — token counts, cost_usd, performance_metrics and the budget debit
      # (IMP 019fe1da). #tracked_client_for wraps WITHOUT re-routing which
      # provider serves the call; see its doc for why that distinction matters
      # and why there is no double-debit.
      def build_llm_client
        tracked_client_for(
          WorkerLlmClient.for_account(account),
          slugs: ::Ai::Provisioning::TrackingAgents::SLUGS
        )
      rescue StandardError => e
        Rails.logger.warn("[IntentCaptureService] LLM client unavailable: #{e.message}")
        nil
      end

      def safe_complete(client, **opts)
        client.complete(model: resolve_model, **opts)
      rescue WorkerLlmClient::WorkerLlmError => e
        Rails.logger.warn("[IntentCaptureService] LLM call failed: #{e.message}")
        nil
      end

      def resolve_model
        # Prefer the conversation agent's configured model when present, else
        # ask the same provider WorkerLlmClient.for_account picks (i.e. the
        # account's first active *credential's* provider) for its default
        # model. Picking by Ai::Provider#is_active alone misses the case
        # where multiple providers are flagged active but only one has live
        # credentials — IntentCaptureService would then send (e.g.)
        # "gpt-4.1-mini" to an Anthropic HTTP client and the API would 404.
        model = conversation&.agent&.try(:model)
        model ||= conversation&.agent&.mcp_tool_manifest&.dig("model")
        return model if model.present?

        credential = account&.ai_provider_credentials&.active
                            &.includes(:provider)&.first
        credential&.provider&.default_model.presence || "gpt-4.1-mini"
      end

      # ----- Prompts ---------------------------------------------------------

      def build_brief_prompt(natural_language, prior_brief, mode)
        action_label = mode == :refine ? "Update the brief with new information" : "Extract a brief from the message"
        <<~PROMPT
          You are a provisioning intent extractor. #{action_label}.

          Return ONLY a single JSON object — no prose, no code fences. The object
          contains any of these fields you can confidently infer; OMIT fields you
          can't determine (do NOT guess):

            intent: short string ("provision a 3-node Postgres cluster")
            use_case: longer description of what the workload does
            scale: { initial: int, target: int, growth_profile: "linear"|"exponential"|"steady"|"bursty" }
            regions: array of region strings (e.g. ["us-east-1","eu-west-1"])
            compliance: array of frameworks (e.g. ["SOC2","HIPAA","PCI"])
            budget_cap_usd_monthly: number
            latency_targets_ms: { p99: int }
            data_residency: array of country/region codes the data must stay in
            preferred_provider: string id of a cloud provider, or null

          Provider extraction rule: if the operator names a specific provider
          (AWS, Hetzner, DigitalOcean, GCP, Azure, Vultr, Linode, OpenStack,
          Local QEMU/KVM, LocalQemu, "local hypervisor", Pro Cloud), populate
          `preferred_provider` with the lowercase canonical identifier — e.g.
          "aws", "hetzner", "digitalocean", "gcp", "azure", "vultr", "linode",
          "openstack", "local_qemu" (for Local QEMU/KVM and any "local
          hypervisor" / "on-box" phrasing), "pro_cloud" (Powernode-managed
          pool). If no provider is mentioned, leave it null (do NOT guess).

          Local provider regions rule: when `preferred_provider` is
          "local_qemu" (or any other local-hypervisor provider — runs on the
          operator's own hardware), regions are NOT meaningful. Even if the
          operator mentions a cloud-style region like "us-east" or "eu-west"
          in passing, leave `regions` as an empty array []. Local providers
          have no concept of cloud regions; surfacing one would make the
          downstream plan composer try to resolve a non-existent zone. If
          the operator truly insists on a cloud-region label after picking
          local_qemu, treat it as confused intent and prefer empty regions.

          Run-My-Code rule: if the operator references a Git repository (e.g.
          "github.com/me/my-bot", "github:me/repo", "gitlab.com/foo/bar",
          "https://gitea.example.com/me/svc"), populate `repo_url` with the
          canonical HTTPS URL of the repo. If they mention a branch, populate
          `branch` (default to "main" only when the operator is explicit; leave
          null otherwise). If they specify a start command (e.g. "run node
          index.js", "start with python app.py", "launch via npm start"),
          populate `start_command`. If you can confidently infer the runtime
          from context (Node.js / Python / Ruby / Go / Docker / Java),
          populate `runtime_hint` with the lowercase token: "node", "python",
          "ruby", "go", "docker", "java", or "none". If none of these can be
          determined, leave the field null (do NOT guess).

          Existing brief (merge new fields onto this — do not repeat fields you have nothing to add to):
          #{JSON.dump(prior_brief)}

          Operator message:
          #{natural_language}
        PROMPT
      end

      def build_classify_prompt(natural_language)
        <<~PROMPT
          Classify the operator's message into ONE intent and a confidence score.

          Intents:
            #{INTENT_PROVISION}  — wants to create / scale / migrate / replace infrastructure
            #{INTENT_GENERAL}    — anything else (questions, conversation, status checks)

          Return JSON ONLY: {"intent_type":"...","confidence":0.0-1.0}

          Message:
          #{natural_language}
        PROMPT
      end

      # ----- Parsing ---------------------------------------------------------

      def parse_brief_json(content)
        json = extract_json_object(content)
        return nil unless json.is_a?(Hash)

        json.deep_stringify_keys
      rescue JSON::ParserError => e
        Rails.logger.warn("[IntentCaptureService] Brief JSON parse failed: #{e.message}")
        nil
      end

      def parse_classify_json(content)
        json = extract_json_object(content)
        return nil unless json.is_a?(Hash)

        intent = json["intent_type"] || json[:intent_type]
        confidence = (json["confidence"] || json[:confidence]).to_f

        return nil unless [INTENT_PROVISION, INTENT_GENERAL].include?(intent)

        { intent_type: intent, confidence: confidence.clamp(0.0, 1.0) }
      rescue JSON::ParserError => e
        Rails.logger.warn("[IntentCaptureService] Classify JSON parse failed: #{e.message}")
        nil
      end

      def extract_json_object(content)
        return nil unless content.is_a?(String)

        # Strip ```json fences and surrounding prose; isolate the largest balanced object.
        stripped = content.strip
        stripped = stripped.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "")
        first = stripped.index("{")
        last = stripped.rindex("}")
        return nil unless first && last && last > first

        JSON.parse(stripped[first..last])
      end

      # ----- Brief shape helpers --------------------------------------------

      def empty_brief
        {
          "intent" => nil,
          "use_case" => nil,
          "scale" => { "initial" => nil, "target" => nil, "growth_profile" => nil },
          "regions" => [],
          "compliance" => [],
          "budget_cap_usd_monthly" => nil,
          "latency_targets_ms" => { "p99" => nil },
          "data_residency" => [],
          "preferred_provider" => nil,
          "repo_url" => nil,
          "branch" => nil,
          "start_command" => nil,
          "runtime_hint" => nil
        }
      end

      def normalize_brief(brief)
        return empty_brief unless brief.is_a?(Hash)

        brief.deep_stringify_keys
      end

      def deep_merge_brief(base, additions)
        base = empty_brief.deep_merge(base) { |_k, a, b| b.nil? ? a : b }
        return base if additions.blank?

        base.deep_merge(additions) do |_k, a, b|
          if b.nil? || (b.respond_to?(:empty?) && b.empty? && !a.nil?)
            a
          elsif a.is_a?(Array) && b.is_a?(Array)
            (a + b).uniq
          else
            b
          end
        end
      end

      def coerce_brief(brief)
        out = brief.dup
        out["intent"] = out["intent"]&.to_s
        out["use_case"] = out["use_case"]&.to_s

        scale = out["scale"].is_a?(Hash) ? out["scale"].dup : {}
        scale["initial"] = scale["initial"]&.to_i unless scale["initial"].nil?
        scale["target"] = scale["target"]&.to_i unless scale["target"].nil?
        scale["growth_profile"] = scale["growth_profile"]&.to_s
        out["scale"] = scale

        out["regions"] = Array(out["regions"]).map(&:to_s).uniq
        out["compliance"] = Array(out["compliance"]).map(&:to_s).uniq
        out["data_residency"] = Array(out["data_residency"]).map(&:to_s).uniq

        # Resolve preferred_provider against what the account ACTUALLY has,
        # BEFORE the local-provider scrub below — that scrub keys off the
        # provider TYPE, and an operator naturally writes the provider's NAME.
        out["preferred_provider"] = normalize_preferred_provider(out["preferred_provider"])

        # Local-provider regions are meaningless — runs on the operator's own
        # hardware. Belt-and-suspenders to the prompt rule above: if the LLM
        # still extracts a cloud-style region alongside a local provider,
        # scrub it so the downstream composer doesn't try to resolve a
        # non-existent zone. Keep this list synchronized with
        # CostEstimatorService::LOCAL_PROVIDER_TYPES.
        local_providers = %w[local_qemu]
        if out["preferred_provider"] && local_providers.include?(out["preferred_provider"].to_s)
          out["regions"] = []
        end

        unless out["budget_cap_usd_monthly"].nil?
          out["budget_cap_usd_monthly"] = out["budget_cap_usd_monthly"].to_f
        end

        latency = out["latency_targets_ms"].is_a?(Hash) ? out["latency_targets_ms"].dup : {}
        latency["p99"] = latency["p99"]&.to_i unless latency["p99"].nil?
        out["latency_targets_ms"] = latency

        # (preferred_provider is normalized above, before the local-provider
        # region scrub that depends on its resolved TYPE.)

        # M3 "Run My Code" fields — string_or_nil. Coerce non-nil values to
        # String; leave explicit nils alone so the plan composer can branch
        # on `brief["repo_url"].present?`.
        %w[repo_url branch start_command runtime_hint].each do |key|
          out[key] = out[key].to_s if out[key].is_a?(String) || out[key].is_a?(Symbol)
          out[key] = nil if out[key].is_a?(String) && out[key].strip.empty?
        end
        out["runtime_hint"] = out["runtime_hint"].downcase if out["runtime_hint"].is_a?(String)

        out
      end

      # Resolve the LLM's free-text provider reference to a provider_type the
      # account actually has, or nil (IMP 019fe1e0-71b1).
      #
      # The extracted value was previously stringified and trusted. Observed
      # failure: an objective naming "the 'IPNode PVE' provider" yielded
      # 'pro_cloud' — a type absent from that account — which matched nothing in
      # PlanComposerService#resolve_provider_choice and degraded to the
      # clarification path. The more dangerous variant is a hallucinated type
      # that DOES match some other configured provider: that silently routes the
      # whole plan to the wrong cloud with no error and no operator signal.
      #
      # Accepts provider_type, display name, or id because operators write the
      # NAME; normalizes to provider_type, which is what the downstream matcher
      # compares against.
      def normalize_preferred_provider(raw)
        return nil if raw.blank?

        value = raw.to_s.strip
        return value if value.empty?
        # Core mode: no catalog to validate against. Nulling every value here
        # would be a regression, not a safety win.
        return value unless self.class.provider_catalog_available?

        providers = ::System::Provider.where(account_id: account.id, enabled: true).to_a
        # No providers configured is an existing, defined state ("legacy/test
        # path" per resolve_provider_choice) — nothing to validate against.
        return value if providers.empty?

        needle = value.downcase
        match = providers.find do |p|
          p.provider_type.to_s.downcase == needle ||
            p.name.to_s.downcase == needle ||
            p.id.to_s.downcase == needle
        end
        return match.provider_type.to_s if match

        # Deliberately NOT nulled. An unconfigured value and nil both reach the
        # same place downstream (resolve_provider_choice matches nothing and
        # falls through to clarification), so discarding it would change no
        # outcome while throwing away a real signal — the operator asked for
        # something they have not configured, which is worth keeping in the
        # brief and worth saying out loud. Whether that should instead become a
        # distinct "you asked for X, which isn't configured" response is a
        # product decision, not this defect's to make.
        Rails.logger.warn(
          "[IntentCaptureService] preferred_provider #{value.inspect} for " \
            "account=#{account&.id} matches no configured provider " \
            "#{providers.map { |p| [p.name, p.provider_type] }.inspect}; leaving it on the " \
            "brief — the composer will ask which provider to use."
        )
        value
      end

      def missing_fields_for(brief)
        REQUIRED_FIELDS.select { |field| field_blank?(brief, field) }
      end

      def field_blank?(brief, field)
        case field
        when :scale
          scale = brief["scale"]
          !scale.is_a?(Hash) || scale["initial"].blank? || scale["target"].blank?
        when :regions
          Array(brief["regions"]).empty?
        else
          brief[field.to_s].blank?
        end
      end

      def regex_confidence(text)
        # Multiple matches → higher confidence; clamp to [0.6, 0.95].
        match_count = text.scan(INTENT_KEYWORDS).size
        (0.6 + (0.1 * match_count)).clamp(0.6, 0.95)
      end

      # Surface the cost-cap state to capture/refine callers so the chat layer
      # can render UpgradeRequiredCard instead of pretending the LLM round-trip
      # succeeded.
      def cap_exceeded_attributes
        payload = @cap_exceeded_payload || {}
        {
          cap_exceeded: true,
          requires_upgrade: true,
          reason: "llm_cost_cap_exceeded",
          spent: payload[:spent],
          cap: payload[:cap]
        }
      end
    end
  end
end

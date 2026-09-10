# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # LLM PROVIDERS (`Ai::Provider`) as components.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # `Ai::Provider.for_account(account).platform_routable`.
      #
      # `Ai::Provider` has no terminated / archived / soft-deleted state: every
      # row is a provider somebody configured. What IS excluded is the synthetic
      # recording scope the `platform_routable` scope already names — the row
      # `Ai::ClaudeExport::ExecutionRecorder` files Claude Code executions
      # under. The platform holds no credential that could serve it and
      # `Ai::AgentModelSelector` will never route to it, so a status row for it
      # would be a permanently un-actionable red herring. Reusing the existing
      # scope rather than re-deriving the condition keeps the two definitions
      # from drifting.
      #
      # A DEACTIVATED provider (`is_active: false`) is NOT excluded: turning a
      # provider off is operator intent, which the ladder spells `held`, and an
      # operator who switched something off still wants to see it on the page.
      #
      # ── WHY HEALTH IS NOT REPORTED FOR A DEACTIVATED PROVIDER ───────────────
      # `#health_status` on an inactive provider answers from whatever stale
      # health metrics happen to be in metadata. Reporting `not_measured` there
      # would rank the component ABOVE `held` on the ladder (a gap outranks
      # intent), so every provider an operator deliberately switched off would
      # count as blindness in the rollup. So an inactive provider emits its
      # `Held` condition and no health claim at all — which is the honest
      # position: we are not measuring it, because it is off.
      #
      # ── NO KEY MATERIAL, EVER ───────────────────────────────────────────────
      # The credential condition COUNTS rows on the association. It never reads,
      # decrypts, logs or puts a credential anywhere near the conditions, the
      # evidence or the message.
      #
      # It counts `provider_credentials`, not `credentials`, and that is not a
      # style choice. `Ai::Provider` declares BOTH — but
      # `Ai::Provider::Configurable#credentials` is defined in a module included
      # after the association is generated, so it SHADOWS the association reader
      # and `provider.credentials` returns the first active credential's
      # DECRYPTED HASH, not a relation. Counting it would have counted the keys
      # in somebody's secret. The unshadowed `provider_credentials` association
      # is the only safe reader here.
      class AiProvider < Contributor
        include EnumConditions

        KIND = "ai_provider"

        HEALTH_TYPE = "Healthy"
        # The one Held token lives on Condition; a second copy here would be a
        # second thing to keep in step with the verdict mapping.
        HELD_TYPE   = Condition::HELD_TYPE

        # `Ai::Provider::HealthCheckable#health_status` — the four values that
        # method can return. Asserted against the method's own source in the
        # spec, so a fifth value added there turns the spec red instead of
        # quietly rendering as `UnknownStatus` in production.
        HEALTH_CONDITIONS = {
          "healthy" => {
            type: HEALTH_TYPE, status: true, reason: "HealthCheckPassed",
            message: "last provider health check succeeded"
          },
          "unhealthy" => {
            type: HEALTH_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "HealthCheckFailed",
            message: "provider health check is failing"
          },
          "unknown" => {
            type: HEALTH_TYPE, status: Condition::UNKNOWN, reason: "NeverChecked",
            message: "no provider health check has been recorded"
          },
          # Reachable only if `is_active` flips between the guard and this read.
          # Mapped anyway: a total table is the point.
          "inactive" => {
            type: HEALTH_TYPE, status: Condition::UNKNOWN, reason: "NotInService",
            message: "provider is deactivated; health is not measured"
          }
        }.freeze

        def kind = KIND

        def each_component(account)
          return if account.blank?

          ::Ai::Provider.for_account(account).platform_routable
                        .includes(:provider_credentials)
                        .find_each { |provider| yield provider }
        end

        def ref_for(provider) = provider.id.to_s

        def display_name_for(provider) = provider.name.presence || provider.slug

        def links_for(provider)
          [ { "label" => "Provider settings", "path" => "/app/ai/infrastructure/providers/#{provider.id}" } ]
        end

        def presentation
          { "icon" => "Plug", "label" => "AI Provider", "group_order" => 10 }
        end

        def conditions_for(provider)
          return [ held_condition(provider), credential_condition(provider) ] unless provider.is_active?

          [ held_condition(provider), health_condition(provider), credential_condition(provider) ]
        end

        # A provider depends on nothing this plane models. The upstream vendor
        # API is not a component: nobody here can act on it, and inventing a
        # node for it would put an un-actionable box on every operator's screen.
        def dependencies_for(_provider) = []

        # A3 registers no write actions in core (design §8, row A3).
        def actions_for(_provider) = []

        # The SOURCE's own measurement time, not the sweep's — a health check
        # from an hour ago must not read as fresh.
        def observed_at_for(provider)
          timestamp = provider.health_metrics["last_check_timestamp"]
          return nil if timestamp.blank?

          Time.zone.parse(timestamp.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        private

        def held_condition(provider)
          if provider.is_active?
            Condition.build(type: HELD_TYPE, status: false, reason: "Active",
                            message: "provider is enabled",
                            evidence: { "is_active" => true })
          else
            Condition.build(type: HELD_TYPE, status: true, reason: "Deactivated",
                            message: "provider was deactivated by an operator",
                            evidence: { "is_active" => false })
          end
        end

        def health_condition(provider)
          metrics = provider.health_metrics

          enum_condition(
            provider.health_status,
            table: HEALTH_CONDITIONS,
            unknown_type: HEALTH_TYPE,
            evidence: {
              "health_status" => provider.health_status.to_s,
              "provider_type" => provider.provider_type,
              "consecutive_failures" => metrics["consecutive_failures"],
              "last_check_timestamp" => metrics["last_check_timestamp"],
              "last_error" => provider.health_error&.to_s&.truncate(300)
            }.compact
          )
        end

        # Presence only. See "NO KEY MATERIAL, EVER" above.
        def credential_condition(provider)
          unless provider.requires_auth?
            return Condition.build(type: "Credentialed", status: true, reason: "AuthNotRequired",
                                   message: "provider requires no credential",
                                   evidence: { "requires_auth" => false })
          end

          # Preloaded by `each_component`, so this counts in memory. `count`
          # (not `size`) on the loaded array would issue a query per provider.
          count = provider.provider_credentials.count { |credential| credential.is_active? }
          if count.positive?
            Condition.build(type: "Credentialed", status: true, reason: "CredentialPresent",
                            message: "#{count} active credential#{'s' if count > 1}",
                            evidence: { "active_credential_count" => count })
          else
            Condition.build(type: "Credentialed", status: false,
                            severity: Condition::SEVERITY_DEGRADED, reason: "CredentialMissing",
                            message: "provider requires a credential and has no active one",
                            evidence: { "active_credential_count" => 0 })
          end
        end
      end
    end
  end
end

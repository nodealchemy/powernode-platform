# frozen_string_literal: true

module Api
  module V1
    module Platform
      # E8 — the operator door for alert-channel configuration (lead rulings
      # 2026-09-10).
      #
      # WRITE-ONLY CREDENTIALS. The three secrets (Slack webhook URL, alert
      # webhook URL, webhook token) go in and never come back out: every
      # response answers `configured: true|false` and nothing else. Clearing is
      # its own explicit action, so a blank field in an update is rejected
      # rather than read as "clear".
      #
      # REST ONLY. No MCP verb reads or writes any of this: secrets never
      # travel through MCP. Gated on settings.manage, with admin.access always
      # granting — the same gate as the site settings door.
      #
      # AUDITED. Every set, replace and clear writes an AuditLog row naming the
      # key and the actor; plain-setting changes record which names changed.
      # No row carries a value.
      #
      # FAILS CLOSED. When the credential store is selected but unreachable the
      # door answers 503 and neither reads nor writes anything.
      class AlertChannelsController < ApplicationController
        include AuditLogging

        before_action -> { require_admin_access("settings.manage") }

        AUDIT = {
          set: "platform.alert_channels.secret_set",
          replaced: "platform.alert_channels.secret_replaced",
          cleared: "platform.alert_channels.secret_cleared",
          settings: "platform.alert_channels.settings_updated"
        }.freeze

        # GET /api/v1/platform/alert_channels
        def show
          render_success(config_payload)
        rescue ::Security::SecretStore::BackendUnavailable
          render_store_unavailable
        end

        # PATCH /api/v1/platform/alert_channels
        #   { secrets: { slack_webhook_url: "https://..." },
        #     settings: { email: "ops@example.com", min_severity_slack: "warning" } }
        #
        # Validated as a whole before anything is written, so a bad field
        # cannot leave half an update behind.
        def update
          secrets = submitted(:secrets, channels::SECRET_KEYS)
          settings = submitted(:settings, channels::SETTING_NAMES)
          return render_error("Nothing to update", status: :unprocessable_content) if secrets.empty? && settings.empty?

          normalized = secrets.to_h { |key, value| [ key, channels.validate_secret!(key, value) ] }
          settings.each { |name, value| channels.validate_setting!(name, value) if value.to_s.strip.present? }
          # Probe the store BEFORE writing either kind of value, so an outage
          # answers 503 without a partial update.
          channels.secrets_status if normalized.any?

          changed = channels.update_settings!(settings)
          audit(AUDIT[:settings], channels::SETTINGS_AUDIT_ID, changed: changed) if changed.any?

          normalized.each do |key, value|
            outcome = channels.write_secret!(key, value)
            audit(AUDIT.fetch(outcome), key, secret_key: key)
          end

          render_success(config_payload)
        rescue ::Monitoring::AlertChannels::InvalidSetting => e
          render_error(e.message, status: :unprocessable_content)
        rescue ::Security::SecretStore::BackendUnavailable
          render_store_unavailable
        end

        # DELETE /api/v1/platform/alert_channels/secrets/:secret_key
        def clear_secret
          key = params[:secret_key].to_s
          had_value = channels.clear_secret!(key)
          audit(AUDIT[:cleared], key, secret_key: key, had_value: had_value)

          render_success(config_payload)
        rescue ::Monitoring::AlertChannels::InvalidSetting => e
          render_error(e.message, status: :unprocessable_content)
        rescue ::Security::SecretStore::BackendUnavailable
          render_store_unavailable
        end

        private

        # Fully qualified throughout: Api::V1::Platform lexically shadows the
        # top-level Platform namespace, and the same hazard applies to any
        # other bare constant resolved from in here.
        def channels
          ::Monitoring::AlertChannels
        end

        def config_payload
          {
            secrets: channels.secrets_status,
            settings: channels.settings,
            defaults: channels.defaults,
            severities: channels.severities
          }
        end

        # Unknown keys are REJECTED, not silently dropped: a misspelled
        # credential name that vanished would read as a successful save.
        def submitted(group, allowed)
          raw = params[group]
          return {} if raw.blank?
          raise ::Monitoring::AlertChannels::InvalidSetting, "#{group} must be an object" unless raw.respond_to?(:keys)

          unknown = raw.keys.map(&:to_s) - allowed
          raise ::Monitoring::AlertChannels::InvalidSetting, "unknown #{group}: #{unknown.join(', ')}" if unknown.any?

          raw.permit(*allowed).to_h
        end

        def audit(action, audit_id, **metadata)
          log_audit_event(action, channels::AuditRef.new(audit_id),
                          metadata: metadata.merge(scope: channels::SECRET_SCOPE))
        end

        def render_store_unavailable
          render_error("The credential store is unavailable (secret_store_unavailable); nothing was read or written.",
                       status: :service_unavailable)
        end
      end
    end
  end
end

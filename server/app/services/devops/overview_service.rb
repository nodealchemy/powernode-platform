# frozen_string_literal: true

module Devops
  class OverviewService
    include SourceControlMetrics
    include CiCdMetrics
    include InfrastructureMetrics

    attr_reader :account

    CACHE_TTL = 5.minutes

    def initialize(account:)
      @account = account
    end

    def generate(force_refresh: false)
      cache_key = "devops:overview:#{account.id}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, force: force_refresh) do
        sc = generate_source_control_metrics
        cicd = generate_ci_cd_metrics
        infra = generate_infrastructure_metrics
        conns = generate_connections_metrics

        {
          source_control: sc,
          ci_cd: cicd,
          infrastructure: infra,
          connections: conns,
          alerts: generate_alerts(sc, cicd, infra, conns)
        }
      end
    end

    def self.invalidate_cache(account_id)
      Rails.cache.delete("devops:overview:#{account_id}")
    end

    private

    def generate_connections_metrics
      {
        integrations: integration_metrics,
        webhooks: webhook_metrics,
        api_keys: api_key_metrics
      }
    end

    def integration_metrics
      instances = account.devops_integration_instances

      {
        total: instances.count,
        active: instances.active.count,
        healthy: instances.healthy.count,
        errored: instances.errored.count
      }
    end

    def webhook_metrics
      endpoints = account.webhook_endpoints
      events_today = account.webhook_events.where(
        created_at: Time.current.beginning_of_day..Time.current.end_of_day
      )

      {
        total: endpoints.count,
        processed_today: events_today.processed.count,
        failed_today: events_today.failed.count
      }
    end

    def api_key_metrics
      {
        total: account.api_keys.count
      }
    end

    def generate_alerts(sc, cicd, infra, conns)
      alerts = []

      if sc[:credentials][:expires_soon] > 0
        alerts << {
          level: "warning",
          message: "#{sc[:credentials][:expires_soon]} credential(s) expiring soon",
          section: "source_control"
        }
      end

      if sc[:credentials][:unhealthy] > 0
        alerts << {
          level: "error",
          message: "#{sc[:credentials][:unhealthy]} unhealthy credential(s)",
          section: "source_control"
        }
      end

      if cicd[:runners][:offline] > 0
        alerts << {
          level: "warning",
          message: "#{cicd[:runners][:offline]} runner(s) offline",
          section: "ci_cd"
        }
      end

      if conns[:integrations][:errored] > 0
        alerts << {
          level: "error",
          message: "#{conns[:integrations][:errored]} integration(s) with errors",
          section: "connections"
        }
      end

      if conns[:webhooks][:failed_today] > 0
        alerts << {
          level: "warning",
          message: "#{conns[:webhooks][:failed_today]} failed webhook delivery(s) today",
          section: "connections"
        }
      end

      if infra[:containers][:failed] > 0
        alerts << {
          level: "warning",
          message: "#{infra[:containers][:failed]} failed container execution(s)",
          section: "infrastructure"
        }
      end

      alerts
    end
  end
end

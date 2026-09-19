# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class DiscoveryController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          # IMP-80e613fb9c43 review round 2: mcp_servers/docker_hosts/
          # swarm_clusters all looked the account up by the caller-supplied
          # `account_id` param with no tenancy scoping, so any worker-mTLS
          # caller could read another account's infrastructure by passing
          # that account's id. All three now resolve `@account` through the
          # SAME anchor (WorkerTenancy#account_scope, keyed on the
          # authenticated worker's own account_id, never a param), so a
          # cross-account id 404s uniformly rather than three near-identical
          # inline `Account.find` calls independently drifting.
          before_action :set_discovery_account, only: [ :mcp_servers, :docker_hosts, :swarm_clusters ]

          # GET /api/v1/internal/ai/discovery/mcp_servers
          #
          # `capabilities` is sliced to `tools` only — the sole key
          # AiDiscoveryScanJob (worker/app/jobs/ai_discovery_scan_job.rb)
          # reads from this response — rather than returned raw (config
          # secrets, last_error, allow_network, ... all live in the same
          # jsonb column).
          def mcp_servers
            servers = @account.mcp_servers.map do |s|
              { id: s.id, name: s.name, capabilities: (s.capabilities || {}).slice("tools"), status: s.status }
            end
            render_success(servers)
          end

          # GET /api/v1/internal/ai/discovery/docker_hosts
          #
          # Fields checked against AiDiscoveryScanJob#scan_docker_hosts,
          # which reads only id/name/status(+containers[name,status]) —
          # already the exact shape returned here, so no field slicing was
          # needed, only the tenancy scope. Devops::DockerHost's TLS
          # material lives in `encrypted_tls_credentials`, never touched by
          # this hand-picked hash.
          #
          # review round 3: Devops::DockerContainer has no `status` column
          # (`c.status` raised NoMethodError, uncaught, for any host with
          # real containers — Docker discovery never worked at all past an
          # empty host). Mapped to `state`: the validated STATES-enumerated
          # column every model predicate/scope already treats as the
          # container's canonical status (`status_text` is an untyped
          # mirror of Docker's human-readable "Up 2 hours" string, not a
          # status value). AiDiscoveryScanJob only passes
          # `container['status']` through into its own payload for
          # display — it never branches on the value — so `state` (e.g.
          # "running", "exited") is what a caller here actually needs.
          def docker_hosts
            hosts = @account.devops_docker_hosts.includes(:docker_containers).map do |h|
              {
                id: h.id, name: h.name, status: h.status,
                containers: h.docker_containers.map { |c| { name: c.name, status: c.state } }
              }
            end
            render_success(hosts)
          end

          # GET /api/v1/internal/ai/discovery/swarm_clusters
          #
          # Same check as docker_hosts: AiDiscoveryScanJob#scan_swarm_clusters
          # reads only id/name/status(+services[name,status]); Devops::
          # SwarmCluster's join-token/TLS material lives in
          # `encrypted_tls_credentials`, never touched here.
          #
          # review round 3: Devops::SwarmService has no `name` or `status`
          # method/column at all (`s.name`/`s.status` raised NoMethodError,
          # uncaught, for any cluster with real services — Swarm discovery
          # never worked past an empty cluster). `name` maps to
          # `service_name` (the model's own name field). `status` has no
          # direct column — a swarm service's health is replica counts,
          # not a single-word state like a container's — so it's derived
          # from the model's pre-existing `#healthy?` predicate
          # ("healthy"/"unhealthy"), the same two-value shape every other
          # status field in this codebase uses, rather than inventing a
          # new concept. AiDiscoveryScanJob only passes `service['status']`
          # through for display, never branching on it.
          def swarm_clusters
            clusters = @account.devops_swarm_clusters.includes(:swarm_services).map do |c|
              {
                id: c.id, name: c.name, status: c.status,
                services: c.swarm_services.map { |s| { name: s.service_name, status: s.healthy? ? "healthy" : "unhealthy" } }
              }
            end
            render_success(clusters)
          end

          # POST /api/v1/internal/ai/discovery/:scan_id/complete
          #
          # This action has no `account_id` param — it names a row
          # (Ai::DiscoveryResult) that itself belongs to an account, so it
          # resolves through the same worker_account_id anchor via the
          # column directly (WorkerTenancy's own "scope by the column, not
          # the association" guidance), rather than through account_scope's
          # Account-shaped lookup used by the three GET actions above.
          def complete
            result = ::Ai::DiscoveryResult.where(account_id: worker_account_id).find_by!(scan_id: params[:scan_id])
            result.complete!(
              agents: params[:agents] || [],
              connections: params[:connections] || [],
              tools: params[:tools] || [],
              recommendations: params[:recommendations] || []
            )

            render_success(result.scan_summary)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Discovery Result")
          end

          # POST /api/v1/internal/ai/discovery/:scan_id/failed
          #
          # review round 3: same unscoped `find_by!(scan_id: ...)` gap as
          # `complete` (same file, same shape) — same fix.
          def failed
            result = ::Ai::DiscoveryResult.where(account_id: worker_account_id).find_by!(scan_id: params[:scan_id])
            result.fail!(params[:error_message] || "Unknown error")

            render_success(result.scan_summary)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Discovery Result")
          end

          private

          def set_discovery_account
            @account = account_scope.find(params[:account_id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end
        end
      end
    end
  end
end

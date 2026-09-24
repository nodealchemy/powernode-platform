# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      module DockerContextResolvable
        extend ActiveSupport::Concern

        # PROVIDER-SAFETY CONTRACT (IMP-5ed95e651b80): every ArgumentError /
        # ActiveRecord::RecordNotFound this concern raises is static
        # app-authored text, at most interpolating a resource name/id/count
        # scoped to the calling account (never raw driver/framework text) —
        # audited exhaustively when every one of this concern's seven
        # includers (docker_cluster_tool.rb, docker_container_tool.rb,
        # docker_host_tool.rb, docker_image_tool.rb,
        # docker_network_volume_tool.rb, docker_service_tool.rb,
        # docker_stack_tool.rb) was found to have no OTHER raise site for
        # either class. Those tools' rescue arms route ActiveRecord::
        # RecordNotFound through BaseTool#not_found_result (IMP-f6f80b585b19)
        # rather than forwarding e.message directly — today that's a no-op
        # for THIS concern's own raises (raise_not_found never sets e.model/
        # e.id, so the safe hand-authored text passes through unchanged, and
        # the helper's WHERE-stripping fallback is a no-op on text that never
        # carried that suffix). That protects a REAL scoped `.find` added
        # directly to one of these tools (Rails sets e.model/e.id on that
        # raise, so the helper authors the message from those instead of
        # forwarding text). It does NOT protect a future raise_not_found
        # call, or any other hand-raise here, that wraps an inner error's
        # (e.g. a driver/PG exception's) message — that raise has no model/id
        # to key off, so the helper passes its text through unchanged, `[WHERE`
        # suffix and all if present. Any new raise site here still must
        # author its own safe, static (or caller-echo-only) text — sanitize
        # before raising, not after.
        private

        # Resolve a Docker host by identifier (UUID, slug, or name).
        # When identifier is nil, auto-selects if exactly one connected host exists.
        def resolve_host(identifier = nil)
          scope = account.devops_docker_hosts

          if identifier.present?
            scope.find_by(id: identifier) ||
              scope.find_by(slug: identifier) ||
              scope.find_by(name: identifier) ||
              raise_not_found("Docker host", identifier)
          else
            connected = scope.connected
            case connected.count
            when 0
              raise_not_found("Docker host", nil, "No connected Docker hosts found")
            when 1
              connected.first
            else
              raise ArgumentError, "Multiple Docker hosts found (#{connected.count}). Specify host_id to disambiguate: #{connected.pluck(:name).join(', ')}"
            end
          end
        end

        # Resolve a Swarm cluster by identifier (UUID, slug, or name).
        # When identifier is nil, auto-selects if exactly one connected cluster exists.
        def resolve_cluster(identifier = nil)
          scope = account.devops_swarm_clusters

          if identifier.present?
            scope.find_by(id: identifier) ||
              scope.find_by(slug: identifier) ||
              scope.find_by(name: identifier) ||
              raise_not_found("Swarm cluster", identifier)
          else
            connected = scope.connected
            case connected.count
            when 0
              raise_not_found("Swarm cluster", nil, "No connected Swarm clusters found")
            when 1
              connected.first
            else
              raise ArgumentError, "Multiple Swarm clusters found (#{connected.count}). Specify cluster_id to disambiguate: #{connected.pluck(:name).join(', ')}"
            end
          end
        end

        # Resolve a container on a host by UUID, docker_container_id, or name.
        def resolve_container(host, identifier)
          host.docker_containers.find_by(id: identifier) ||
            host.docker_containers.find_by(docker_container_id: identifier) ||
            host.docker_containers.find_by(name: identifier) ||
            raise_not_found("container", identifier)
        end

        # Resolve a Swarm service on a cluster by UUID, docker_service_id, or service_name.
        def resolve_service(cluster, identifier)
          cluster.swarm_services.find_by(id: identifier) ||
            cluster.swarm_services.find_by(docker_service_id: identifier) ||
            cluster.swarm_services.find_by(service_name: identifier) ||
            raise_not_found("service", identifier)
        end

        # Resolve a Swarm stack on a cluster by UUID, slug, or name.
        def resolve_stack(cluster, identifier)
          cluster.swarm_stacks.find_by(id: identifier) ||
            cluster.swarm_stacks.find_by(slug: identifier) ||
            cluster.swarm_stacks.find_by(name: identifier) ||
            raise_not_found("stack", identifier)
        end

        # Resolve a Swarm node on a cluster by UUID, docker_node_id, or hostname.
        def resolve_node(cluster, identifier)
          cluster.swarm_nodes.find_by(id: identifier) ||
            cluster.swarm_nodes.find_by(docker_node_id: identifier) ||
            cluster.swarm_nodes.find_by(hostname: identifier) ||
            raise_not_found("node", identifier)
        end

        def raise_not_found(resource_type, identifier, message = nil)
          msg = message || "#{resource_type} not found: #{identifier}"
          raise ActiveRecord::RecordNotFound, msg
        end
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      # The principal whose Mcp::ToolCatalog a catalog-reading tool may answer
      # from. Shared by platform.describe_tool and platform.discover_tools, so the
      # two doors onto the catalog cannot disagree about what a caller may see.
      module CatalogPrincipal
        extend ActiveSupport::Concern

        private

        # The principal whose catalog this call may read, or nil for a user/agent
        # caller (unrestricted, exactly like tools/list).
        #
        # WHY THIS EXISTS. Restricted principals — instance (mTLS node cert) and
        # federation — are DEFAULT-DENY (Mcp::Principal#restricted?): tools/list
        # advertises only their granted patterns. Grants are globs in practice
        # ("platform.*", "platform.system_*_read"), so one of them can easily
        # match `platform.describe_tool` itself. Without this scoping, that one
        # grant would read the full entry — description, schemas, annotations —
        # of every tool the principal was NOT granted, and #nearest would
        # enumerate their names. The controller's may_invoke? gate authorizes the
        # CALL; only this scopes the RESULT.
        #
        # `instance_authorized` is set by McpPlatformToolRegistrar for EVERY
        # restricted principal (streamable_http_controller.rb passes
        # `current_mcp_principal&.restricted?`), while `node_instance` arrives
        # only for the instance kind. A restricted caller we cannot resolve a
        # grant for (federation, whose partner row never reaches the tool) gets a
        # principal that grants nothing — fail closed, never the full catalog.
        def catalog_principal
          return nil unless instance_authorized?

          if node_instance
            ::Mcp::Principal.new(kind: :instance, account: account,
                                 node_instance: node_instance, subject_id: node_instance.id)
          else
            ::Mcp::Principal.new(kind: :federation, account: account, subject_id: nil)
          end
        end
      end
    end
  end
end

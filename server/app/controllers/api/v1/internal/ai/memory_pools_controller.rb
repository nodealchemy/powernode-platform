# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class MemoryPoolsController < InternalBaseController
          # GET /api/v1/internal/ai/memory_pools/expired
          def expired
            pools = ::Ai::MemoryPool.expired.map(&:pool_summary)
            render_success(pools)
          end

          # DELETE /api/v1/internal/ai/memory_pools/:id
          def destroy
            pool = ::Ai::MemoryPool.find(params[:id])
            pool.destroy!
            render_success({ message: "Pool deleted", id: pool.id })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Memory Pool")
          end

          # POST /api/v1/internal/ai/memory_pools/purge_expired
          # Bulk-delete all expired pools in a single call, returning the count and total bytes
          # freed. Collapses the worker's per-pool DELETE N+1 (one round-trip per expired pool)
          # into one request. The same set is counted and destroyed (no TOCTOU drift).
          def purge_expired
            pools = ::Ai::MemoryPool.expired.to_a
            pools_cleaned = pools.size
            bytes_freed = pools.sum { |p| p.data_size_bytes.to_i }
            ::Ai::MemoryPool.where(id: pools.map(&:id)).destroy_all if pools.any?
            render_success({ pools_cleaned: pools_cleaned, bytes_freed: bytes_freed })
          end

          # POST /api/v1/internal/ai/memory_pools/cleanup_results
          def cleanup_results
            render_success({
              message: "Cleanup results recorded",
              pools_cleaned: params[:pools_cleaned] || 0,
              bytes_freed: params[:bytes_freed] || 0
            })
          end
        end
      end
    end
  end
end

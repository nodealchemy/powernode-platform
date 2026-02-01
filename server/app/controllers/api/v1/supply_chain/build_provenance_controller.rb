# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class BuildProvenanceController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:verify_reproducibility]
        before_action :set_provenance, only: [:show, :verify_reproducibility]

        # GET /api/v1/supply_chain/build_provenance
        def index
          @provenances = current_account.supply_chain_build_provenances
                                        .includes(:attestation)
                                        .order(created_at: :desc)

          @provenances = @provenances.where(builder_id: params[:builder_id]) if params[:builder_id].present?
          @provenances = @provenances.where(reproducible: true) if params[:reproducible] == "true"

          if params[:source_repository].present?
            @provenances = @provenances.where(source_repository: params[:source_repository])
          end

          @provenances = paginate(@provenances)

          render_success(
            { build_provenances: @provenances.map { |p| serialize_provenance(p) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/build_provenance/:id
        def show
          render_success({ build_provenance: serialize_provenance(@provenance, include_details: true) })
        end

        # POST /api/v1/supply_chain/build_provenance/:id/verify_reproducibility
        def verify_reproducibility
          if @provenance.verification_in_progress?
            return render_error("Verification already in progress", status: :unprocessable_content)
          end

          updated_metadata = (@provenance.metadata || {}).merge(
            "reproducibility_status" => "verifying",
            "reproducibility_started_at" => Time.current.iso8601
          )
          @provenance.update!(metadata: updated_metadata)

          # Queue the verification job
          ::SupplyChain::ReproducibilityVerificationJob.perform_later(@provenance.id, current_user.id)

          render_success(
            { build_provenance: serialize_provenance(@provenance) },
            message: "Reproducibility verification started"
          )
        rescue StandardError => e
          render_error("Failed to start verification: #{e.message}", status: :unprocessable_content)
        end

        private

        def set_provenance
          @provenance = current_account.supply_chain_build_provenances.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Build provenance not found", status: :not_found)
        end

        def serialize_provenance(provenance, include_details: false)
          data = {
            id: provenance.id,
            builder_id: provenance.builder_id,
            builder_version: provenance.builder_version,
            source_repository: provenance.source_repository,
            source_commit: provenance.source_commit,
            source_branch: provenance.source_branch,
            build_started_at: provenance.build_started_at,
            build_finished_at: provenance.build_finished_at,
            build_duration_ms: provenance.build_duration_ms,
            reproducible: provenance.reproducible,
            reproducibility_verified_at: provenance.reproducibility_verified_at,
            reproducibility_status: provenance.metadata&.dig("reproducibility_status"),
            attestation_id: provenance.attestation_id,
            created_at: provenance.created_at
          }

          if include_details
            data[:build_config] = provenance.build_config
            data[:materials] = provenance.materials
            data[:environment] = provenance.environment
            data[:invocation] = provenance.invocation
            data[:reproducibility_hash] = provenance.reproducibility_hash
            data[:metadata] = provenance.metadata
          end

          data
        end
      end
    end
  end
end

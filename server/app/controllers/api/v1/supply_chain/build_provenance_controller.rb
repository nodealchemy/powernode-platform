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
                                        .includes(:attestation, :repository)
                                        .order(created_at: :desc)

          @provenances = @provenances.where(build_type: params[:build_type]) if params[:build_type].present?
          @provenances = @provenances.where(verified: true) if params[:verified] == "true"
          @provenances = @provenances.where(reproducible: true) if params[:reproducible] == "true"

          if params[:repository_id].present?
            @provenances = @provenances.where(repository_id: params[:repository_id])
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
            return render_error("Verification already in progress", status: :unprocessable_entity)
          end

          @provenance.update!(
            reproducibility_status: "verifying",
            reproducibility_started_at: Time.current
          )

          # Queue the verification job
          ::SupplyChain::ReproducibilityVerificationJob.perform_later(@provenance.id, current_user.id)

          render_success(
            { build_provenance: serialize_provenance(@provenance) },
            message: "Reproducibility verification started"
          )
        rescue StandardError => e
          render_error("Failed to start verification: #{e.message}", status: :unprocessable_entity)
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
            provenance_id: provenance.provenance_id,
            build_type: provenance.build_type,
            builder_id: provenance.builder_id,
            builder_version: provenance.builder_version,
            build_started_at: provenance.build_started_at,
            build_finished_at: provenance.build_finished_at,
            invocation_id: provenance.invocation_id,
            verified: provenance.verified,
            reproducible: provenance.reproducible,
            reproducibility_status: provenance.reproducibility_status,
            slsa_level: provenance.slsa_level,
            attestation_id: provenance.attestation_id,
            repository: provenance.repository ? {
              id: provenance.repository.id,
              name: provenance.repository.name,
              full_name: provenance.repository.full_name
            } : nil,
            created_at: provenance.created_at
          }

          if include_details
            data[:build_config] = provenance.build_config
            data[:materials] = provenance.materials
            data[:environment] = provenance.environment
            data[:parameters] = provenance.parameters
            data[:reproducibility_started_at] = provenance.reproducibility_started_at
            data[:reproducibility_completed_at] = provenance.reproducibility_completed_at
            data[:reproducibility_logs] = provenance.reproducibility_logs
            data[:verification_errors] = provenance.verification_errors
            data[:metadata] = provenance.metadata
          end

          data
        end
      end
    end
  end
end

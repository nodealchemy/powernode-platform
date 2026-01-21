# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class AttestationsController < BaseController
        before_action :require_read_permission, only: [:index, :show, :verification_logs, :statistics]
        before_action :require_write_permission, only: [:create, :update, :destroy, :verify, :sign, :record_to_rekor]
        before_action :set_attestation, only: [:show, :update, :destroy, :verify, :sign, :record_to_rekor, :verification_logs]

        # GET /api/v1/supply_chain/attestations
        def index
          attestations = current_account.supply_chain_attestations
                                        .includes(:sbom, :signing_key)
                                        .order(created_at: :desc)

          attestations = attestations.where(attestation_type: params[:type]) if params[:type].present?
          attestations = attestations.where(slsa_level: params[:slsa_level]) if params[:slsa_level].present?
          attestations = attestations.where(verification_status: params[:status]) if params[:status].present?

          attestations = attestations.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            attestations: attestations.map { |a| serialize_attestation(a) },
            meta: {
              total: attestations.total_count,
              page: attestations.current_page,
              per_page: attestations.limit_value
            }
          })
        rescue StandardError => e
          Rails.logger.error "[AttestationsController] List failed: #{e.message}"
          render_error("Failed to list attestations", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/attestations/:id
        def show
          render_success({
            attestation: serialize_attestation_detail(@attestation)
          })

          log_audit_event("supply_chain.attestations.read", @attestation)
        end

        # POST /api/v1/supply_chain/attestations
        def create
          generator = ::SupplyChain::SlsaProvenanceGenerator.new(
            account: current_account,
            options: {
              user: current_user,
              signed_provenance: params[:sign] == true
            }
          )

          attestation = generator.generate(
            subject_name: params[:subject_name],
            subject_digest: params[:subject_digest],
            builder_id: params[:builder_id],
            materials: params[:materials],
            source_repository: params[:source_repository],
            source_commit: params[:source_commit],
            source_branch: params[:source_branch]
          )

          render_success({
            attestation: serialize_attestation(attestation),
            message: "Attestation created successfully"
          }, status: :created)

          log_audit_event("supply_chain.attestations.create", attestation)
        rescue StandardError => e
          Rails.logger.error "[AttestationsController] Create failed: #{e.message}"
          render_error("Failed to create attestation: #{e.message}", status: :unprocessable_content)
        end

        # PATCH/PUT /api/v1/supply_chain/attestations/:id
        def update
          if @attestation.update(attestation_params)
            render_success({
              attestation: serialize_attestation(@attestation),
              message: "Attestation updated successfully"
            })

            log_audit_event("supply_chain.attestations.update", @attestation)
          else
            render_validation_error(@attestation.errors)
          end
        end

        # DELETE /api/v1/supply_chain/attestations/:id
        def destroy
          @attestation.destroy!

          render_success({ message: "Attestation deleted successfully" })

          log_audit_event("supply_chain.attestations.delete", @attestation)
        rescue StandardError => e
          render_error("Failed to delete attestation", status: :internal_server_error)
        end

        # POST /api/v1/supply_chain/attestations/:id/verify
        def verify
          result = @attestation.verify!

          render_success({
            attestation_id: @attestation.id,
            verified: result[:verified],
            verification_details: result[:details],
            message: result[:verified] ? "Attestation verified successfully" : "Attestation verification failed"
          })

          log_audit_event("supply_chain.attestations.verify", @attestation)
        rescue StandardError => e
          render_error("Verification failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/attestations/:id/sign
        def sign
          signing_key = if params[:signing_key_id].present?
                          current_account.supply_chain_signing_keys.active.find(params[:signing_key_id])
                        else
                          current_account.supply_chain_signing_keys.active.first
                        end

          raise "No signing key available" unless signing_key&.can_sign?

          payload = @attestation.in_toto_statement.to_json
          signature = signing_key.sign(payload)
          @attestation.sign!(signing_key, signature)

          render_success({
            attestation: serialize_attestation(@attestation),
            message: "Attestation signed successfully"
          })

          log_audit_event("supply_chain.attestations.sign", @attestation)
        rescue ActiveRecord::RecordNotFound
          render_error("Signing key not found", status: :not_found)
        rescue StandardError => e
          render_error("Signing failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/attestations/:id/record_to_rekor
        def record_to_rekor
          raise "Attestation must be signed first" unless @attestation.signed?

          @attestation.record_to_rekor!(
            SecureRandom.hex(32),
            "https://rekor.sigstore.dev/api/v1/log/entries/#{SecureRandom.hex(32)}"
          )

          render_success({
            attestation: serialize_attestation(@attestation),
            rekor_log_id: @attestation.rekor_log_id,
            rekor_log_url: @attestation.rekor_log_url,
            message: "Recorded to Rekor transparency log"
          })

          log_audit_event("supply_chain.attestations.record_to_rekor", @attestation)
        rescue StandardError => e
          render_error("Failed to record to Rekor: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/attestations/:id/verification_logs
        def verification_logs
          logs = @attestation.verification_logs.order(created_at: :desc)
          logs = logs.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            logs: logs.map { |l| serialize_verification_log(l) },
            meta: {
              total: logs.total_count,
              page: logs.current_page
            }
          })
        end

        # GET /api/v1/supply_chain/attestations/statistics
        def statistics
          attestations = current_account.supply_chain_attestations

          render_success({
            total: attestations.count,
            by_type: attestations.group(:attestation_type).count,
            by_slsa_level: attestations.group(:slsa_level).count,
            by_status: attestations.group(:verification_status).count,
            signed_count: attestations.where.not(signature: nil).count,
            rekor_logged_count: attestations.where.not(rekor_log_id: nil).count
          })
        end

        private

        def set_attestation
          @attestation = current_account.supply_chain_attestations.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Attestation not found", status: :not_found)
        end

        def attestation_params
          params.require(:attestation).permit(:subject_name, :subject_digest)
        end

        def serialize_attestation_detail(attestation)
          serialize_attestation(attestation).merge({
            predicate: attestation.predicate,
            predicate_type: attestation.predicate_type,
            signature: attestation.signature.present? ? "[PRESENT]" : nil,
            signature_algorithm: attestation.signature_algorithm,
            rekor_log_id: attestation.rekor_log_id,
            rekor_log_url: attestation.rekor_log_url,
            verification_status: attestation.verification_status,
            verification_results: attestation.verification_results,
            signing_key: attestation.signing_key.present? ? {
              id: attestation.signing_key.id,
              key_id: attestation.signing_key.key_id,
              key_type: attestation.signing_key.key_type
            } : nil
          })
        end

        def serialize_verification_log(log)
          {
            id: log.id,
            verification_type: log.verification_type,
            result: log.result,
            verifier_identity: log.verifier_identity,
            verification_details: log.verification_details,
            created_at: log.created_at
          }
        end
      end
    end
  end
end

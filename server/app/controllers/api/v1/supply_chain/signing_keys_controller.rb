# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class SigningKeysController < BaseController
        before_action :set_signing_key, only: [:show, :update, :destroy, :rotate, :revoke, :public_key]

        # GET /api/v1/supply_chain/signing_keys
        def index
          @signing_keys = current_account.supply_chain_signing_keys
                                         .order(created_at: :desc)

          @signing_keys = @signing_keys.where(status: params[:status]) if params[:status].present?
          @signing_keys = @signing_keys.where(key_type: params[:key_type]) if params[:key_type].present?

          @signing_keys = paginate(@signing_keys)

          render_success(
            signing_keys: @signing_keys.map { |key| serialize_signing_key(key) },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/signing_keys/:id
        def show
          render_success(signing_key: serialize_signing_key(@signing_key, include_details: true))
        end

        # POST /api/v1/supply_chain/signing_keys
        def create
          @signing_key = current_account.supply_chain_signing_keys.build(signing_key_params)
          @signing_key.created_by = current_user

          if @signing_key.save
            SupplyChainChannel.broadcast_signing_key_created(@signing_key)
            render_success(signing_key: serialize_signing_key(@signing_key), status: :created)
          else
            render_error(@signing_key.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/signing_keys/:id
        def update
          if @signing_key.update(signing_key_update_params)
            render_success(signing_key: serialize_signing_key(@signing_key))
          else
            render_error(@signing_key.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/signing_keys/:id
        def destroy
          if @signing_key.attestations.exists?
            render_error("Cannot delete signing key with existing attestations", status: :unprocessable_entity)
          else
            @signing_key.destroy
            render_success(message: "Signing key deleted")
          end
        end

        # POST /api/v1/supply_chain/signing_keys/:id/rotate
        def rotate
          new_key = @signing_key.rotate!

          SupplyChainChannel.broadcast_signing_key_rotated(@signing_key, new_key)

          render_success(
            old_key: serialize_signing_key(@signing_key),
            new_key: serialize_signing_key(new_key),
            message: "Key rotated successfully"
          )
        rescue StandardError => e
          render_error("Failed to rotate key: #{e.message}", status: :unprocessable_entity)
        end

        # POST /api/v1/supply_chain/signing_keys/:id/revoke
        def revoke
          reason = params[:reason] || "Manual revocation"

          @signing_key.revoke!(reason: reason)

          SupplyChainChannel.broadcast_signing_key_revoked(@signing_key)

          render_success(
            signing_key: serialize_signing_key(@signing_key),
            message: "Key revoked"
          )
        rescue StandardError => e
          render_error("Failed to revoke key: #{e.message}", status: :unprocessable_entity)
        end

        # GET /api/v1/supply_chain/signing_keys/:id/public_key
        def public_key
          render_success(
            key_id: @signing_key.key_id,
            public_key: @signing_key.public_key,
            key_type: @signing_key.key_type,
            algorithm: @signing_key.algorithm
          )
        end

        private

        def set_signing_key
          @signing_key = current_account.supply_chain_signing_keys.find(params[:id])
        end

        def signing_key_params
          params.require(:signing_key).permit(
            :name, :description, :key_type, :algorithm,
            :kms_provider, :kms_key_uri, :oidc_issuer, :oidc_subject,
            :expires_at, metadata: {}
          )
        end

        def signing_key_update_params
          params.require(:signing_key).permit(:name, :description, :expires_at, metadata: {})
        end

        def serialize_signing_key(key, include_details: false)
          data = {
            id: key.id,
            key_id: key.key_id,
            name: key.name,
            description: key.description,
            key_type: key.key_type,
            algorithm: key.algorithm,
            status: key.status,
            kms_provider: key.kms_provider,
            created_at: key.created_at,
            expires_at: key.expires_at,
            rotated_at: key.rotated_at,
            revoked_at: key.revoked_at
          }

          if include_details
            data[:public_key] = key.public_key
            data[:attestation_count] = key.attestations.count
            data[:metadata] = key.metadata
          end

          data
        end
      end
    end
  end
end

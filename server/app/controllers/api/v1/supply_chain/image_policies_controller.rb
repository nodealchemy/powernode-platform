# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ImagePoliciesController < BaseController
        before_action :set_image_policy, only: [:show, :update, :destroy, :evaluate]

        # GET /api/v1/supply_chain/image_policies
        def index
          @policies = current_account.supply_chain_image_policies
                                     .includes(:created_by)
                                     .order(created_at: :desc)

          @policies = @policies.where(is_active: true) if params[:active_only] == "true"
          @policies = @policies.where(policy_type: params[:policy_type]) if params[:policy_type].present?

          @policies = paginate(@policies)

          render_success(
            image_policies: @policies.map { |p| serialize_policy(p) },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/image_policies/:id
        def show
          render_success(image_policy: serialize_policy(@policy, include_details: true))
        end

        # POST /api/v1/supply_chain/image_policies
        def create
          @policy = current_account.supply_chain_image_policies.build(policy_params)
          @policy.created_by = current_user

          if @policy.save
            render_success(image_policy: serialize_policy(@policy), status: :created)
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/image_policies/:id
        def update
          if @policy.update(policy_params)
            render_success(image_policy: serialize_policy(@policy))
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/image_policies/:id
        def destroy
          @policy.destroy
          render_success(message: "Image policy deleted")
        end

        # POST /api/v1/supply_chain/image_policies/:id/evaluate
        def evaluate
          image = current_account.supply_chain_container_images.find(params[:image_id])

          result = @policy.evaluate(image)

          if result[:violations].any?
            SupplyChainChannel.broadcast_policy_violation(
              current_account,
              policy: @policy,
              image: image,
              violations: result[:violations]
            )
          end

          render_success(
            policy_id: @policy.id,
            policy_name: @policy.name,
            image_id: image.id,
            image_reference: image.full_reference,
            compliant: result[:compliant],
            enforcement_action: result[:enforcement_action],
            violations: result[:violations]
          )
        end

        private

        def set_image_policy
          @policy = current_account.supply_chain_image_policies.find(params[:id])
        end

        def policy_params
          params.require(:image_policy).permit(
            :name, :description, :policy_type, :enforcement_level,
            :is_active, :max_critical_vulnerabilities, :max_high_vulnerabilities,
            :max_age_days, :require_signature, :require_attestation,
            match_rules: {}, rules: {}, metadata: {}
          )
        end

        def serialize_policy(policy, include_details: false)
          data = {
            id: policy.id,
            name: policy.name,
            description: policy.description,
            policy_type: policy.policy_type,
            enforcement_level: policy.enforcement_level,
            is_active: policy.is_active,
            require_signature: policy.require_signature,
            require_attestation: policy.require_attestation,
            created_at: policy.created_at,
            updated_at: policy.updated_at
          }

          if include_details
            data[:match_rules] = policy.match_rules
            data[:rules] = policy.rules
            data[:max_critical_vulnerabilities] = policy.max_critical_vulnerabilities
            data[:max_high_vulnerabilities] = policy.max_high_vulnerabilities
            data[:max_age_days] = policy.max_age_days
            data[:metadata] = policy.metadata
          end

          data
        end
      end
    end
  end
end

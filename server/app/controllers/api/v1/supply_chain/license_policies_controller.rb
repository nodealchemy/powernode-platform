# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class LicensePoliciesController < BaseController
        before_action :require_read_permission, only: [:index, :show, :evaluate]
        before_action :require_write_permission, only: [:create, :update, :destroy]
        before_action :set_license_policy, only: [:show, :update, :destroy, :evaluate]

        # GET /api/v1/supply_chain/license_policies
        def index
          @policies = current_account.supply_chain_license_policies
                                     .includes(:created_by)
                                     .order(created_at: :desc)

          @policies = @policies.where(is_active: true) if params[:active_only] == "true"
          @policies = @policies.where(policy_type: params[:policy_type]) if params[:policy_type].present?

          @policies = paginate(@policies)

          render_success(
            { license_policies: @policies.map { |p| serialize_policy(p) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/license_policies/:id
        def show
          render_success({ license_policy: serialize_policy(@policy, include_details: true) })
        end

        # POST /api/v1/supply_chain/license_policies
        def create
          @policy = current_account.supply_chain_license_policies.build(policy_params)
          @policy.created_by = current_user

          if @policy.save
            render_success({ license_policy: serialize_policy(@policy) }, status: :created)
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/license_policies/:id
        def update
          if @policy.update(policy_params)
            render_success({ license_policy: serialize_policy(@policy) })
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/supply_chain/license_policies/:id
        def destroy
          @policy.destroy
          render_success(message: "License policy deleted")
        end

        # POST /api/v1/supply_chain/license_policies/:id/evaluate
        def evaluate
          sbom_ids = params[:sbom_ids] || []
          sboms = current_account.supply_chain_sboms.where(id: sbom_ids)

          results = sboms.map do |sbom|
            violations = @policy.evaluate(sbom)
            {
              sbom_id: sbom.id,
              sbom_name: sbom.name,
              compliant: violations.empty?,
              violation_count: violations.count,
              violations: violations.map { |v| serialize_violation_preview(v) }
            }
          end

          render_success({
            policy_id: @policy.id,
            policy_name: @policy.name,
            results: results,
            total_violations: results.sum { |r| r[:violation_count] }
          })
        end

        private

        def set_license_policy
          @policy = current_account.supply_chain_license_policies.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("License policy not found", status: :not_found)
        end

        def policy_params
          params.require(:license_policy).permit(
            :name, :description, :policy_type, :enforcement_level,
            :is_active, :is_default, :priority,
            :block_copyleft, :block_strong_copyleft, :block_unknown,
            allowed_licenses: [], denied_licenses: [], exception_packages: [], metadata: {}
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
            is_default: policy.is_default,
            priority: policy.priority,
            block_copyleft: policy.block_copyleft,
            block_strong_copyleft: policy.block_strong_copyleft,
            block_unknown: policy.block_unknown,
            created_at: policy.created_at,
            updated_at: policy.updated_at
          }

          if include_details
            data[:allowed_licenses] = policy.allowed_licenses
            data[:denied_licenses] = policy.denied_licenses
            data[:exception_packages] = policy.exception_packages
            data[:violation_count] = policy.license_violations.where(status: "open").count
            data[:metadata] = policy.metadata
          end

          data
        end

        def serialize_violation_preview(violation)
          {
            license_spdx_id: violation[:license_spdx_id],
            component_name: violation[:component_name],
            violation_type: violation[:violation_type],
            severity: violation[:severity]
          }
        end
      end
    end
  end
end

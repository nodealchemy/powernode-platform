# frozen_string_literal: true

# Internal API controller for worker service to fetch data retention policies
class Api::V1::Internal::DataRetentionPoliciesController < Api::V1::Internal::InternalBaseController
  # GET /api/v1/internal/data_retention_policies
  def index
    policies = DataRetentionPolicy.where(active: true).order(:data_type)

    render_success(data: policies.map { |p| policy_data(p) })
  end

  private

  def policy_data(policy)
    {
      id: policy.id,
      data_type: policy.data_type,
      retention_days: policy.retention_days,
      action: policy.action,
      active: policy.active,
      created_at: policy.created_at,
      updated_at: policy.updated_at
    }
  end
end

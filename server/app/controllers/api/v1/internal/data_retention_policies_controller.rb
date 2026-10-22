# frozen_string_literal: true

# Internal API controller for worker service to fetch data retention policies
class Api::V1::Internal::DataRetentionPoliciesController < Api::V1::Internal::InternalBaseController
  # GET /api/v1/internal/data_retention_policies
  def index
    policies = DataManagement::RetentionPolicy.where(active: true).order(:data_type)

    render_success(data: policies.map { |p| policy_data(p) })
  end

  private

  # account_id is the policy's tenant scope: the worker refuses any policy
  # without one rather than treating nil as system-wide (IMP-01a163fa).
  def policy_data(policy)
    {
      id: policy.id,
      account_id: policy.account_id,
      data_type: policy.data_type,
      retention_days: policy.retention_days,
      action: policy.action,
      active: policy.active,
      last_enforced_at: policy.last_enforced_at,
      records_processed_count: policy.records_processed_count,
      created_at: policy.created_at,
      updated_at: policy.updated_at
    }
  end
end

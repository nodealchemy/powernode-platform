# frozen_string_literal: true

module Ai
  module WorkflowParamNormalization
    extend ActiveSupport::Concern

    private

    def workflow_params
      params.require(:workflow).permit(
        :name, :description, :status, :visibility, :version, :workflow_type,
        :is_template, :template_category, :tags, :trigger_types,
        :execution_mode, :retry_policy, :timeout_seconds, :max_execution_time, :cost_limit,
        configuration: {}, metadata: {}, input_schema: {}, output_schema: {}, tags: [], nodes: [], edges: []
      )
    end

    def normalized_workflow_params
      permitted = workflow_params.to_h

      if permitted[:status].present?
        status_mapping = { "published" => "active", "enabled" => "active", "disabled" => "inactive" }
        permitted[:status] = status_mapping[permitted[:status]] || permitted[:status]
      end

      config_keys = %w[execution_mode timeout_seconds max_execution_time retry_policy cost_limit]
      config_params = {}
      config_keys.each do |key|
        sym_key = key.to_sym
        config_params[key] = permitted.delete(sym_key) if permitted[sym_key].present?
      end
      permitted[:configuration] = (permitted[:configuration] || {}).merge(config_params) if config_params.any?

      if permitted.key?(:tags) || permitted.key?("tags")
        tags_value = permitted.delete(:tags) || permitted.delete("tags")
        permitted[:metadata] = (permitted[:metadata] || {}).merge("tags" => tags_value) if tags_value.present?
      end

      permitted.delete(:trigger_types)
      permitted.delete("trigger_types")
      permitted
    end

    def workflow_sort_fields
      { "version" => "version", "creator" => "users.name" }
    end
  end
end

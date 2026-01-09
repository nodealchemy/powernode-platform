# frozen_string_literal: true

module Ai
  class WorkflowEdge < ApplicationRecord
    self.table_name = "ai_workflow_edges"

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"

    # Associations - using node_id as foreign key since it's the unique identifier within a workflow
    belongs_to :source_node, class_name: "Ai::WorkflowNode",
               foreign_key: "source_node_id", primary_key: "node_id"
    belongs_to :target_node, class_name: "Ai::WorkflowNode",
               foreign_key: "target_node_id", primary_key: "node_id"

    # Validations
    validates :edge_id, presence: true, uniqueness: { scope: :ai_workflow_id }
    validates :source_node_id, presence: true
    validates :target_node_id, presence: true
    validates :edge_type, presence: true, inclusion: {
      in: %w[
        default success error conditional
        retry timeout skip fallback compensation loop
      ],
      message: "must be a valid edge type"
    }
    validates :priority, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_source_and_target_exist
    validate :validate_no_self_loops
    validate :validate_conditional_configuration
    validate :validate_start_end_node_connections

    # JSON columns
    attribute :condition, :json, default: -> { {} }
    attribute :configuration, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :by_type, ->(type) { where(edge_type: type) }
    scope :conditional, -> { where(is_conditional: true) }
    scope :default_edges, -> { where(edge_type: "default") }
    scope :success_edges, -> { where(edge_type: "success") }
    scope :error_edges, -> { where(edge_type: "error") }
    scope :retry_edges, -> { where(edge_type: "retry") }
    scope :compensation_edges, -> { where(edge_type: "compensation") }
    scope :ordered_by_priority, -> { order(:priority) }

    # Callbacks
    before_validation :set_conditional_flag
    after_create :update_workflow_metadata
    after_destroy :update_workflow_metadata

    # Edge type check methods
    def default_edge?
      edge_type == "default"
    end

    def success_edge?
      edge_type == "success"
    end

    def error_edge?
      edge_type == "error"
    end

    def conditional_edge?
      edge_type == "conditional" || is_conditional?
    end

    def loop_edge?
      edge_type == "loop"
    end

    def retry_edge?
      edge_type == "retry"
    end

    def timeout_edge?
      edge_type == "timeout"
    end

    def skip_edge?
      edge_type == "skip"
    end

    def fallback_edge?
      edge_type == "fallback"
    end

    def compensation_edge?
      edge_type == "compensation"
    end

    # Condition evaluation methods
    def evaluate_condition(context_variables = {})
      return true unless is_conditional? || condition.present?

      begin
        evaluate_condition_expression(condition, context_variables)
      rescue StandardError => e
        Rails.logger.error "Failed to evaluate edge condition: #{e.message}"
        false
      end
    end

    def condition_summary
      return "Always" unless is_conditional? || condition.present?

      if condition["expression"].present?
        condition["expression"]
      elsif condition["rules"].present?
        summarize_condition_rules(condition["rules"])
      else
        "Custom condition"
      end
    end

    # Edge configuration helpers
    def has_condition?
      is_conditional? || condition.present?
    end

    def condition_variables
      return [] unless condition.present?

      extract_variables_from_condition(condition)
    end

    def is_error_fallback?
      edge_type == "error" || configuration["is_error_fallback"] == true
    end

    def should_execute_on_success?
      %w[default success].include?(edge_type) ||
      (!is_conditional? && edge_type != "error")
    end

    def should_execute_on_error?
      edge_type == "error" || configuration["execute_on_error"] == true
    end

    # Path analysis
    def creates_cycle?
      visited = Set.new([ source_node_id ])
      check_for_cycle(target_node_id, visited)
    end

    def path_length_to_end
      calculate_path_length_to_end(target_node_id, Set.new([ source_node_id ]))
    end

    private

    def set_conditional_flag
      self.is_conditional = condition.present? && condition.keys.any? { |k| k != "metadata" }
    end

    def validate_source_and_target_exist
      return unless ai_workflow_id.present?

      workflow_node_ids = workflow.workflow_nodes.pluck(:node_id)

      unless workflow_node_ids.include?(source_node_id)
        errors.add(:source_node_id, "does not exist in this workflow")
      end

      unless workflow_node_ids.include?(target_node_id)
        errors.add(:target_node_id, "does not exist in this workflow")
      end
    end

    def validate_no_self_loops
      if source_node_id == target_node_id
        errors.add(:target_node_id, "cannot be the same as source node (self-loops not allowed)")
      end
    end

    def validate_conditional_configuration
      return unless is_conditional? || condition.present?

      if condition.blank? || condition.empty?
        errors.add(:condition, "must be present for conditional edges")
        return
      end

      # Validate condition structure
      if condition["expression"].present?
        validate_expression_syntax(condition["expression"])
      elsif condition["rules"].present?
        validate_condition_rules(condition["rules"])
      else
        errors.add(:condition, "must contain either expression or rules")
      end
    end

    def validate_start_end_node_connections
      return unless ai_workflow_id.present? && source_node && target_node

      if source_node.is_end_node?
        errors.add(:source_node_id, "end nodes cannot have outgoing edges")
      end

      if target_node.is_start_node?
        errors.add(:target_node_id, "start nodes cannot have incoming edges")
      end
    end

    def validate_expression_syntax(expression)
      return if expression.blank?

      unless expression.is_a?(String)
        errors.add(:condition, "expression must be a string")
        return
      end

      paren_count = 0
      expression.each_char do |char|
        case char
        when "("
          paren_count += 1
        when ")"
          paren_count -= 1
          if paren_count < 0
            errors.add(:condition, "expression has unbalanced parentheses")
            return
          end
        end
      end

      if paren_count != 0
        errors.add(:condition, "expression has unbalanced parentheses")
      end
    end

    def validate_condition_rules(rules)
      unless rules.is_a?(Array)
        errors.add(:condition, "rules must be an array")
        return
      end

      rules.each_with_index do |rule, index|
        unless rule.is_a?(Hash)
          errors.add(:condition, "rule #{index + 1} must be a hash")
          next
        end

        %w[variable operator value].each do |required_key|
          if rule[required_key].blank?
            errors.add(:condition, "rule #{index + 1} must have #{required_key}")
          end
        end

        valid_operators = %w[== != > >= < <= contains starts_with ends_with in not_in exists not_exists]
        unless valid_operators.include?(rule["operator"])
          errors.add(:condition, "rule #{index + 1} has invalid operator")
        end
      end
    end

    def evaluate_condition_expression(condition_hash, context)
      if condition_hash["expression"].present?
        evaluate_expression(condition_hash["expression"], context)
      elsif condition_hash["rules"].present?
        evaluate_rules(condition_hash["rules"], context, condition_hash["logic"] || "AND")
      else
        false
      end
    end

    def evaluate_expression(expression, context)
      processed_expression = expression.dup

      context.each do |key, value|
        processed_expression.gsub!("${#{key}}", value.to_s)
        processed_expression.gsub!("$#{key}", value.to_s)
      end

      case processed_expression
      when /^true$/i
        true
      when /^false$/i
        false
      when /^\d+\s*[><=!]+\s*\d+$/
        eval(processed_expression) rescue false
      when /^["'][^"']*["']\s*[><=!]+\s*["'][^"']*["']$/
        eval(processed_expression) rescue false
      else
        false
      end
    end

    def evaluate_rules(rules, context, logic_operator)
      results = rules.map { |rule| evaluate_single_rule(rule, context) }

      case logic_operator.upcase
      when "AND"
        results.all?
      when "OR"
        results.any?
      else
        false
      end
    end

    def evaluate_single_rule(rule, context)
      variable_name = rule["variable"]
      operator = rule["operator"]
      expected_value = rule["value"]

      actual_value = context[variable_name] || context[variable_name.to_sym]

      case operator
      when "=="
        actual_value == expected_value
      when "!="
        actual_value != expected_value
      when ">"
        actual_value.to_f > expected_value.to_f
      when ">="
        actual_value.to_f >= expected_value.to_f
      when "<"
        actual_value.to_f < expected_value.to_f
      when "<="
        actual_value.to_f <= expected_value.to_f
      when "contains"
        actual_value.to_s.include?(expected_value.to_s)
      when "starts_with"
        actual_value.to_s.start_with?(expected_value.to_s)
      when "ends_with"
        actual_value.to_s.end_with?(expected_value.to_s)
      when "in"
        Array(expected_value).include?(actual_value)
      when "not_in"
        !Array(expected_value).include?(actual_value)
      when "exists"
        !actual_value.nil?
      when "not_exists"
        actual_value.nil?
      else
        false
      end
    end

    def summarize_condition_rules(rules)
      return "No conditions" if rules.empty?

      summaries = rules.map do |rule|
        "#{rule['variable']} #{rule['operator']} #{rule['value']}"
      end

      logic = condition["logic"] || "AND"
      summaries.join(" #{logic} ")
    end

    def extract_variables_from_condition(condition_hash)
      variables = Set.new

      if condition_hash["expression"].present?
        expression = condition_hash["expression"]
        variables.merge(expression.scan(/\$\{([^}]+)\}/).flatten)
        variables.merge(expression.scan(/\$([a-zA-Z_][a-zA-Z0-9_]*)/).flatten)
      end

      if condition_hash["rules"].present?
        condition_hash["rules"].each do |rule|
          variables.add(rule["variable"]) if rule["variable"].present?
        end
      end

      variables.to_a
    end

    def check_for_cycle(current_node_id, visited)
      return true if visited.include?(current_node_id)

      visited.add(current_node_id)

      outgoing_edges = workflow.workflow_edges.where(source_node_id: current_node_id)

      outgoing_edges.each do |edge|
        return true if check_for_cycle(edge.target_node_id, visited.dup)
      end

      false
    end

    def calculate_path_length_to_end(current_node_id, visited, depth = 0)
      return Float::INFINITY if visited.include?(current_node_id) || depth > 100

      current_node = workflow.workflow_nodes.find_by(node_id: current_node_id)
      return depth if current_node&.is_end_node?

      visited.add(current_node_id)

      outgoing_edges = workflow.workflow_edges.where(source_node_id: current_node_id)

      return Float::INFINITY if outgoing_edges.empty? && !current_node&.is_end_node?

      min_path_length = Float::INFINITY

      outgoing_edges.each do |edge|
        path_length = calculate_path_length_to_end(edge.target_node_id, visited.dup, depth + 1)
        min_path_length = [ min_path_length, path_length ].min
      end

      min_path_length
    end

    def update_workflow_metadata
      workflow.touch(:updated_at)
    end
  end
end

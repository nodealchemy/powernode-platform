# frozen_string_literal: true

module Ai
  module Campaigns
    # IMP-fd7e7082b431 — the shape of a campaign's `plan_increments`, in one
    # place: documented for the callers who write one, and checked by the models
    # (Ai::CampaignProposal when its configuration changes, Ai::Campaign on
    # create) so every door that stores or spawns a plan is covered, not one tool.
    #
    # CampaignDriver#seed_plan_increments! turns each increment into a RalphTask
    # and reads it leniently: an unknown key is dropped, a `files` that is not a
    # list reads as "none declared" (which the dev_next_task file-collision
    # guard treats as colliding with everything), a non-string dependency is
    # dropped, and an increment with neither a title nor a task_key is skipped.
    # Each of those is a plan silently losing something its author meant, so
    # they are refused up front with the key named.
    #
    # An increment is either a title String or an object with:
    #   title                 String   the increment's name (its task_key derives from it)
    #   description           String
    #   task_key              String   explicit key, so dependencies can name it
    #   files                 [String] paths it touches (the file-collision guard's input)
    #   acceptance_criteria   String
    #   dependencies          [String] task_keys that must finish first
    # One of title or task_key is required.
    module PlanIncrements
      CONFIG_KEY = "plan_increments"
      STRING_KEYS = %w[title description task_key acceptance_criteria].freeze
      LIST_KEYS = %w[files dependencies].freeze
      KEYS = (STRING_KEYS + LIST_KEYS).freeze

      # The text a caller reads on the tool's `configuration` parameter.
      DOCUMENTATION = "plan_increments: [ title String | { title, description, task_key (String); files, dependencies " \
                      "([String]: paths it touches / task_keys it waits on); acceptance_criteria (String) } ] — " \
                      "a title or task_key is required; unknown keys and wrong types are refused. " \
                      "Other keys: scope/posture/ordering/keep-going."

      module_function

      # @param configuration [Hash, nil] a campaign or proposal configuration
      # @return [Array<String>] one message per problem, empty when the plan is fine or absent
      def problems(configuration)
        return [] unless configuration.is_a?(Hash)

        plan = configuration.stringify_keys[CONFIG_KEY]
        return [] if plan.nil? # absent or null: no plan, which the driver reads the same way

        return [ "#{CONFIG_KEY} must be a list of increments (a title string or an object), got #{plan.class.name.downcase}" ] unless plan.is_a?(Array)

        plan.each_with_index.flat_map { |increment, index| increment_problems(increment, index) }
      end

      def increment_problems(increment, index)
        at = "#{CONFIG_KEY}[#{index}]"
        return title_problems(increment, at) if increment.is_a?(String)
        return [ "#{at} must be a title string or an object" ] unless increment.is_a?(Hash)

        spec = increment.to_h.stringify_keys
        unknown = (spec.keys - KEYS).map do |key|
          "#{at}.#{key} is not a known key (allowed: #{KEYS.sort.join(', ')})"
        end
        unknown + key_problems(spec, at) + identity_problems(spec, at)
      end

      def title_problems(title, at)
        title.strip.empty? ? [ "#{at} needs a title or a task_key" ] : []
      end

      def key_problems(spec, at)
        STRING_KEYS.filter_map { |key| "#{at}.#{key} must be a string" if spec.key?(key) && !spec[key].nil? && !spec[key].is_a?(String) } +
          LIST_KEYS.flat_map { |key| list_problems(spec, key, at) }
      end

      def list_problems(spec, key, at)
        return [] unless spec.key?(key) && !spec[key].nil?
        return [ "#{at}.#{key} must be a list of strings" ] unless spec[key].is_a?(Array)

        spec[key].each_with_index.filter_map { |entry, i| "#{at}.#{key}[#{i}] must be a string" unless entry.is_a?(String) }
      end

      # A wrong-typed title or task_key is already reported by key_problems; only
      # a plan that names the increment in neither is reported here.
      def identity_problems(spec, at)
        values = spec.values_at("title", "task_key")
        return [] if values.any? { |value| !value.nil? && !value.is_a?(String) }
        return [] if values.any? { |value| value.is_a?(String) && !value.strip.empty? }

        [ "#{at} needs a title or a task_key" ]
      end
    end
  end
end

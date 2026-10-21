# frozen_string_literal: true

module Ai
  module Skills
    # THE rule that a skill attesting it is read-only (manifest.gate_category read /
    # read_only true) names no verb that writes, shared by the seed gate (seeded
    # batches) and Ai::Skill's save validation (account clones and hand-made
    # skills), so a clone cannot be mis-tiered by carrying writing verbs under a
    # read-only attestation.
    #
    # Allowed despite `mutating: true`: Contract::READ_SKILL_MUTATING_VERBS and the
    # read probes registered for the skill's own owner (Contract.read_probe_verbs).
    # A registered verb with no declared action cannot be shown read-only, so it
    # fails; a verb the registry does not know at all is left to the seed gate's
    # registered-verb check (an extension that is not loaded must not make a clone
    # unsaveable).
    module ReadOnlyVerbs
      module_function

      # @param slug [String]
      # @param manifest [Hash, nil] the skill's metadata["manifest"]
      # @param owner [String] the skill's owner_repo
      # @return [Array<String>] error messages (empty when the skill is fine)
      def errors(slug:, manifest:, owner:)
        return [] unless manifest.is_a?(Hash) && (manifest["gate_category"] == "read" || manifest["read_only"] == true)

        registry = ::Ai::Tools::PlatformApiToolRegistry.all_tools
        allowed = Contract.read_probe_verbs(owner)
        Array(manifest["verbs"]).map(&:to_s).uniq.filter_map do |verb|
          next if allowed.include?(verb) || !registry.key?(verb)

          tool = registry[verb]
          tool = tool.safe_constantize if tool.is_a?(String)
          declaration = tool.respond_to?(:declared_action) ? tool.declared_action(::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(verb, verb)) : nil
          if declaration.nil?
            "#{slug}: gate_category read but verb #{verb} has no declared action, so it cannot be shown read-only"
          elsif declaration[:mutating]
            "#{slug}: gate_category read but names mutating verb #{verb} (declare the skill mutate, or have its owner register a read-only probe)"
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Tools
    # THE declared tool-family vocabulary (C3-1). Every registry action resolves
    # to one of these keys through BaseTool.family_for: the tool class's default
    # (`tool_family`) or a per-action `declare_action ... family:` override. A
    # family is a DECLARATION, never a name prefix; before this the only
    # taxonomy was the prefix, and 440 of 674 actions had no catalog section.
    #
    # Core declares its own families below. An extension adds the families its
    # tool classes use through .register, from its engine's to_prepare, so core
    # never names an extension's domain. Insertion order is the generated
    # catalog's section order.
    #
    # spec/services/ai/tools/tool_family_declaration_spec.rb is the lint: every
    # registered action must resolve to a key known here.
    module ToolFamilies
      CORE = {
        "agents" => "Agents, teams & coordination",
        "skills" => "Skills",
        "knowledge" => "Knowledge, learnings & RAG",
        "memory" => "Agent memory",
        "code" => "Codebase intelligence",
        "conversations" => "Conversations & workspaces",
        "notifications" => "Activity, notifications & escalation",
        "governance" => "Governance, approvals & autonomy control",
        "campaigns" => "Campaigns, improvements & dev loop",
        "devops" => "Git, CI/CD & delivery",
        "docker" => "Docker",
        "kubernetes" => "Kubernetes",
        "data_sources" => "Data sources",
        "content" => "Content & media",
        "provisioning" => "Projects & provisioning",
        "platform" => "Platform status, settings & identity",
        "discovery" => "Tool discovery"
      }.freeze

      class << self
        # Merge an extension's { key => label } families. Idempotent, so a
        # to_prepare re-run on reload is harmless; a core key cannot be relabelled.
        def register(families)
          families.each do |key, label|
            key = key.to_s
            raise ArgumentError, "#{key.inspect} is a core family and cannot be re-registered" if CORE.key?(key)

            extension_families[key] = label.to_s
          end
          all
        end

        def extension_families
          @extension_families ||= {}
        end

        # key => label, core first.
        def all
          CORE.merge(extension_families)
        end

        def known?(key)
          key.present? && all.key?(key.to_s)
        end

        def label(key)
          all[key.to_s]
        end
      end
    end
  end
end

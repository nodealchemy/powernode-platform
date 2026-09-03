# frozen_string_literal: true

# Declaration-coverage computation for the governance ratchet
# (IMP-a0553dda1ec3). Kept OUT of the spec file so the ratchet's two-way oracle
# can drive it with synthetic registries, and so a mutant can be injected with
# `rspec -r` without editing anything in the repo.
#
# WHAT IT MEASURES. Ai::Tools::BaseTool#execute looks a declaration up by
# #routed_action_name — NOT by the MCP registry key. For most tools those agree;
# for the ones McpPlatformToolRegistrar aliases (KnowledgeGraphTool, the
# code_* family) they do not, and a ratchet keyed on the registry key would
# report every aliased action as undeclared and be garbage on day one. So the
# resolution below mirrors the registrar exactly:
#
#   registrar auto-injects  execution_params[:action] = ACTION_ALIASES.fetch(k, k)
#   ...but only when        action_dispatched?(tool_class)
#   otherwise               no :action param -> routed_action_name falls back to
#                           tool_class.definition[:name]
#
# `action_dispatched?` is CALLED on the registrar (private, via send) rather
# than reimplemented, so the two cannot drift apart silently.
#
# SCOPE. The walk is Ai::Tools::PlatformApiToolRegistry.all_tools, which is
# `TOOLS.merge(extension_tools)` — so extension-registered tool maps are covered
# by construction, through the generic seam, with no extension named here. A
# caller-supplied :action that is not a registry key is out of scope: the
# registry surface is what this ratchet bounds.
module ToolDeclarationCoverage
  SNAPSHOT_PATH = Rails.root.join("spec/fixtures/governance/undeclared_actions.txt")

  module_function

  # Registry key => tool class name. Seam-level, overridable by a mutant.
  def registry_map
    Ai::Tools::PlatformApiToolRegistry.all_tools
  end

  def registrar
    Ai::Tools::McpPlatformToolRegistrar
  end

  # The action name BaseTool#execute will look the declaration up by.
  def resolved_action_name(registry_key, tool_class)
    if registrar.send(:action_dispatched?, tool_class)
      registrar::ACTION_ALIASES.fetch(registry_key, registry_key)
    else
      tool_class.definition[:name].to_s
    end
  end

  # action name => Array of tool class names serving it.
  def resolved_actions(map = registry_map)
    map.each_with_object({}) do |(key, class_name), acc|
      tool_class =
        begin
          class_name.constantize
        rescue NameError
          # Unresolvable class: count the key as undeclared rather than
          # dropping it. A registry entry nobody can load is ungoverned too.
          (acc[key] ||= []) << class_name
          next
        end

      (acc[resolved_action_name(key, tool_class)] ||= []) << class_name
    end
  end

  # Declared only when EVERY class serving the action declares it. Uses
  # .declared_action (ancestry-walking), never .declared_actions (per-class),
  # so a subclass inheriting its parent's declaration is not read as undeclared.
  def declared?(action_name, class_names)
    class_names.all? do |class_name|
      klass = class_name.safe_constantize
      klass.respond_to?(:declared_action) && !klass.declared_action(action_name).nil?
    end
  end

  def snapshot_entries(path = SNAPSHOT_PATH)
    return [] unless File.exist?(path)

    File.readlines(path, chomp: true)
        .map(&:strip)
        .reject { |line| line.empty? || line.start_with?("#") }
  end

  def report(map = registry_map, snapshot = snapshot_entries)
    actions = resolved_actions(map)
    declared, undeclared = actions.keys.partition { |name| declared?(name, actions[name]) }

    {
      registry_keys: map.size,
      resolved_actions: actions.size,
      declared: declared.sort,
      undeclared: undeclared.sort,
      snapshot: snapshot.sort,
      # Direction 1 — the ratchet: a registry action that is neither declared
      # nor already acknowledged in the frozen snapshot is NEW ungoverned surface.
      ungoverned_growth: (undeclared - snapshot).sort,
      # Direction 2 — anti-rot: a snapshot entry that is no longer an undeclared
      # registry action (it got declared, or the key is gone). Without this the
      # snapshot decays into a permanent exemption list.
      stale_snapshot_entries: (snapshot - undeclared).sort
    }
  end

  # Rewrite the frozen snapshot from the current tree. Deliberately NOT called
  # by the spec — regenerating on failure is what turns a ratchet into a
  # rubber stamp. Run by hand when a NEW undeclared action is a conscious,
  # reviewed addition.
  def write_snapshot!(path = SNAPSHOT_PATH)
    entries = report[:undeclared]
    File.write(path, "#{SNAPSHOT_HEADER}#{entries.join("\n")}\n")
    entries.size
  end

  SNAPSHOT_HEADER = <<~HEADER
    # FROZEN SNAPSHOT — MCP registry actions that execute with NO governance
    # declaration (Ai::Tools::BaseTool.declare_action). IMP-a0553dda1ec3.
    #
    # THIS LIST MAY ONLY SHRINK.
    #   * A new registry action that is not declared and not listed here fails
    #     spec/services/ai/tools/declaration_coverage_ratchet_spec.rb.
    #   * An entry here that HAS since been declared (or whose registry key is
    #     gone) also fails, so this cannot rot into a permanent exemption list.
    #   * Adding a line is a reviewed decision to grow the ungoverned surface.
    #     Removing one is the point.
    #
    # Names are the RESOLVED action names BaseTool#execute looks declarations up
    # by (McpPlatformToolRegistrar::ACTION_ALIASES applied), not raw registry
    # keys. Sorted; one per line. Regenerate ONLY deliberately:
    #   bin/rails runner -e test 'require Rails.root.join("spec/support/tool_declaration_coverage"); ToolDeclarationCoverage.write_snapshot!'
  HEADER
end

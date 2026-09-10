# frozen_string_literal: true

require "rails_helper"

# Increment E2 — the two destructiveness classifications on this platform agree
# over the CORE tool surface.
#
# There are two of them, and before E2 they never met:
#
#   Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS  an 18-glob deny overlay that
#     hard-refuses destroy-shaped tools for every instance principal, whatever
#     its grant. Answers "may this principal invoke it at all".
#
#   declare_action(destructive:)               the wire hint Mcp::ToolCatalog
#     publishes as `destructiveHint`. Answers "may this action perform an
#     irreversible update".
#
# They are different questions with the same subject, and two rival
# classifications of the same 640 verbs is how one of them silently rots. This
# holds them in SET EQUALITY over core, in both directions:
#
#   overlay - declared   a destroy-shaped core action nobody declared. It would
#                        publish `destructiveHint: false`, and a client reading
#                        the hint would treat a verb the platform refuses to
#                        even grant an instance as a reversible write.
#   declared - overlay   a core action declared destructive that the overlay
#                        does NOT refuse. That is not a harmless surplus: the
#                        author has said it performs an irreversible update, so
#                        the overlay should be refusing it for instance
#                        principals and does not. The fix is a pattern, not an
#                        exemption.
#
# SCOPE IS CORE ONLY, and that is a live gap rather than a design choice. The
# 40 destroy-shaped actions in extensions/system carry no `destructive:`
# declaration yet — E2's partition is core tool files. Mcp::ToolCatalog covers
# them meanwhile with a floor that reads the overlay directly, so nothing is
# UNDER-stated on the wire today; what is missing is the declaration. The
# extension arm below asserts that gap is still exactly what it was, so it
# cannot quietly grow while it waits for its lane.
RSpec.describe "declare_action(destructive:) agrees with the instance deny overlay", type: :lint do
  # Walked from the REGISTRY MAP, one row per registry key. Walking
  # ToolDeclarationCoverage.resolved_actions instead and recovering the key by
  # reverse-lookup does not work: a multi-action class serves many keys, so
  # `all_tools.find { |_k, c| c == class_name }` hands every one of its actions
  # the class's FIRST key — which is how a first cut of this file reported
  # `list_skills` and `search_knowledge` as declared destructive.
  #
  # The action name is resolved through ToolDeclarationCoverage, the SHARED
  # resolver that mirrors BaseTool#execute's alias hop. A lookup keyed on the
  # raw registry key finds nothing for the 25 aliased entries and would report
  # every one of them as undeclared; re-deriving the hop here would be a second
  # place to get it wrong.
  def rows
    @rows ||= Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |key, class_name|
      klass = class_name.safe_constantize
      next nil unless klass.respond_to?(:declared_action)

      action = ToolDeclarationCoverage.resolved_action_name(key, klass)
      { registry_key: key, action: action, klass: class_name,
        source: source_path(class_name), declaration: klass.declared_action(action) }
    end
  end

  def source_path(class_name)
    Object.const_source_location(class_name)&.first.to_s
  end

  # Core = the class is NOT defined under an extension checkout. Keyed on
  # `/extensions/` rather than on `/server/app/`, because an extension's tool
  # files live at `extensions/<slug>/server/app/services/ai/tools/` — they
  # contain `/server/app/` too, so the obvious test classifies every extension
  # tool as core and the split silently collapses to "everything".
  #
  # Path-based rather than namespace-based: an extension may use any namespace,
  # and what actually decides whether this lane may edit a declaration is which
  # repository the file lives in.
  def core?(path)
    !path.empty? && !path.include?("/extensions/")
  end

  # Keyed on the REGISTRY KEY, because that is the name Mcp::Principal
  # #may_invoke? checks the overlay against — the name a caller invokes, not
  # the name BaseTool dispatches internally.
  let(:overlay_core) do
    Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |key, class_name|
      next nil unless core?(source_path(class_name))

      key if Mcp::Principal.destructive_tool?(key)
    end.to_set
  end

  let(:declared_core) do
    rows.filter_map do |row|
      next nil unless core?(row[:source])
      next nil unless row[:declaration].is_a?(Hash) && row[:declaration][:destructive] == true

      row[:registry_key]
    end.to_set
  end

  it "scans a real corpus" do
    expect(rows.size).to be > 500, "resolved only #{rows.size} actions — the walk has broken"
    expect(rows.count { |r| core?(r[:source]) }).to be > 200
    expect(rows.count { |r| !core?(r[:source]) }).to be > 100,
      "found no extension-defined actions — the core?/extension split has stopped working"
  end

  it "declares every core action the deny overlay refuses" do
    missing = (overlay_core - declared_core).to_a.sort

    expect(missing).to be_empty, <<~MSG
      #{missing.size} core action(s) are refused by Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS
      but carry no `destructive: true` on their declare_action:

        #{missing.join("\n  ")}

      Mcp::ToolCatalog publishes destructiveHint from the declaration, so each of
      these would advertise as a reversible write to any client that did not also
      hit the overlay's floor. Add `destructive: true` to the declaration.
    MSG
  end

  it "refuses a core destructive declaration the deny overlay would still grant" do
    surplus = (declared_core - overlay_core).to_a.sort

    expect(surplus).to be_empty, <<~MSG
      #{surplus.size} core action(s) declare `destructive: true` but are NOT matched by
      Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS:

        #{surplus.join("\n  ")}

      The declaration says the action performs an irreversible update, so an
      instance principal should not be able to hold a grant for it. Add a pattern
      to the overlay rather than dropping the declaration — the overlay is the
      control, the hint is only the disclosure.
    MSG
  end

  # THE PENDING HALF, asserted rather than described. If somebody declares the
  # extension verbs (the intended follow-up) this goes red and is deleted
  # along with Mcp::ToolCatalog#destructive?'s floor; if somebody adds a new
  # undeclared destroy-shaped extension verb it goes red too.
  it "pins the extension surface as still entirely undeclared" do
    overlay_ext = Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |key, class_name|
      path = source_path(class_name)
      next nil if path.empty? || core?(path)

      key if Mcp::Principal.destructive_tool?(key)
    end.to_set

    declared_ext = rows.filter_map do |row|
      next nil if row[:source].empty? || core?(row[:source])
      next nil unless row[:declaration].is_a?(Hash) && row[:declaration][:destructive] == true

      row[:registry_key]
    end.to_set

    expect(overlay_ext).not_to be_empty,
      "no destroy-shaped extension actions found — either the extension is not loaded in this " \
      "environment, or the split has broken; either way this pin is not measuring anything"
    expect(declared_ext).to be_empty, <<~MSG
      #{declared_ext.size} extension action(s) now declare destructive: true:
        #{declared_ext.to_a.sort.join("\n  ")}

      Good — that is the follow-up landing. When ALL of them are declared, delete
      this example and the deny-overlay floor in Mcp::ToolCatalog#destructive?,
      and widen the two set-equality examples above from core to the whole surface.
    MSG
  end
end

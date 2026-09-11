# frozen_string_literal: true

require "rails_helper"

# Increment E2 — the two destructiveness classifications on this platform agree
# over the WHOLE registered tool surface, core and extension alike.
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
# classifications of the same verbs is how one of them silently rots. This
# holds them in SET EQUALITY over every registered action, in both directions:
#
#   overlay - declared   a destroy-shaped action nobody declared. It would
#                        publish `destructiveHint: false`, and a client reading
#                        the hint would treat a verb the platform refuses to
#                        even grant an instance as a reversible write.
#   declared - overlay   an action declared destructive that the overlay
#                        does NOT refuse. That is not a harmless surplus: the
#                        author has said it performs an irreversible update, so
#                        the overlay should be refusing it for instance
#                        principals and does not. The fix is a pattern, not an
#                        exemption.
#
# WHAT THIS MEANS FOR THE DECLARATIONS (E2 review M3). Over core, the
# `destructive: true` set is DERIVED from the overlay and held there by this
# file — it was not judged verb by verb, and it cannot be corrected verb by
# verb without changing the overlay. That matters because the overlay is a
# principal-class deny list, which is a broader question than MCP's. MCP
# defines destructiveHint by whether an update is ADDITIVE; the overlay also
# denies verbs because of who may call them. Five core verbs sit in the gap:
#
#   create_intervention_policy   purely additive at the row level — but a new
#                                policy at a higher priority can shadow an
#                                existing one's protection
#   update_intervention_policy   overwrites prior values: non-additive
#   emergency_resume             overwrites the suspended state
#   approve_deferred_operation   RUNS the parked operation (DeferredOperation
#                                #on_approval_decision -> #execute_now!), which
#                                can itself be anything the gate parked
#   reject_deferred_operation    a terminal transition that abandons it
#
# By MCP's own definition four of the five are correctly `true`; only the
# first is additive, and it stays `true` for the effect above. Undeclaring any
# of them is not an option either: the catalog now publishes destructiveHint
# from the declaration alone, so an undeclared entry would advertise a verb the
# overlay refuses as a reversible write, which the first equality example
# below forbids. The one way to publish `false` is to take them off the
# overlay, which would let an instance principal write its own autonomy
# policy, lift the kill switch, or approve operations parked against it. The
# control wins; the over-statement is the safe direction and is recorded here
# rather than rediscovered.
#
# SCOPE IS THE WHOLE SURFACE (E2 follow-through). E2 declared the core tool
# files, and the 40 destroy-shaped actions in the system extension were
# declared in its own lane (extension commit a6bda1dc). Until then this file
# covered core only, Mcp::ToolCatalog stood in for the extension with a floor
# that read the overlay directly, and a pin asserted the extension gap had not
# grown. With every destroy-shaped verb declared, the pin and the floor are
# both gone: the catalog publishes destructiveHint from the declaration alone,
# and the equality below is what keeps that honest, in every tree.
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

  # RESOLVED FIRST, then located (E2 review M1). On a constant Zeitwerk has
  # not loaded yet, Object.const_source_location does not return nil — it
  # returns the autoloader's own stub, a path inside the zeitwerk gem. That
  # path is non-empty and contains no `/extensions/`, so #core? read EVERY
  # not-yet-loaded extension class as core: measured, overlay_core came out 72
  # cold and 32 warm. The file was green on a full run only because the first
  # example constantizes everything through #rows before the others look, and
  # red on any targeted run of the two examples that walk the registry raw.
  # CI eager-loads, which hid it there too.
  def source_path(class_name)
    klass = class_name.to_s.safe_constantize
    return "" if klass.nil? || klass.name.nil?

    Object.const_source_location(klass.name)&.first.to_s
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
  let(:overlay) do
    Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |key, _class_name|
      key if Mcp::Principal.destructive_tool?(key)
    end.to_set
  end

  let(:declared) do
    rows.filter_map do |row|
      next nil unless row[:declaration].is_a?(Hash) && row[:declaration][:destructive] == true

      row[:registry_key]
    end.to_set
  end

  # THE M1 GUARD, as an assertion rather than a comment. Every class this file
  # classifies must resolve to the file its own NAME implies — the one property
  # the autoloader's stub cannot have, because the stub is a single file inside
  # zeitwerk that stands in for every constant it has not loaded yet. A
  # regression to an unresolved lookup fails here instead of silently
  # reclassifying 40 extension verbs as core.
  #
  # A first cut asserted "the path is inside this checkout". It PASSED with
  # the raw lookup restored, run in isolation, because the bundle is vendored
  # INSIDE the checkout: the stub resolved to
  # server/vendor/bundle/ruby/3.2.0/gems/zeitwerk-2.8.2/lib/zeitwerk/cref.rb.
  # A location test says nothing about a stub when the gem lives in the repo,
  # so that cut was replaced rather than kept beside this one.
  #
  # Walks the registry RAW, the same way overlay_core does, so it measures the
  # path the two set-equality examples actually take.
  it "locates every registered tool class in the file its name implies" do
    wrong = Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |class_name|
      path = source_path(class_name)
      next nil if path.empty?

      "#{class_name} -> #{path}" unless path.end_with?("/#{class_name.underscore}.rb")
    end

    expect(wrong).to be_empty, "resolved to a file its name does not imply:\n  #{wrong.join("\n  ")}"
  end

  it "scans a real corpus" do
    expect(rows.size).to be > 500, "resolved only #{rows.size} actions — the walk has broken"
    expect(rows.count { |r| core?(r[:source]) }).to be > 200
    expect(rows.count { |r| !core?(r[:source]) }).to be > 100,
      "found no extension-defined actions — the core?/extension split has stopped working"
  end

  # The equality is only as wide as the sets it compares. If the extension
  # stopped loading, both sides would shrink to core and still agree, so both
  # trees must be present in the overlay set for the examples below to mean
  # what they say.
  it "compares sets that span both trees" do
    trees = overlay.map { |key| core?(source_path(Ai::Tools::PlatformApiToolRegistry.all_tools[key])) ? :core : :extension }

    expect(trees).to include(:core, :extension),
      "the overlay set covers only #{trees.uniq.inspect} — the whole-surface equality is not measuring both trees"
  end

  it "declares every action the deny overlay refuses" do
    missing = (overlay - declared).to_a.sort

    expect(missing).to be_empty, <<~MSG
      #{missing.size} action(s) are refused by Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS
      but carry no `destructive: true` on their declare_action:

        #{missing.join("\n  ")}

      Mcp::ToolCatalog publishes destructiveHint from the declaration alone, so each
      of these would advertise as a reversible write. Add `destructive: true` to the
      declaration.
    MSG
  end

  it "refuses a destructive declaration the deny overlay would still grant" do
    surplus = (declared - overlay).to_a.sort

    expect(surplus).to be_empty, <<~MSG
      #{surplus.size} action(s) declare `destructive: true` but are NOT matched by
      Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS:

        #{surplus.join("\n  ")}

      The declaration says the action performs an irreversible update, so an
      instance principal should not be able to hold a grant for it. Add a pattern
      to the overlay rather than dropping the declaration — the overlay is the
      control, the hint is only the disclosure.
    MSG
  end
end

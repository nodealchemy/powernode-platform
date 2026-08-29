# frozen_string_literal: true

require "ripper"

# Constant-resolution check for the MCP tool surface (IMP-4707960fc610).
#
# WHY. `platform_validate_plan` and `platform_approve_plan` were advertised for
# months while their bodies constantized `Ai::Autonomy::PlanValidationService`
# and `Ai::Autonomy::PlanApprovalService` — classes that exist nowhere in core
# or in any extension. Because both methods carried a `rescue NameError` arm,
# the failure was indistinguishable from a normal refusal: every call on every
# account returned "Plan validation service not available" and nothing raised,
# nothing was logged, no spec went red. An advertised verb whose only reachable
# behaviour is its own rescue is worse than an absent one — the catalog is the
# contract an agent plans against.
#
# WHAT IT MEASURES. For every class registered in
# Ai::Tools::PlatformApiToolRegistry.all_tools, parse the class's source file
# and assert that every NAMESPACED constant path it references resolves to a
# constant that actually exists.
#
# Deliberate scoping decisions:
#
#   * Namespaced paths only (>= 2 segments). A bare `FOO` is almost always a
#     constant of the enclosing class and carries no cross-namespace typo risk;
#     including them would flood the check with local noise for no signal.
#   * The app is eager-loaded before resolving. Zeitwerk only autoloads the
#     constant a file is NAMED for, so a sibling declared in the same file
#     (e.g. Ai::KnowledgeGraph::ExtractionServiceError, declared beside
#     ExtractionService in extraction_service.rb) does not resolve cold. That is
#     a load-order question, not an existence question, and this check asks the
#     existence question.
#   * `defined?(X::Y)` references are skipped. That is the deliberate
#     optional-constant seam (see McpPlatformToolRegistrar) — a reference the
#     author has already declared conditional is not a broken reference.
#   * Resolution is attempted absolutely and then against each enclosing module
#     of the owning class, mirroring Ruby's own lexical lookup, so a relative
#     `Autonomy::Foo` written inside `Ai::Tools` is not a false positive.
#
# KNOWN BOUND (same one the declaration-coverage ratchet carries): the walk is
# .all_tools, i.e. core TOOLS plus whatever extension maps are registered in
# THIS environment. An environment loading an extension tool map absent here
# checks that map too; it is covered through the generic seam, with no
# extension named.
module ToolConstantResolution
  module_function

  # Registry key => tool class name. Seam-level, overridable by a mutant.
  def registry_map
    Ai::Tools::PlatformApiToolRegistry.all_tools
  end

  # Every namespaced constant path referenced by `source`, minus the ones
  # wrapped in `defined?`. Pure function over a source STRING so the oracle can
  # be driven with synthetic input and proven red without touching the tree.
  def constant_paths(source)
    sexp = Ripper.sexp(source)
    raise ArgumentError, "source did not parse" if sexp.nil?

    collect_paths(sexp).uniq.sort
  end

  # Constant paths in `source` that do not resolve, judged from the lexical
  # position of `owner_name` (a fully-qualified class/module name, or nil for
  # top level).
  def unresolved_in_source(source, owner_name)
    constant_paths(source).reject { |path| resolves?(path, owner_name) }
  end

  def resolves?(path, owner_name)
    return true if "::#{path}".safe_constantize

    segments = owner_name.to_s.split("::")
    (segments.length - 1).downto(1).any? do |i|
      "::#{segments[0, i].join('::')}::#{path}".safe_constantize
    end
  end

  # => { classes_scanned:, paths_scanned:, unresolvable_classes:, unresolved: }
  #
  # `unresolved` entries are { tool_class:, constant:, file: }.
  def report(map = registry_map)
    Rails.application.eager_load!

    unresolvable_classes = []
    unresolved = []
    paths_scanned = 0
    class_names = map.values.uniq.sort

    class_names.each do |class_name|
      klass = class_name.safe_constantize
      if klass.nil?
        unresolvable_classes << class_name
        next
      end

      file, = Object.const_source_location(class_name)
      next if file.blank? || !File.exist?(file)

      paths = constant_paths(File.read(file))
      paths_scanned += paths.size
      paths.each do |path|
        next if resolves?(path, class_name)

        unresolved << { tool_class: class_name, constant: path, file: file }
      end
    end

    {
      registry_keys: map.size,
      classes_scanned: class_names.size,
      paths_scanned: paths_scanned,
      unresolvable_classes: unresolvable_classes.sort,
      unresolved: unresolved.sort_by { |e| [e[:tool_class], e[:constant]] }
    }
  end

  # --- Ripper walk -------------------------------------------------------

  def collect_paths(node, acc = [])
    return acc unless node.is_a?(Array)

    case node[0]
    when :const_path_ref, :const_path_field
      path = flatten_path(node)
      acc << path if path
      # The receiver is part of THIS path; do not re-collect its prefix.
      return acc
    when :defined
      # Deliberate optional-constant seam — not a broken reference.
      return acc
    end

    node.each { |child| collect_paths(child, acc) if child.is_a?(Array) }
    acc
  end

  def flatten_path(node)
    case node[0]
    when :const_path_ref, :const_path_field
      left = flatten_path(node[1])
      right = node[2]
      return nil unless left && right.is_a?(Array) && right[0] == :@const

      "#{left}::#{right[1]}"
    when :var_ref, :const_ref, :top_const_ref
      inner = node[1]
      inner.is_a?(Array) && inner[0] == :@const ? inner[1] : nil
    when :@const
      node[1]
    end
  end
end

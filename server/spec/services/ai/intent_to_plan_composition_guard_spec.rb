# frozen_string_literal: true

require "rails_helper"
require "ripper"
require "tempfile"

# IMP-59478e8e620a — the guard §6.2 of the readiness map asked for and never got.
#
#   "Deterministic-first did not generalize because it lived as prose. The
#    provisioning composer learned 'recognized scenario -> synthesize, LLM only
#    for novel' the hard way; the adaptation composer regressed to LLM-first
#    anyway. Rule: every intent->plan seam declares a recognized-scenario
#    predicate and stamps composer provenance -- and the lesson gets a guard,
#    because un-guarded lessons recur instance-by-instance forever."
#     -- docs/operations/autonomous-infrastructure-readiness-2026-08-12.md:268
#
# Two composers learned this rule one at a time. This file is what stops the
# third from learning it a third time.
#
# ---------------------------------------------------------------------------
# MEMBERSHIP: what makes a class an intent->plan composer
# ---------------------------------------------------------------------------
#
# NOT the filename. `*_composer_service.rb` / `*_proposer_service.rb` is the
# analogue of a formatting-blind regex: a composer named anything else escapes
# entirely, which is precisely the third composer this guard exists to catch.
# It is also wrong in the other direction -- `feature_plan_service.rb` (core
# entitlements) and `control_plane_fence.rb` match those name patterns and
# compose nothing.
#
# The predicate is STRUCTURAL: a class is an intent->plan composer iff it
# CONSTRUCTS an `Ai::GoalPlan`. That model is the platform's one plan artifact
# -- the thing a plan runner walks and an operator reads -- so authoring one IS
# the act of turning an intent into a plan, whatever the authoring class is
# called. The predicate is also what correctly EXCLUDES the consumers:
# `Ai::Provisioning::AdaptationDispatchService` writes `live_plan.steps.create!`
# and transacts on `Ai::GoalPlan` all over, but it never constructs a plan -- it
# appends already-composed steps onto someone else's -- so it needs no
# exemption line. Membership falls out of what the code DOES.
#
# Construction is recognised through BOTH routes, because they are the same act
# written two ways and a guard that knew only one is a guard the idiomatic
# refactor walks past:
#
#   constant     -- `Ai::GoalPlan.create!` / `::Ai::GoalPlan.new`
#   association  -- `goal.plans.create!` / `account.ai_goal_plans.build`
#
# The association NAMES are read out of ActiveRecord's own reflections rather
# than written here as a literal. A hand-written list is how the first draft of
# this file shipped a dead arm: it guessed `goal_plans`, which is not an
# association on this tree at all (the real ones are `Ai::AgentGoal#plans` and
# `Account#ai_goal_plans`), so the arm could never fire and the tempfile oracle
# that "proved" it could not tell, because a tempfile bypasses file discovery.
# Reflections cannot drift from the models the way a literal can, and the
# example below additionally asserts the derived list is non-empty.
#
# What this predicate CANNOT catch, stated plainly rather than discovered later:
#
#   1. A SPLIT composer. If the class that computes the steps hands them to a
#      separate thin PERSISTER that constructs the plan, the persister is the
#      member -- and a persister passes both conjuncts honestly (it stamps one
#      value, and it does not itself touch the LLM), so the guard goes GREEN
#      while the LLM-first composer behind it is never examined. This is a
#      silent hole, not a misdirected diagnostic. It is the most serious known
#      gap in this file.
#   2. A composer for a DIFFERENT plan artifact. `System::Migrations::
#      PlanComposer` authors `System::MigrationPlanStep` rows, a separate plane
#      with its own model; core's guard sees only `Ai::GoalPlan`, and core may
#      not name an extension anyway.
#   3. METAPROGRAMMED construction -- `"Ai::GoalPlan".constantize.create!` or an
#      association reached through `send`. Ripper sees a string, not a constant
#      path, and file discovery never even reaches such a file.
#   4. DELEGATED LLM reach. Reachability (below) resolves a class's own source
#      and its real ancestor chain -- NOT the services it calls. A member that
#      gets its steps from an LLM-backed collaborator and then persists them
#      itself with a single stamp reads as deterministic and is waived from
#      conjunct B.
#      This is a genuine hole and is recorded as one. It is NOT argued away:
#      it merely happens that the one instance on today's tree is covered by
#      accident, because `PlanComposerService`'s novel-brief delegate
#      (`GoalDecompositionService`) constructs a plan of its own and is
#      therefore a member in its own right. A delegate that RETURNS steps
#      instead of persisting them would not be.
#      Modelling delegation was tried and rejected: it turns `PlanComposerService`
#      -- the platform's exemplar of the very rule, with a real
#      recognized-scenario predicate -- into a conjunct-B violator, and a guard
#      whose loudest red is its model citizen is a guard that gets exempted into
#      uselessness.
#
# ---------------------------------------------------------------------------
# THE TWO CONJUNCTS
# ---------------------------------------------------------------------------
#
# A. STAMPS COMPOSER PROVENANCE. The member writes a recognized provenance key
#    into something it PERSISTS, so an operator reading a stored plan can tell
#    what composed it.
#
# B. DECLARES A RECOGNIZED-SCENARIO PREDICATE. "Deterministic-first" is a
#    semantic property, and a guard that pattern-matched a predicate would be
#    over-fitted to whichever `include?` the current code happens to use. Its
#    mechanically checkable SHADOW is: a composer that can reach the LLM must
#    stamp MORE THAN ONE value UNDER ONE KEY. You cannot stamp a non-LLM value
#    unless a non-LLM branch exists to stamp it, and a composer whose provenance
#    is a constant has exactly one composition path -- if that path reaches the
#    LLM, it IS LLM-first. That is the regression, expressed as a count.
#
#    A member that cannot reach the LLM is deterministic by construction and
#    satisfies B with one value.
#
#    Two deliberate tightenings, each closing a way to buy the count for free:
#
#      * SAME KEY. Values are grouped by the key they are written under, so
#        `{ "composed_by" => "llm", "composer" => "llm_v2" }` on one path is one
#        value under each key, not two.
#      * PERSISTED CONTEXT. A literal stamp counts only inside the argument
#        list of a persistence call. `composer` is an ordinary English word --
#        this tree already has `composer_agent` and `composer_router` -- so an
#        unrelated `Rails.logger.info(composer: "x")` must be able to neither
#        certify a composer NOR red one. Values reaching a plan through a
#        stamper method are exempt from this rule, since the stamper mechanism
#        is itself the evidence.
#
#    Still buyable, and not claimed otherwise: two literal values under one key
#    in two persistence calls on the SAME path satisfy B without any branch
#    existing. Closing that needs the two sites proven to sit in different arms
#    of one conditional, which is not implemented here.
#
# ---------------------------------------------------------------------------
# WHY RIPPER, NOT GREP
# ---------------------------------------------------------------------------
#
# Not a stylistic preference -- a grep implementation of this guard is WRONG on
# today's tree, and the counter-example is load-bearing enough to have its own
# example below. `plan_composer_service.rb` contains the text
# "GoalDecompositionService's WorkerLlmClient call" in a COMMENT. A text scan
# classifies that composer as LLM-reachable, demands a second provenance value
# it has no need of, and reds a compliant composer. Ripper drops :on_comment,
# so only executable code is read. Every arm here parses.
RSpec.describe "intent-to-plan composer coherence", type: :lib do
  # `let`, never a bare constant in a describe block -- that lands on Object and
  # a generic name there is the duplicate-constant clobber that makes suites
  # order-dependent.

  let(:scan_roots) { [ Rails.root.join("app"), Rails.root.join("lib") ] }

  let(:plan_const) { "GoalPlan" }
  let(:plan_namespace) { "Ai" }
  let(:plan_class_name) { "#{plan_namespace}::#{plan_const}" }

  # Construction verbs. `new` and `build` are included because a composer that
  # builds then saves is composing just as much as one that `create!`s.
  let(:construct_methods) do
    %w[create! create new build first_or_create! first_or_create create_or_find_by! create_or_find_by]
  end

  # The context a LITERAL provenance stamp must sit in to count -- broader than
  # construction, because a stamp may land on the goal or the steps rather than
  # the plan row itself (MissionComposer does both).
  let(:persistence_methods) do
    construct_methods + %w[update! update assign_attributes insert_all! save!]
  end

  # Derived from ActiveRecord, never hand-written -- see the header.
  let(:plan_association_methods) do
    Rails.application.eager_load!
    names = ActiveRecord::Base.descendants.flat_map do |model|
      model.reflect_on_all_associations(:has_many)
           .select { |ref| ref.class_name == plan_class_name }
           .map { |ref| ref.name.to_s }
    rescue StandardError
      []
    end
    names.uniq.sort
  end

  # The provenance keys the platform actually writes. TWO, not one, and that
  # fork is a REAL finding rather than a convenience: AdaptationProposerService
  # and MissionComposer write "composed_by", PlanComposerService writes
  # "composer". No consumer can read provenance uniformly across all three.
  # Recorded here rather than papered over -- a THIRD key invented by a new
  # composer registers as "stamps no provenance" and reds, which is the
  # behaviour that keeps the fork bounded at two.
  let(:provenance_keys) { %w[composed_by composer] }

  # The terminal LLM seams. Both ways core reaches a model bottom out in a
  # WorkerLlmClient: `Ai::LlmCallable#call_llm` builds one, and
  # AdaptationProposerService#build_llm_client names it directly -- through the
  # cost-tracking wrapper, which is a DIFFERENT constant and must be listed or
  # a composer using only the wrapper reads as deterministic. Reachability is
  # resolved through the REAL ancestor chain, not a text approximation of
  # `include`, so any depth of module inclusion counts.
  let(:llm_client_seams) { %w[WorkerLlmClient TrackedWorkerLlmClient] }

  # ==========================================================================
  # Sexp helpers
  # ==========================================================================

  # Ripper returns nil for source it cannot parse. Silently yielding no nodes
  # for an unparseable file is the "matches nothing, so cannot fail" shape this
  # whole file exists to refuse.
  def parse!(path)
    sexp = Ripper.sexp(File.read(path))
    raise "#{path} does not parse, so this guard cannot read it — a file the scan cannot parse is a " \
          "file the scan silently exempts" if sexp.nil?

    sexp
  end

  def each_node(node, &blk)
    return unless node.is_a?(Array)

    blk.call(node) if node.first.is_a?(Symbol)
    node.each { |child| each_node(child, &blk) if child.is_a?(Array) }
  end

  # Flatten a constant path to a dotted name. A leading `::` is normalised
  # away: `::Ai::GoalPlan` and `Ai::GoalPlan` name the same class and a guard
  # that told them apart would be reporting punctuation.
  def const_name(node)
    return nil unless node.is_a?(Array)

    case node.first
    when :const_path_ref, :const_path_field
      left = const_name(node[1])
      right = node[2].is_a?(Array) && node[2].first == :@const ? node[2][1] : nil
      left && right ? "#{left}::#{right}" : nil
    when :top_const_ref, :var_ref, :const_ref
      node[1].is_a?(Array) && node[1].first == :@const ? node[1][1] : const_name(node[1])
    when :@const
      node[1]
    end
  end

  # A STATIC string. Interpolation returns nil deliberately -- a provenance
  # value assembled at runtime is not a declaration, and treating it as one
  # would let `"#{mode}_composer"` masquerade as two values. An EMPTY string
  # literal is a real (if useless) static value, not an unparseable one.
  def literal_string(node)
    return nil unless node.is_a?(Array)

    case node.first
    when :@label
      node[1].delete_suffix(":")
    when :string_literal
      parts = node[1].is_a?(Array) ? node[1][1..] : []
      return nil unless parts.is_a?(Array)
      return "" if parts.empty?
      return nil unless parts.size == 1 && parts[0].is_a?(Array) && parts[0].first == :@tstring_content

      parts[0][1]
    when :symbol_literal
      inner = node[1]
      inner.is_a?(Array) && inner.first == :symbol && inner[1].is_a?(Array) ? inner[1][1] : nil
    when :@tstring_content
      node[1]
    end
  end

  # Positional (required, optional AND post-required) then keyword parameter
  # names. Omitting post-required parameters made `def stamp!(*rest, source)`
  # raise as unclassifiable — a shape that is fine, just unread.
  def param_names(node)
    return { positional: [], keyword: [] } unless node.is_a?(Array)

    params = node.first == :paren ? node[1] : node
    return { positional: [], keyword: [] } unless params.is_a?(Array) && params.first == :params

    ident = ->(n) { n.is_a?(Array) && n.first == :@ident ? n[1] : nil }
    required = Array(params[1]).filter_map { |p| ident.call(p) }
    optional = Array(params[2]).filter_map { |p| ident.call(p.is_a?(Array) ? p[0] : p) }
    post     = Array(params[4]).filter_map { |p| ident.call(p) }
    keywords = Array(params[5]).filter_map do |p|
      label = p.is_a?(Array) ? p[0] : nil
      label.is_a?(Array) && label.first == :@label ? label[1].delete_suffix(":") : nil
    end

    { positional: required + optional + post, keyword: keywords }
  end

  # The argument list of a call, as [positional_nodes, {label => node}].
  def call_arguments(node)
    args = node
    args = args[1] if args.is_a?(Array) && args.first == :arg_paren
    return [ [], {} ] unless args.is_a?(Array) && args.first == :args_add_block

    positional = []
    keyword = {}
    Array(args[1]).each do |arg|
      if arg.is_a?(Array) && arg.first == :bare_assoc_hash
        Array(arg[1]).each do |assoc|
          next unless assoc.is_a?(Array) && assoc.first == :assoc_new

          key = literal_string(assoc[1])
          keyword[key] = assoc[2] if key
        end
      else
        positional << arg
      end
    end
    [ positional, keyword ]
  end

  # A call node normalised to [receiver_or_nil, method_name, argument_node].
  # ALL four shapes, because the difference between them is punctuation:
  #   `X.create!(a: 1)`  :method_add_arg wrapping :call
  #   `X.create! a: 1`   :command_call
  #   `stamp!(x, "l")`   :method_add_arg wrapping :fcall
  #   `stamp! x, "l"`    :command
  def normalized_call(node)
    return nil unless node.is_a?(Array)

    case node.first
    when :method_add_arg
      inner = node[1]
      return nil unless inner.is_a?(Array)

      case inner.first
      when :call  then [ inner[1], inner[3].is_a?(Array) && inner[3].first == :@ident ? inner[3][1] : nil, node[2] ]
      when :fcall then [ nil, inner[1].is_a?(Array) ? inner[1][1] : nil, node[2] ]
      end
    when :command_call
      [ node[1], node[3].is_a?(Array) && node[3].first == :@ident ? node[3][1] : nil, node[4] ]
    when :command
      [ nil, node[1].is_a?(Array) ? node[1][1] : nil, node[2] ]
    when :method_add_block
      normalized_call(node[1])
    end
  end

  # ==========================================================================
  # The scan
  # ==========================================================================

  # Replace nested class/module subtrees with a no-op, so an outer class does
  # not inherit an inner one's construction sites and stamps. Each nested class
  # is still walked as its own unit by `class_units`.
  def strip_nested(node)
    return node unless node.is_a?(Array)
    return [ :void_stmt ] if %i[class module].include?(node.first)

    node.map { |child| child.is_a?(Array) ? strip_nested(child) : child }
  end

  # Every class in a file, with its full namespaced name and its own body.
  def class_units(path)
    units = []
    walk = lambda do |node, nesting|
      return unless node.is_a?(Array)

      if %i[class module].include?(node.first) && node[1].is_a?(Array)
        name = const_name(node[1])
        if name
          # split on "::" so a compact definition (`class Ai::Foo`) contributes
          # each segment to the nesting a bare constant is resolved against.
          inner = nesting + name.split("::")
          body = node.first == :class ? node[3] : node[2]
          if node.first == :class
            units << { name: inner.join("::"), body: strip_nested(body), nesting: inner }
          end
          walk.call(body, inner)
          return
        end
      end

      node.each { |child| walk.call(child, nesting) if child.is_a?(Array) }
    end
    walk.call(parse!(path), [])
    units
  end

  # Does this class body CONSTRUCT an Ai::GoalPlan?
  def constructs_plan?(body, nesting)
    found = false
    each_node(body) do |node|
      next if found

      call = normalized_call(node)
      next unless call

      receiver, method, = call
      next unless construct_methods.include?(method)

      name = const_name(receiver)
      if name
        # A bare `GoalPlan` counts only inside the Ai namespace; elsewhere it is
        # some other class that happens to share the name.
        found = true if name == plan_class_name || (name == plan_const && nesting.include?(plan_namespace))
      else
        inner = normalized_call(receiver) ||
                (receiver.is_a?(Array) && receiver.first == :call ? [ nil, receiver[3].is_a?(Array) ? receiver[3][1] : nil, nil ] : nil)
        assoc = inner && inner[1]
        found = true if assoc && plan_association_methods.include?(assoc)
      end
    end
    found
  end

  # Provenance writes inside a class body, resolved to {key => [values]}.
  #
  # Classification is TOTAL within the contexts that count: a provenance write
  # this scan cannot resolve RAISES rather than being skipped, because a skipped
  # write is a composer certified by a stamp nobody read. Shapes understood:
  #
  #   1. literal    -- `"composed_by" => "mission_composer"`, a bare label, or
  #                    `step["composed_by"] = "llm"` / `||= "llm"`, INSIDE the
  #                    argument list of a persistence call.
  #   2. stamper    -- a method that assigns the key from one of its OWN
  #                    parameters. Its values are the literal arguments at its
  #                    call sites inside the same class. This is the shape
  #                    AdaptationProposerService uses, and a scan that only
  #                    understood shape 1 would report the one COMPLIANT
  #                    composer as stamping nothing.
  #   3. anything else in those contexts -> raise.
  #
  # A literal write OUTSIDE any persistence call is neither counted nor raised:
  # `composer` is an ordinary word, and an unrelated `composer:` kwarg must be
  # able to neither certify a composer nor red one.
  def provenance_scan(unit)
    values = Hash.new { |h, k| h[k] = [] }
    stampers = []
    unresolved = []

    walk = lambda do |node, ctx, persisting|
      return unless node.is_a?(Array)

      if node.first == :def && node[1].is_a?(Array)
        ctx = { name: node[1][1], params: param_names(node[2]) }
      elsif node.first == :defs && node[3].is_a?(Array)
        # `def self.stamp!(...)` — same mechanism, different node.
        ctx = { name: node[3][1], params: param_names(node[4]) }
      end

      call = normalized_call(node)
      persisting = true if call && persistence_methods.include?(call[1])

      write = provenance_write(node)
      if write
        literal = literal_string(write[:value])
        ident = value_identifier(write[:value])
        if ident && ctx && (idx = ctx[:params][:positional].index(ident))
          stampers << { method: ctx[:name], positional: idx }
        elsif ident && ctx && ctx[:params][:keyword].include?(ident)
          stampers << { method: ctx[:name], keyword: ident }
        elsif literal
          values[write[:key]] << literal if persisting
        elsif persisting
          unresolved << "#{unit[:name]}: writes #{write[:key].inspect} inside a persistence call from an " \
                        "expression this scan cannot resolve to a declared value " \
                        "(#{Array(write[:value]).first.inspect})"
        end
      end

      node.each { |child| walk.call(child, ctx, persisting) if child.is_a?(Array) }
    end
    walk.call(unit[:body], nil, false)

    stampers.uniq.each do |stamper|
      sites = stamper_call_values(unit[:body], stamper)
      unresolved.concat(sites[:unresolved])
      if sites[:values].empty? && sites[:unresolved].empty?
        unresolved << "#{unit[:name]}: ##{stamper[:method]} assigns a composer-provenance key from a " \
                      "parameter but this scan finds NO call site for it in the class, so the values it " \
                      "stamps are unreadable — a stamp nobody can read is not a declaration"
      end
      sites[:values].each { |key, vals| values[key].concat(vals) }
    end

    if unresolved.any?
      raise "#{unit[:name]} carries a composer-provenance write this guard does not classify, so it " \
            "would be certified or condemned on an incomplete reading. Teach the scan the shape, or " \
            "write the stamp in one it knows: #{unresolved.join('; ')}"
    end

    values.transform_values(&:uniq)
  end

  # A single provenance write, or nil. Hash-entry, index-assign and
  # index-or-assign forms — `||=` is how a stamp gets written defensively, and
  # reading it as "no stamp" would condemn a composer that has one.
  def provenance_write(node)
    case node.first
    when :assoc_new
      key = literal_string(node[1])
      provenance_keys.include?(key) ? { key: key, value: node[2] } : nil
    when :assign, :opassign
      target = node[1]
      return nil unless target.is_a?(Array) && target.first == :aref_field

      index = target[2]
      index = index[1] if index.is_a?(Array) && index.first == :args_add_block
      key = literal_string(Array(index).first)
      return nil unless provenance_keys.include?(key)

      { key: key, value: node.first == :opassign ? node[3] : node[2] }
    end
  end

  def value_identifier(node)
    return nil unless node.is_a?(Array)
    return nil unless %i[var_ref vcall].include?(node.first)

    node[1].is_a?(Array) && node[1].first == :@ident ? node[1][1] : nil
  end

  # The literal values handed to a stamper method at its call sites, keyed by
  # the provenance key that stamper writes.
  def stamper_call_values(body, stamper)
    values = Hash.new { |h, k| h[k] = [] }
    unresolved = []
    key = stamper_key(body, stamper[:method])

    each_node(body) do |node|
      call = normalized_call(node)
      next unless call && call[1] == stamper[:method]

      positional, keyword = call_arguments(call[2])
      arg = stamper[:keyword] ? keyword[stamper[:keyword]] : positional[stamper[:positional]]
      next if arg.nil? && stamper[:keyword].nil? && positional.empty? # the definition itself

      literal = literal_string(arg)
      if literal
        values[key] << literal
      else
        unresolved << "a call to ##{stamper[:method]} passes a non-literal composer-provenance value, " \
                      "so the provenance this composer stamps is not declared in its source"
      end
    end

    { values: values, unresolved: unresolved }
  end

  # Which provenance key a stamper method writes.
  def stamper_key(body, method_name)
    key = nil
    each_node(body) do |node|
      next if key
      next unless %i[def defs].include?(node.first)

      name_node = node.first == :def ? node[1] : node[3]
      next unless name_node.is_a?(Array) && name_node[1] == method_name

      each_node(node) do |inner|
        next if key

        write = provenance_write(inner)
        key = write[:key] if write
      end
    end
    key || provenance_keys.first
  end

  # ==========================================================================
  # Discovery
  # ==========================================================================

  # Pre-filtered on substrings before parsing. The needles include the
  # ASSOCIATION names as well as the constant, because a file that composes
  # only through `goal.plans.create!` never types "GoalPlan" — filtering on the
  # constant alone dropped exactly the composer the association arm exists to
  # catch, before it was ever parsed. (Metaprogrammed construction is already
  # listed as out of reach for this same reason.)
  let(:candidate_files) do
    needles = [ plan_const ] + plan_association_methods
    files = scan_roots.flat_map { |root| Dir[root.join("**/*.rb").to_s] }.sort.select do |path|
      source = File.read(path)
      needles.any? { |needle| source.include?(needle) }
    end
    raise "no file under #{scan_roots.join(', ')} mentions any of #{needles.inspect} — the scan is " \
          "looking in the wrong tree" if files.empty?

    files
  end

  let(:members) do
    found = candidate_files.flat_map do |path|
      class_units(path).select { |unit| constructs_plan?(unit[:body], unit[:nesting]) }
                       .map { |unit| unit.merge(path: path) }
    end
    found.sort_by { |unit| unit[:name] }
  end

  let(:member_names) { members.map { |unit| unit[:name] } }

  # The composers that exist today. A SUBSET assertion, not equality: a new
  # composer must not red the membership example (the conjunct examples are
  # where it is judged), but the scan going blind must.
  let(:known_members) do
    %w[
      Ai::Autonomy::GoalDecompositionService
      Ai::Missions::MissionComposer
      Ai::Provisioning::AdaptationProposerService
      Ai::Provisioning::PlanComposerService
    ]
  end

  # The compliant composer. Everything here is calibrated so this one PASSES:
  # a guard that cannot see the single conforming example that already exists
  # will never recognise a new one.
  let(:positive_control) { "Ai::Provisioning::AdaptationProposerService" }

  # ==========================================================================
  # LLM reachability, through the REAL ancestor chain
  # ==========================================================================

  # Every in-repo source file that defines this class or one of its ancestors.
  # Using `ancestors` rather than text-matching `include` lines means a seam
  # reached through two modules, a nested concern, or an `included do` block
  # counts exactly as much as a direct one.
  def ancestor_sources(class_name)
    klass = class_name.constantize
    ([ klass ] + klass.ancestors).uniq.filter_map do |mod|
      next unless mod.respond_to?(:name) && mod.name

      location = Object.const_source_location(mod.name)
      path = location && location[0]
      next unless path && scan_roots.any? { |root| path.start_with?(root.to_s) }

      path
    end.uniq
  rescue NameError => e
    # FAIL LOUD. Returning [] here would waive conjunct B for exactly the
    # members whose structure this guard understands least.
    raise "member #{class_name} does not constantize (#{e.message}), so its LLM reachability cannot be " \
          "resolved and conjunct B would be silently waived for it"
  end

  # Does this file NAME an LLM client seam in executable code? Parsed, so the
  # comment in plan_composer_service.rb does not count.
  def names_llm_seam?(path)
    found = false
    each_node(parse!(path)) do |node|
      found = true if !found && node.first == :@const && llm_client_seams.include?(node[1])
    end
    found
  end

  # [reachable?, :own_source | :ancestor | nil] -- the arm is returned so each
  # can be proven to match something on its own.
  def llm_reach(unit)
    return [ true, :own_source ] if names_llm_seam?(unit[:path])

    via = ancestor_sources(unit[:name]).reject { |p| p == unit[:path] }.find { |p| names_llm_seam?(p) }
    via ? [ true, :ancestor ] : [ false, nil ]
  end

  # Conjunct B's count: the largest number of distinct values under ONE key.
  def widest_provenance(unit)
    provenance_scan(unit).values.map(&:size).max || 0
  end

  # ==========================================================================
  # Examples
  # ==========================================================================

  # The scan's own oracle #1.
  it "finds every composer known to construct a plan today" do
    expect(members).not_to be_empty, "the membership scan matched NOTHING — a scan that matches nothing " \
                                     "cannot fail, so it is not a guard. Check the plan constant and scan roots."

    missing = known_members - member_names
    expect(missing).to be_empty,
                       "#{missing.size} class(es) that construct an Ai::GoalPlan on this tree are no longer " \
                       "seen by the membership scan, so they are silently unguarded: #{missing.join(', ')}"
  end

  # The association arm cannot be proven against the tree (no member uses it
  # today), so the thing that CAN be proven is that the names it looks for are
  # real. The first draft looked for `goal_plans`, which does not exist on any
  # model here — a dead arm that no tempfile oracle could detect, because a
  # tempfile bypasses file discovery entirely.
  it "derives the plan association names from ActiveRecord, and finds real ones" do
    expect(plan_association_methods).not_to be_empty,
                                            "no has_many association resolves to #{plan_class_name}, so the " \
                                            "association arm of the membership scan is looking for nothing " \
                                            "and `goal.plans.create!` would be invisible"

    plan_association_methods.each do |name|
      owners = ActiveRecord::Base.descendants.select do |model|
        model.reflect_on_all_associations(:has_many).any? { |r| r.name.to_s == name && r.class_name == plan_class_name }
      rescue StandardError
        false
      end
      expect(owners).not_to be_empty, "#{name} is not a real has_many to #{plan_class_name}"
    end

    # And the prefilter must not drop a file that only ever names the
    # association — the second, independent way the first draft's arm was dead.
    Tempfile.create([ "assoc_probe", ".rb" ]) do |f|
      f.write("goal.#{plan_association_methods.first}.create!(status: \"draft\")\n")
      f.flush
      needles = [ plan_const ] + plan_association_methods
      expect(needles.any? { |n| File.read(f.path).include?(n) }).to be(true),
                                                                    "file discovery would drop a composer " \
                                                                    "that constructs only through an association"
    end
  end

  # The scan's own oracle #2 — the positive control.
  it "sees the one compliant composer as compliant" do
    unit = members.find { |m| m[:name] == positive_control }
    expect(unit).not_to be_nil, "#{positive_control} is the calibration example for this guard and the " \
                                "membership scan no longer finds it"

    reachable, arm = llm_reach(unit)
    expect(reachable).to be(true), "#{positive_control} reaches the LLM and the seam scan no longer sees it"
    expect(arm).to eq(:own_source)

    expect(provenance_scan(unit)).to eq({ "composed_by" => %w[deterministic llm] })
  end

  # Each LLM-seam arm proven on its own. An alternation whose second arm is
  # dead looks exactly like an alternation that works.
  it "proves each LLM-reachability arm against a real class" do
    arms = members.to_h { |unit| [ unit[:name], llm_reach(unit)[1] ] }

    expect(arms.values).to include(:own_source),
                           "no member reaches the LLM through its OWN source, so that arm of the seam scan " \
                           "is matching nothing and would not be missed if it broke"
    expect(arms.values).to include(:ancestor),
                           "no member reaches the LLM through an ANCESTOR, so the include-graph arm is dead " \
                           "and a composer that gets the LLM from a concern would read as deterministic"
  end

  # Each provenance-extraction arm proven on its own, for the same reason.
  it "proves each provenance-extraction arm against a real class" do
    literal_only = members.find { |unit| unit[:name] == "Ai::Missions::MissionComposer" }
    indirect     = members.find { |unit| unit[:name] == positive_control }

    expect(provenance_scan(literal_only)).to eq({ "composed_by" => %w[mission_composer] }),
                                             "the literal hash-entry arm of the provenance scan no longer " \
                                             "reads MissionComposer's stamp"
    expect(widest_provenance(indirect)).to be > 1,
                                           "the stamper-indirection arm no longer reads " \
                                           "AdaptationProposerService's stamp_composition_source! call " \
                                           "sites — the ONE compliant composer would read as unstamped"
  end

  # The reason this guard parses instead of grepping, pinned as an example so
  # a future rewrite to grep reds here rather than in production.
  it "does not count an LLM client named only in a comment" do
    unit = members.find { |m| m[:name] == "Ai::Provisioning::PlanComposerService" }
    expect(unit).not_to be_nil

    expect(File.read(unit[:path])).to include("WorkerLlmClient"),
                                      "this example pins that a COMMENT naming the LLM client does not make " \
                                      "a composer LLM-reachable; the comment it pins is gone, so either move " \
                                      "the example to another commented seam or delete it"
    expect(llm_reach(unit)).to eq([ false, nil ]),
                               "PlanComposerService names WorkerLlmClient only in a comment. Reading it as " \
                               "LLM-reachable would demand a second provenance value from a composer whose " \
                               "novel-brief arm delegates instead — a grep implementation of this guard reds " \
                               "a compliant composer here."
  end

  # ---- Conjunct A -----------------------------------------------------------
  it "stamps composer provenance in every intent-to-plan composer" do
    # Composers that stamp nothing today. NAMED, not exempted: each line is a
    # standing defect with the sentence that says why it is still open. Delete
    # a line when the composer starts stamping; adding one costs a
    # justification, which is what makes a new exception visible.
    recorded = {
      "Ai::Autonomy::GoalDecompositionService" =>
        "LLM-only decomposition that stamps nothing, so a plan it authors is indistinguishable from a " \
        "deterministically synthesized one; it is PlanComposerService's novel-brief delegate, so the " \
        "provisioning lane's LLM arm is entirely unprovenanced. Open — fixing it is a composer change, " \
        "not a guard change."
    }

    unstamped = members.reject { |unit| provenance_scan(unit).any? }.map { |unit| unit[:name] }
    novel = unstamped - recorded.keys
    fixed = recorded.keys - unstamped

    expect(novel).to be_empty,
                     "#{novel.size} intent-to-plan composer(s) persist a plan while stamping no composer " \
                     "provenance, so nothing reading the stored plan can tell what composed it: " \
                     "#{novel.join(', ')} — stamp one of #{provenance_keys.join('/')}, or record the " \
                     "composer above with the sentence that justifies leaving it open"
    expect(fixed).to be_empty,
                     "#{fixed.join(', ')} now stamps provenance — delete its line from `recorded` above so " \
                     "the list keeps naming only what is actually still broken"
  end

  # ---- Conjunct B -----------------------------------------------------------
  it "gives every LLM-reachable composer a non-LLM branch to stamp" do
    # Composers that can reach the LLM and stamp exactly one value under every
    # key — i.e. one composition path, and it is the LLM one. LLM-FIRST, the
    # precise regression §6.2 records. Named, with the sentence that keeps it open.
    recorded = {
      "Ai::Missions::MissionComposer" =>
        "Every mission plan goes to the LLM: `decompose` prompts for a DAG with no recognized-scenario " \
        "arm ahead of it, and the single stamp \"mission_composer\" names the class rather than what " \
        "composed the steps. This is the third instance of the §6.2 regression and the reason this guard " \
        "exists; giving it a deterministic arm is composer work, filed separately.",
      "Ai::Autonomy::GoalDecompositionService" =>
        "LLM-only by construction — prompt, parse, persist, with no deterministic arm and no stamp at " \
        "all. Also recorded under conjunct A; the two conjuncts fail for one underlying reason."
    }

    offenders = members.select { |unit| llm_reach(unit)[0] && widest_provenance(unit) < 2 }
                       .map { |unit| unit[:name] }

    novel = offenders - recorded.keys
    fixed = recorded.keys - offenders

    expect(novel).to be_empty,
                     "#{novel.size} composer(s) can reach the LLM but stamp a single provenance value under " \
                     "every key, so they have exactly ONE composition path and it is the LLM one — " \
                     "LLM-first, the regression the readiness map §6.2 recorded: #{novel.join(', ')}. Give " \
                     "the composer a recognized-scenario arm and stamp it distinctly under the SAME key, or " \
                     "record it above with a justification sentence."
    expect(fixed).to be_empty,
                     "#{fixed.join(', ')} now stamps more than one provenance value under one key — delete " \
                     "its line from `recorded` above"
  end

  # ---- The scanner's own oracle ---------------------------------------------
  #
  # Every example above trusts the scan to FIND the drift, and the count floors
  # only protect shapes that already exist — never a NEW composer written in a
  # shape the scan walks past. So each shape a composer could plausibly take is
  # exercised against constructed source, refusals PAIRED with positive
  # controls: over-tightening this scan is invisible to a refusal-only test.
  it "recognizes a composer whatever shape it takes, and invents none" do
    scan = lambda do |source|
      Tempfile.create([ "composer_scan", ".rb" ]) do |f|
        f.write(source)
        f.flush
        class_units(f.path).map do |unit|
          member = constructs_plan?(unit[:body], unit[:nesting])
          { name: unit[:name], member: member, provenance: member ? provenance_scan(unit) : {} }
        end
      end
    end

    # Membership arm 1: qualified constant, and a name that matches NO
    # composer-ish filename convention.
    expect(scan.call(<<~RUBY).map { |u| [ u[:name], u[:member] ] }).to eq([ [ "Ai::WidgetMaker", true ] ])
      module Ai
        class WidgetMaker
          def go
            ::Ai::GoalPlan.create!(account: a)
          end
        end
      end
    RUBY

    # Membership arm 1b: bare constant inside the Ai namespace.
    expect(scan.call(<<~RUBY).first[:member]).to be(true)
      module Ai
        module Missions
          class Thing
            def go
              GoalPlan.new(account: a)
            end
          end
        end
      end
    RUBY

    # Membership arm 1c: COMPACT definition. `class Ai::Foo` must still resolve
    # a bare `GoalPlan` against the Ai namespace.
    expect(scan.call(<<~RUBY).first[:member]).to be(true)
      class Ai::Compact
        def go
          GoalPlan.create!(x: 1)
        end
      end
    RUBY

    # Membership arm 1d: PAREN-LESS construction (:command_call). One deleted
    # paren must not be an escape hatch.
    expect(scan.call(<<~RUBY).first[:member]).to be(true)
      module Ai
        class NoParens
          def go
            ::Ai::GoalPlan.create! account: a, status: "draft"
          end
        end
      end
    RUBY

    # Membership arm 2: ASSOCIATION construction — the idiomatic refactor of
    # what every current composer already does, and the shape the first draft
    # of this guard was blind to in two independent ways.
    assoc = plan_association_methods.first
    expect(scan.call(<<~RUBY).first[:member]).to be(true)
      module Ai
        module Autonomy
          class RemediationPlanner
            def compose!(goal)
              goal.#{assoc}.create!(status: "draft")
            end
          end
        end
      end
    RUBY

    # ...including with `build`.
    expect(scan.call(<<~RUBY).first[:member]).to be(true)
      module Ai
        class ViaBuild
          def go
            goal.#{assoc}.build(status: "draft")
          end
        end
      end
    RUBY

    # NOT a member: a bare `GoalPlan` outside the Ai namespace is a different
    # class that happens to share a name.
    expect(scan.call(<<~RUBY).first[:member]).to be(false)
      module Billing
        class Thing
          def go
            GoalPlan.create!(x: 1)
          end
        end
      end
    RUBY

    # NOT a member: the consumer shape. Appending to a plan, and transacting on
    # the class, must not read as composing one — this is what keeps
    # AdaptationDispatchService out without an exemption line.
    expect(scan.call(<<~RUBY).first[:member]).to be(false)
      module Ai
        class Appender
          def go
            ::Ai::GoalPlan.transaction do
              live_plan.steps.create!(step_number: 1)
            end
          end
        end
      end
    RUBY

    # NOT a member: a commented-out construction. The whole reason this parses.
    expect(scan.call(<<~RUBY).first[:member]).to be(false)
      module Ai
        class Inert
          def go
            # ::Ai::GoalPlan.create!(account: a)
            nil
          end
        end
      end
    RUBY

    # Nested classes do not pool their construction sites or their stamps.
    nested = scan.call(<<~RUBY)
      module Ai
        class Outer
          class Inner
            def go
              ::Ai::GoalPlan.create!(plan_data: { "composed_by" => "inner" })
            end
          end

          def go
            nil
          end
        end
      end
    RUBY
    expect(nested.find { |u| u[:name] == "Ai::Outer" }[:member]).to be(false)
    expect(nested.find { |u| u[:name] == "Ai::Outer::Inner" }[:provenance]).to eq({ "composed_by" => %w[inner] })

    # Provenance arm: literal hash entry, string key AND label key, inside the
    # construction call.
    expect(scan.call(<<~RUBY).first[:provenance]).to eq({ "composed_by" => %w[alpha], "composer" => %w[beta] })
      module Ai
        class LiteralStamp
          def go
            ::Ai::GoalPlan.create!(plan_data: { "composed_by" => "alpha", composer: "beta" })
          end
        end
      end
    RUBY

    # Provenance arm: index-assign and index-or-assign inside a persistence call.
    expect(scan.call(<<~RUBY).first[:provenance]).to eq({ "composed_by" => %w[gamma delta] })
      module Ai
        class IndexStamp
          def go
            ::Ai::GoalPlan.create!(x: 1)
            step.update!(config: { "composed_by" => "gamma" })
            other.update!(config: { "composed_by" => "delta" })
          end
        end
      end
    RUBY

    # Provenance arm: POSITIONAL stamper indirection — the shape the one
    # compliant composer uses.
    expect(scan.call(<<~RUBY).first[:provenance]).to eq({ "composed_by" => %w[deterministic llm] })
      module Ai
        class PositionalStamp
          def go
            ::Ai::GoalPlan.create!(x: 1)
            stamp!(steps, "deterministic")
            stamp! other, "llm"
          end

          def stamp!(steps, source)
            steps.each { |s| s["composed_by"] = source }
          end
        end
      end
    RUBY

    # Provenance arm: KEYWORD stamper indirection, and `def self.` form.
    expect(scan.call(<<~RUBY).first[:provenance]).to eq({ "composer" => %w[synthesized] })
      module Ai
        class KeywordStamp
          def go
            ::Ai::GoalPlan.create!(x: 1)
            stamp!(steps, source: "synthesized")
          end

          def self.stamp!(steps, source:)
            steps.each { |s| s["composer"] = source }
          end
        end
      end
    RUBY

    # An unrelated `composer:` kwarg outside any persistence call neither
    # certifies the composer nor reds it. `composer` is an ordinary word.
    expect(scan.call(<<~RUBY).first[:provenance]).to eq({})
      module Ai
        class Logs
          def go
            ::Ai::GoalPlan.create!(x: 1)
            Rails.logger.info(event: "composed", composer: "planner_v2")
          end
        end
      end
    RUBY

    # Two keys on ONE path is one value under each key, not two — conjunct B
    # groups by key precisely so this cannot buy the count.
    widest = scan.call(<<~RUBY).first[:provenance].values.map(&:size).max
      module Ai
        class TwoKeysOnePath
          def go
            ::Ai::GoalPlan.create!(plan_data: { "composed_by" => "llm", "composer" => "llm_v2" })
          end
        end
      end
    RUBY
    expect(widest).to eq(1)

    # A stamp whose value is a runtime expression is NOT a declaration, and is
    # not silently skipped either — the scan refuses to classify it.
    expect {
      scan.call(<<~RUBY)
        module Ai
          class DynamicStamp
            def go
              ::Ai::GoalPlan.create!(plan_data: { "composed_by" => mode.to_s })
            end
          end
        end
      RUBY
    }.to raise_error(/does not classify/)

    # A stamper called with a non-literal likewise refuses.
    expect {
      scan.call(<<~RUBY)
        module Ai
          class DynamicStamper
            def go
              ::Ai::GoalPlan.create!(x: 1)
              stamp!(steps, chosen_source)
            end

            def stamp!(steps, source)
              steps.each { |s| s["composed_by"] = source }
            end
          end
        end
      RUBY
    }.to raise_error(/does not classify|not declared in its source/)

    # A stamper with NO call site is a stamp nobody can read — refused rather
    # than reported as "stamps nothing", which would look like a fixable defect
    # in the composer instead of a blind spot in the scan.
    expect {
      scan.call(<<~RUBY)
        module Ai
          class OrphanStamper
            def go
              ::Ai::GoalPlan.create!(x: 1)
            end

            def stamp!(steps, source)
              steps.each { |s| s["composed_by"] = source }
            end
          end
        end
      RUBY
    }.to raise_error(/NO call site/)

    # A file that does not parse must raise, never yield zero members.
    expect {
      Tempfile.create([ "broken", ".rb" ]) do |f|
        f.write("class Ai::Broken\n  def go\n    ::Ai::GoalPlan.create!(\n")
        f.flush
        class_units(f.path)
      end
    }.to raise_error(/does not parse/)
  end
end

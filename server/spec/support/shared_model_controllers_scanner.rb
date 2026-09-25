# frozen_string_literal: true

require "find"
require "set"
require "yaml"

# SharedModelControllersScanner — support for
# spec/lint/shared_model_controllers_spec.rb (P2, fc-48).
#
# Finds every model constant referenced by two or more NON-INTERNAL
# controllers, across core and every checked-out extension. Static: a
# rubocop-ast walk over source, no Rails boot and no extension bundle.
#
#   - MODELS: every class defined under an app/models tree (concerns
#     excluded), named by the class's own lexical nesting in the file — so an
#     inflection such as Ai:: or Sdwan:: comes from the source, not from a
#     path guess.
#   - CONTROLLERS: every class under an app/controllers tree. Internal ones
#     (service-token worker traffic, which by design serves no user) do not
#     count: core knows Api::V1::Internal::*; an extension declares its own
#     internal namespaces in its registry file, and they apply only to
#     controllers in its own tree.
#   - A controller REFERENCES a model when a constant in its file, or in a
#     concern it includes, resolves to that model. Resolution follows the
#     lexical nesting (`Agent` inside `module Ai` tries Ai::Agent, then
#     Agent); a leading `::` is absolute.
#
# Where an entry belongs (EXTENSIONS KEEP THEIR OWN REGISTRY; CORE NAMES NONE):
#   - a model defined by an extension is listed in that extension's registry;
#   - a core model is listed in core when core and the public extensions alone
#     make it shared (they are present in every clone); otherwise the private
#     extension whose controllers make it shared lists it.
# So every list's staleness depends only on trees that are always checked out
# alongside it.
class SharedModelControllersScanner
  CORE_INTERNAL_NAMESPACES = [ "Api::V1::Internal" ].freeze

  # Shared reasons. A registry entry's reason is one of these keys or its own
  # sentence; either way every entry carries one.
  REASONS = {
    "tenancy" => "Identity/tenancy model: read by many controllers to scope, own or authorize their own resource; " \
                 "served by its own controller only.",
    "audit" => "Side record written by the action it records (an audit or event row), not a resource the " \
               "writing controllers serve.",
    "lookup" => "One controller serves it; the others only read it to scope, authorize or link their own resource.",
    "served_twice" => "Served (queried or written) by more than one controller. Consolidation into one home is " \
                      "reviewed in a P2 offer; the entry goes when that lands."
  }.freeze
  REGISTRY_RELATIVE_PATH = File.join("server", "spec", "fixtures", "shared_model_controllers.yml")

  Tree = Struct.new(:root, :rel, :kind, :internal_namespaces, :registry, keyword_init: true) do
    def core? = kind == :core
    def private? = kind == :private
  end

  Controller = Struct.new(:name, :tree, :file, keyword_init: true)

  attr_reader :trees

  # repo_root: the repository root. Trees are core (server/) plus every
  # extensions/<x> and extensions/private/<x> that has a server/app tree.
  def initialize(repo_root)
    @repo_root = repo_root
    @trees = discover_trees
  end

  # model name => [Controller, ...] for every model with >= 2 non-internal controllers
  def shared_models
    @shared_models ||= references.select { |_, ctrls| ctrls.size >= 2 }
  end

  # The tree whose list must carry `model`: see the class comment.
  def owner_tree(model)
    defining = model_trees[model]
    return defining unless defining&.core?

    public_count = shared_models[model].count { |c| !c.tree.private? }
    return defining if public_count >= 2

    shared_models[model].map(&:tree).find(&:private?)
  end

  # Merges core's entries with every extension registry:
  #   [ { model => [tree rel, reason] }, [ "Model (rel, rel)", ... listed more than once ] ]
  def listed_models(core_entries)
    sources = Hash.new { |h, k| h[k] = [] }
    core_entries.each { |model, reason| sources[model] << [ "server", reason ] }
    trees.reject(&:core?).each do |tree|
      Hash(tree.registry["shared_models"]).each { |model, reason| sources[model] << [ tree.rel, reason ] }
    end
    twice = sources.select { |_, s| s.size > 1 }.map { |model, s| "#{model} (#{s.map(&:first).join(', ')})" }.sort
    [ sources.transform_values(&:first), twice ]
  end

  # Problems with the internal_controller_namespaces an extension declares:
  # each must be narrower than Api::V1, match at least one controller in its
  # own tree (else it is stale), and match no controller in any other tree
  # (else it would exclude someone else's controllers).
  def namespace_problems
    problems = []
    trees.reject(&:core?).each do |tree|
      Array(tree.registry["internal_controller_namespaces"]).each do |ns|
        ns = ns.to_s
        if ns.split("::").size <= 2 || "Api::V1".start_with?(ns)
          problems << "#{tree.rel}: internal namespace #{ns} is Api::V1 or broader"
          next
        end
        under = ->(name) { name == ns || name.start_with?("#{ns}::") }
        own = controllers.select { |c| c.tree.equal?(tree) && under.call(c.name) }
        foreign = controllers.reject { |c| c.tree.equal?(tree) }.select { |c| under.call(c.name) }
        problems << "#{tree.rel}: internal namespace #{ns} matches no controller in its tree (stale)" if own.empty?
        foreign.each { |c| problems << "#{tree.rel}: internal namespace #{ns} also matches #{c.name} in #{c.tree.rel}" }
      end
    end
    problems
  end

  # Every controller class in every tree, internal ones included.
  def controllers
    @controllers ||= trees.flat_map do |tree|
      found = []
      each_ruby_file(File.join(tree.root, "server", "app", "controllers"), skip: %r{/concerns/}) do |file|
        class_names(parse(file)).each do |name|
          found << Controller.new(name: name, tree: tree, file: file.delete_prefix("#{@repo_root}/"))
        end
      end
      found
    end
  end

  def model_trees
    @model_trees ||= begin
      map = {}
      trees.each do |tree|
        each_ruby_file(File.join(tree.root, "server", "app", "models"), skip: %r{/concerns/}) do |file|
          class_names(parse(file)).each { |name| map[name] ||= tree }
        end
      end
      map
    end
  end

  private

  def discover_trees
    core_registry = nil # core's list lives in the spec itself
    found = [ Tree.new(root: @repo_root, rel: "server", kind: :core,
                       internal_namespaces: CORE_INTERNAL_NAMESPACES, registry: core_registry) ]
    ext_root = File.join(@repo_root, "extensions")
    return found unless Dir.exist?(ext_root)

    candidates = Dir.children(ext_root).sort.flat_map do |name|
      next [] unless File.directory?(File.join(ext_root, name))

      if name == "private"
        Dir.children(File.join(ext_root, name)).sort.map { |p| [ File.join(ext_root, name, p), "extensions/private/#{p}", :private ] }
      else
        [ [ File.join(ext_root, name), "extensions/#{name}", :public ] ]
      end
    end
    candidates.each do |root, rel, kind|
      next unless Dir.exist?(File.join(root, "server", "app"))

      registry = load_registry(root, rel)
      internal = CORE_INTERNAL_NAMESPACES + Array(registry["internal_controller_namespaces"])
      found << Tree.new(root: root, rel: rel, kind: kind, internal_namespaces: internal, registry: registry)
    end
    found
  end

  def load_registry(root, rel)
    path = File.join(root, REGISTRY_RELATIVE_PATH)
    return {} unless File.exist?(path)

    data = YAML.safe_load(File.read(path)) || {}
    raise ArgumentError, "#{rel}/#{REGISTRY_RELATIVE_PATH} must be a mapping" unless data.is_a?(Hash)

    data
  end

  # model name => [Controller, ...] (non-internal controllers referencing it)
  def references
    @references ||= begin
      models = model_trees.keys.to_set
      concern_refs = {}
      trees.each do |tree|
        each_ruby_file(File.join(tree.root, "server", "app", "controllers")) do |file|
          next unless file.include?("/concerns/")

          ast = parse(file)
          module_names(ast).each { |m| concern_refs[m] = [ ast, models ] }
        end
      end

      result = Hash.new { |h, k| h[k] = [] }
      trees.each do |tree|
        each_ruby_file(File.join(tree.root, "server", "app", "controllers"), skip: %r{/concerns/}) do |file|
          ast = parse(file)
          class_names(ast).each do |controller|
            next if tree.internal_namespaces.any? { |ns| controller == ns || controller.start_with?("#{ns}::") }

            refs = model_refs(ast, models)
            included_modules(ast).each do |mod|
              concern = concern_refs.keys.find { |c| c == mod || c.end_with?("::#{mod}") }
              refs |= model_refs(concern_refs[concern][0], models) if concern
            end
            record = Controller.new(name: controller, tree: tree, file: file.delete_prefix("#{@repo_root}/"))
            refs.each { |m| result[m] << record }
          end
        end
      end
      result
    end
  end

  def each_ruby_file(dir, skip: nil)
    return unless Dir.exist?(dir)

    Find.find(dir) do |path|
      next unless path.end_with?(".rb") && File.file?(path)
      next if skip && path.match?(skip)

      yield path
    end
  end

  def parse(file)
    require "rubocop-ast"
    RuboCop::AST::ProcessedSource.new(File.read(file), RUBY_VERSION.to_f, file).ast
  end

  def definitions(ast, types)
    return [] unless ast

    names = []
    walk_defs(ast, [], types, names)
    names
  end

  def walk_defs(node, nesting, types, out)
    return unless node.is_a?(RuboCop::AST::Node)

    if %i[class module].include?(node.type)
      name = [ *nesting, const_source(node.children[0]) ].join("::")
      out << name if types.include?(node.type)
      node.children.drop(1).each { |c| walk_defs(c, [ name ], types, out) }
    else
      node.children.each { |c| walk_defs(c, nesting, types, out) }
    end
  end

  def class_names(ast) = definitions(ast, %i[class])
  def module_names(ast) = definitions(ast, %i[module])

  def const_source(node)
    return "" unless node&.type == :const

    scope, name = node.children
    scope && scope.type != :cbase ? "#{const_source(scope)}::#{name}" : name.to_s
  end

  # Model names the constants in `ast` resolve to, by lexical nesting.
  def model_refs(ast, models)
    found = Set.new
    collect_refs(ast, [], models, found)
    found
  end

  def collect_refs(node, nesting, models, found)
    return unless node.is_a?(RuboCop::AST::Node)

    if %i[class module].include?(node.type)
      name = [ *nesting.last(1), const_source(node.children[0]) ].reject(&:empty?).join("::")
      collect_refs(node.children[1], nesting, models, found) if node.type == :class # superclass
      node.children.drop(node.type == :class ? 2 : 1).each { |c| collect_refs(c, nesting + [ name ], models, found) }
      return
    end

    if node.type == :const && node.parent&.type != :const
      written = const_source(node)
      absolute = node.each_node(:cbase).any?
      candidates = absolute ? [ written ] : [ *nesting.reverse.flat_map { |ns| lexical_prefixes(ns).map { |p| "#{p}::#{written}" } }, written ]
      hit = candidates.find { |c| models.include?(c) }
      found << hit if hit
      return
    end

    node.children.each { |c| collect_refs(c, nesting, models, found) }
  end

  # "A::B::C" => ["A::B::C", "A::B", "A"]
  def lexical_prefixes(ns)
    parts = ns.split("::")
    parts.size.downto(1).map { |i| parts.first(i).join("::") }
  end

  def included_modules(ast)
    mods = []
    ast&.each_node(:send) do |send|
      next unless send.method_name == :include && send.receiver.nil?

      send.arguments.each { |a| mods << const_source(a) if a.type == :const }
    end
    mods
  end
end

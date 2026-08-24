# frozen_string_literal: true

module Permissions
  # Programmatic permission catalog DSL.
  #
  # Generates permission names + role grants from compact resource→action
  # declarations, with namespace prefixing (extension slug, mirroring the
  # db-table / Gemfile.private prefix convention) and three-tier handling.
  # Replaces hand-maintained "name" => "desc" hashes.
  #
  # CORE usage (server/config/permissions.rb) — accumulates into CORE_PERMISSIONS
  # (and thus the dynamic Permissions.all_permissions) and is merged into every
  # role by permissions_for_role:
  #   Permissions.define(namespace: "ai") do
  #     resource :agents, actions: :crud,
  #              grant: { manager: %i[read create update], owner: :all, admin: :all }
  #   end
  #
  # EXTENSION usage (extensions/<x>/server/lib/<engine>/engine.rb) — routes
  # through the existing register_permissions / register_role_permissions seam so
  # grants survive Role#sync_permissions!'s destructive replace:
  #   Permissions.register_catalog(namespace: "system") do
  #     resource :workers, actions: %i[read create update delete],
  #              grant: { admin: :all, system_worker: %i[read] }
  #   end
  #
  # The namespace is MANDATORY for extensions (register_catalog) — enforced so an
  # extension can never register an unprefixed (core-colliding) permission.
  class Catalog
    # Full CRUD taxonomy expanded by `actions: :crud`.
    CRUD = %i[read create update delete manage].freeze

    VERBS = {
      read: "View", create: "Create", update: "Update",
      delete: "Delete", manage: "Manage"
    }.freeze

    def initialize(namespace: nil, tier: :resource)
      @namespace = namespace&.to_s
      @tier = tier
      @permissions = {}
      @grants = Hash.new { |h, k| h[k] = [] }
    end

    # Declare a resource and generate one permission per action.
    #   actions:      :crud | %i[read create ...]   (any action verbs)
    #   grant:        { role => :all | %i[read ...] }
    #   descriptions: { action => "custom text" }    (else auto-generated)
    #   tier:         override the catalog's default tier for this resource
    def resource(name, actions:, grant: {}, descriptions: {}, tier: nil)
      action_list = actions == :crud ? CRUD : Array(actions)
      action_list.each do |action|
        full = name_for(name, action, tier || @tier)
        @permissions[full] = descriptions[action.to_sym] ||
                             descriptions[action.to_s] ||
                             default_description(name, action)
        grant.each do |role, granted|
          next unless granted == :all || Array(granted).map(&:to_sym).include?(action.to_sym)

          @grants[role.to_s] << full
        end
      end
    end

    # Escape hatch for a single irregular permission (non-CRUD name).
    def permission(full_name, description, grant: {})
      @permissions[full_name.to_s] = description
      grant.each_key { |role| @grants[role.to_s] << full_name.to_s }
    end

    def result
      { permissions: @permissions, grants: @grants.transform_values(&:uniq) }
    end

    private

    def name_for(resource, action, tier)
      segments = []
      segments << "admin"  if tier == :admin
      segments << "system" if tier == :system
      segments << @namespace unless @namespace.nil? || @namespace.empty?
      segments << resource.to_s
      segments << action.to_s
      segments.join(".")
    end

    def default_description(resource, action)
      subject = [@namespace, resource].compact.join(" ").tr("._", " ").strip
      verb = VERBS[action.to_sym] || action.to_s.tr("_", " ").capitalize
      "#{verb} #{subject}".squeeze(" ")
    end
  end

  # Programmatic ROLE catalog DSL — the role twin of Catalog.
  #
  # Lets an extension register NEW global roles (the way Catalog lets it register
  # new permissions), keyed by a mandatory namespace (extension slug) so a role's
  # stored name is always `<namespace>.<short>` (mirrors the db-table / permission
  # prefix convention). Core roles still live in Permissions::ROLES; extension
  # roles accumulate here and join via Permissions.all_roles.
  #
  # EXTENSION usage (extensions/<x>/server/lib/<engine>/engine.rb):
  #   Permissions.register_roles(namespace: "system") do
  #     role "operator", role_type: "admin",
  #          display_name: "System Operator",
  #          description: "Manages system workers",
  #          permissions: %w[system.workers.read system.workers.update]
  #   end
  # => stored as { "system.operator" => { display_name:, description:,
  #                role_type:, permissions:, is_system:, immutable: } }
  class RoleCatalog
    ROLE_TYPES = %w[user admin system].freeze

    def initialize(namespace:)
      @namespace = namespace.to_s
      @roles = {}
    end

    # Declare one role. `short` is prefixed with the namespace if it isn't
    # already (so callers may pass either "viewer" or "<namespace>.viewer").
    #   role_type:    user | admin | system  (required; validated)
    #   display_name: human label (defaults to a titleized short name)
    #   description:  optional blurb
    #   permissions:  array of permission names this role is granted
    #   is_system:    flag the role as system-owned (also implied by role_type)
    #   immutable:    flag the role as non-editable
    def role(short, role_type:, display_name: nil, description: nil, permissions: [], is_system: false, immutable: false)
      type = role_type.to_s
      unless ROLE_TYPES.include?(type)
        raise ArgumentError, "register_roles(#{@namespace.inspect}): role_type must be one of #{ROLE_TYPES.join('/')}, got #{role_type.inspect}"
      end

      name = prefixed(short)
      @roles[name] = {
        display_name: display_name || default_display_name(short),
        description: description,
        role_type: type,
        permissions: Array(permissions).map(&:to_s).uniq,
        is_system: is_system || type == "system",
        immutable: immutable
      }
    end

    def result = @roles

    private

    # Prefix the short name with the namespace unless already prefixed.
    def prefixed(short)
      s = short.to_s
      prefix = "#{@namespace}."
      s.start_with?(prefix) ? s : "#{prefix}#{s}"
    end

    def default_display_name(short)
      short.to_s.split(/[.\-_]/).last.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end
  end

  # Accumulators for core (in-file) catalog declarations.
  @catalog_permissions = {}
  @catalog_grants = Hash.new { |h, k| h[k] = [] }
  # Permissions (core- or extension-registered) that require 2FA to hold.
  # Extension-registered GLOBAL roles (the role twin of @extension_permissions).
  # String-keyed `<namespace>.<short>` => role config Hash. A disabled extension
  # never runs its initializer, so it is naturally excluded — mirroring how
  # @extension_permissions joins via Permissions.all_permissions. Initialized here
  # (beside the other singleton ivars, before permissions.rb's body runs) so it is
  # readable from both files.
  @extension_roles = {}

  class << self
    # Core sink — merge generated permissions into CORE_PERMISSIONS (via the
    # module body) and into every role (via permissions_for_role).
    def define(namespace: nil, tier: :resource, &blk)
      catalog = Catalog.new(namespace: namespace, tier: tier)
      catalog.instance_eval(&blk)
      res = catalog.result
      @catalog_permissions.merge!(res[:permissions])
      res[:grants].each { |role, names| @catalog_grants[role].concat(names) }
      res
    end

    def catalog_permissions = @catalog_permissions
    def catalog_grants = @catalog_grants

    # Extension sink — route through the register seam. Namespace mandatory.
    def register_catalog(namespace:, tier: :resource, &blk)
      if namespace.nil? || namespace.to_s.empty?
        raise ArgumentError, "register_catalog requires a namespace (extension slug) prefix"
      end

      catalog = Catalog.new(namespace: namespace, tier: tier)
      catalog.instance_eval(&blk)
      res = catalog.result

      # Invariant: an extension may only register permissions under its own
      # namespace (mirrors the db-table prefix / core-purity rule). The leading
      # `admin.`/`system.` tier prefix is allowed before the namespace. Catches
      # escape-hatch `permission "..."` names that drift outside the prefix.
      allowed = /\A(admin\.|system\.)?#{Regexp.escape(namespace.to_s)}\./
      stray = res[:permissions].keys.reject { |n| n.match?(allowed) }
      unless stray.empty?
        raise ArgumentError, "register_catalog(#{namespace.inspect}): permissions must be prefixed by the extension namespace; stray: #{stray.inspect}"
      end

      register_permissions(res[:permissions])
      res[:grants].each { |role, names| register_role_permissions(role, names) }
      res
    end

    def extension_roles = @extension_roles

    # Extension sink for NEW global roles — the role twin of register_catalog.
    # Namespace mandatory; every role's stored name is forced under the
    # `<namespace>.` prefix by RoleCatalog#role (an extension can never register
    # an unprefixed, core-colliding role). Idempotent: re-registering the same
    # role name+config is a no-op merge. Roles seed as GLOBAL (account_id nil)
    # via Role.sync_from_config!, which iterates Permissions.all_roles.
    def register_roles(namespace:, &blk)
      if namespace.nil? || namespace.to_s.empty?
        raise ArgumentError, "register_roles requires a namespace (extension slug) prefix"
      end

      catalog = RoleCatalog.new(namespace: namespace)
      catalog.instance_eval(&blk)
      @extension_roles.merge!(catalog.result)
    end
  end
end

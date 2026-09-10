# frozen_string_literal: true

module Ai
  module Tools
    # IDENTITY OVER MCP IS READ-ONLY (design decision 4, audit remedy 16).
    #
    # Users, roles, permissions and the audit log had ZERO MCP verbs while REST
    # exposed full CRUD on all four. That read as an omission rather than a
    # boundary, so the campaign settled it deliberately: agents may READ
    # identity; every WRITE — create a user, assign a role, grant a permission,
    # cleanup the audit log — stays operator-only, through REST and the console.
    #
    # The asymmetry is the point. An agent that can read the audit log can
    # explain what happened; an agent that can assign itself a role has closed
    # the loop on its own authority, which is the one loop this platform must
    # not close. The same reasoning already keeps `respond_to_approval` out of
    # the surface (design §5.1).
    #
    # ── PERMISSIONS: THE REST DOOR'S OWN NAMES, NEVER WIDER ─────────────────
    #
    # Each verb floors on the permission the matching REST controller checks,
    # so this tool can never be a way around a gate a person already passes:
    #
    #   list_users / get_user  → admin.user.read   (users_controller.rb:9)
    #   list_roles             → admin.role.read   (roles_controller.rb:6)
    #   list_permissions       → admin.role.read   (see the note below)
    #   list_audit_logs        → audit.read        (audit_logs_controller.rb:5)
    #
    # `list_permissions` is deliberately NARROWER than its REST twin.
    # `PermissionsController#require_admin_permission` accepts any of
    # `admin.role.read`, `admin.access` or `system.admin`; a tool gate is one
    # name, and the tightest of the three is the right one to pick. A
    # `system.admin` holder still passes (User#has_permission? short-circuits on
    # it), so the only caller who can read the catalog over REST but not here
    # holds `admin.access` alone. Narrower is the safe direction for a
    # difference; wider would never be.
    #
    # ── WHAT IS DELIBERATELY NOT SERIALIZED ─────────────────────────────────
    #
    # See #serialize_user and #serialize_audit_log. The audit log's `metadata`
    # column is the one that matters and it is omitted — read the comment there
    # before adding it back.
    class IdentityReadTool < BaseTool
      REQUIRED_PERMISSION = "admin.user.read"

      ACTION_PERMISSIONS = {
        "list_users" => "admin.user.read",
        "get_user" => "admin.user.read",
        "list_roles" => "admin.role.read",
        "list_permissions" => "admin.role.read",
        "list_audit_logs" => "audit.read"
      }.freeze

      declare_action "list_users", mutating: false
      declare_action "get_user", mutating: false
      declare_action "list_roles", mutating: false
      declare_action "list_permissions", mutating: false
      declare_action "list_audit_logs", mutating: false

      def self.definition
        {
          name: "identity_read",
          description: "Read-only view of identity: the account's users, the roles they can hold, " \
                       "the permission catalog and the audit log. Identity WRITES are operator-only.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "list_users" => {
            description: "List the users in this account with their status, roles and permission counts. " \
                         "Never returns password material, tokens or 2FA secrets. Read-only; " \
                         "creating, suspending and role-assigning users are operator-only. " \
                         "Requires admin.user.read.",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status (active, inactive, suspended)" },
              email: { type: "string", required: false,
                       description: "Exact email match (case-insensitive). There is deliberately no " \
                                    "name/substring search — see the tool source: `name` is encrypted " \
                                    "non-deterministically and cannot be searched in the database." },
              **PAGINATION_PARAMETERS
            }
          },
          "get_user" => {
            description: "One user with their roles and the permission names those roles confer. " \
                         "Requires admin.user.read.",
            parameters: {
              id: { type: "string", required: true, description: "User id (must be in this account)" }
            }
          },
          "list_roles" => {
            description: "Roles available to this account: the code-defined GLOBAL roles plus any " \
                         "account-scoped custom roles, each with its permission names. " \
                         "Requires admin.role.read.",
            parameters: {
              scope: { type: "string", required: false, enum: %w[all global account],
                       description: "all (default) | global (code-defined) | account (custom)" },
              **PAGINATION_PARAMETERS
            }
          },
          "list_permissions" => {
            description: "The code-defined permission catalog — every permission name the platform " \
                         "recognizes, with its description. This is a CATALOG read, not a grant: it " \
                         "says what exists, never who holds it. Requires admin.role.read.",
            parameters: {
              prefix: { type: "string", required: false, description: "Only names starting with this prefix (e.g. \"ai.\")" }
            }
          },
          "list_audit_logs" => {
            description: "Recent audit-log rows for this account: who did what to which resource, when, " \
                         "from where, at what risk level. An agent that WRITES audit rows should be able " \
                         "to read them. The unfiltered `metadata` column is never returned (see the tool " \
                         "source for why). Requires audit.read.",
            parameters: {
              # NOT named `action`: params[:action] is the tool's own dispatch
              # key, so an `action` filter here would be shadowed by the verb
              # name and silently match nothing.
              audit_action: { type: "string", required: false, description: "Exact audited action name (e.g. \"ai.providers.read\")" },
              resource_type: { type: "string", required: false, description: "Filter by audited resource class" },
              user_id: { type: "string", required: false, description: "Filter to one actor" },
              risk_level: { type: "string", required: false, description: "Filter by risk level" },
              since: { type: "string", required: false, description: "ISO8601 lower bound on created_at" },
              **PAGINATION_PARAMETERS
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        return error_result("permission denied: #{required_perm_for(action)} required") unless action_permitted?(action)

        case action
        when "list_users"        then list_users(params)
        when "get_user"          then get_user(params)
        when "list_roles"        then list_roles(params)
        when "list_permissions"  then list_permissions(params)
        when "list_audit_logs"   then list_audit_logs(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

      # ── users ─────────────────────────────────────────────────────────────

      def list_users(params)
        scope = account.users
        scope = scope.where(status: params[:status].to_s) if params[:status].present?
        # EXACT match only, and only on email.
        #
        # `User` encrypts `email` DETERMINISTICALLY (downcase: true) and `name`
        # NON-deterministically (user.rb:8-9). Equality on email therefore works
        # — Rails encrypts the needle the same way — while any LIKE, on either
        # column, matches ciphertext and silently returns zero rows. A
        # substring search here would have looked correct, run without error,
        # and always answered "no such user", which is the worst shape a filter
        # can take. Offering none is honest; offering a broken one is not.
        scope = scope.where(email: params[:email].to_s.downcase) if params[:email].present?

        paginated_result(:users, scope.includes(:roles), params, sort: :id, direction: :asc) do |row|
          serialize_user(row)
        end
      end

      def get_user(params)
        row = account.users.includes(roles: :role_permissions).find_by(id: params[:id].to_s)
        return error_result("user not found in this account") unless row

        success_result(user: serialize_user(row, include_permissions: true))
      end

      # NOTHING AUTHENTICATION-SHAPED CROSSES THIS BOUNDARY.
      #
      # `User` carries `password_digest`, the 2FA secret and its recovery
      # codes, session and reset tokens, and the JWT permission snapshot.
      # None of them are here, and this is an ALLOW-LIST rather than a
      # `.except(...)` on purpose: a column added to `users` tomorrow does not
      # appear in this payload by default. A denylist would have to be
      # remembered; an allowlist cannot be forgotten.
      def serialize_user(row, include_permissions: false)
        payload = {
          id: row.id,
          name: row.name,
          email: row.email,
          status: row.status,
          email_verified: row.email_verified_at.present?,
          created_at: iso(row.created_at),
          last_login_at: iso(row.try(:last_login_at)),
          roles: row.roles.map { |role| { id: role.id, name: role.name, display_name: role.display_name } }
        }
        # The NAMES a user's roles confer — still a read about authority, never
        # a way to change it.
        payload[:permissions] = row.roles.flat_map { |role| role.role_permissions.map(&:permission_name) }.uniq.sort if include_permissions
        payload
      end

      # ── roles ─────────────────────────────────────────────────────────────

      def list_roles(params)
        requested = params[:scope].presence&.to_s || "all"
        # Global roles are code-defined and account_id-nil; custom roles belong
        # to one account. "all" is both, because a user in this account can
        # hold either and a list that showed one half would mislead.
        scope = case requested
        when "global"  then ::Role.where(account_id: nil)
        when "account" then ::Role.where(account_id: account.id)
        when "all"     then ::Role.where(account_id: [ nil, account.id ])
        else return error_result("scope must be one of: all, global, account")
        end

        paginated_result(:roles, scope.includes(:role_permissions), params, sort: :id, direction: :asc) do |role|
          {
            id: role.id,
            name: role.name,
            display_name: role.display_name,
            description: role.description,
            role_type: role.role_type,
            scope: role.account_id.nil? ? "global" : "account",
            is_system: role.is_system,
            immutable: role.immutable,
            permissions: role.role_permissions.map(&:permission_name).sort
          }
        end
      end

      # ── permission catalog ────────────────────────────────────────────────

      # The catalog is CODE, not rows (config/permissions.rb): a dynamic union
      # of core plus whatever extensions are loaded. So this reads the same
      # source PermissionsController does rather than querying a table that
      # does not exist.
      def list_permissions(params)
        names = ::Permissions.all_permissions
        prefix = params[:prefix].to_s
        names = names.select { |name, _| name.start_with?(prefix) } if prefix.present?

        success_result(
          permissions: names.keys.sort.map { |name| { name: name, description: names[name] } },
          count: names.size,
          prefix: prefix.presence,
          source: "code-defined catalog (config/permissions.rb + loaded extensions)"
        )
      end

      # ── audit log ─────────────────────────────────────────────────────────

      def list_audit_logs(params)
        scope = ::AuditLog.where(account_id: account.id)
        scope = scope.where(action: params[:audit_action].to_s) if params[:audit_action].present?
        scope = scope.where(resource_type: params[:resource_type].to_s) if params[:resource_type].present?
        scope = scope.where(user_id: params[:user_id].to_s) if params[:user_id].present?
        scope = scope.where(risk_level: params[:risk_level].to_s) if params[:risk_level].present?
        if params[:since].present?
          # STRICT ISO8601, not Time.zone.parse. `Time.zone.parse("last
          # tuesday")` happily returns a Time, so a fuzzy bound would silently
          # filter to a date the caller never asked for — worse than refusing.
          since = begin
            Time.iso8601(params[:since].to_s)
          rescue ArgumentError, TypeError
            nil
          end
          return error_result("since must be an ISO8601 timestamp (e.g. 2026-09-10T00:00:00Z)") if since.nil?

          scope = scope.where(created_at: since..)
        end

        paginated_result(:audit_logs, scope, params, sort: :id, direction: :desc) do |row|
          serialize_audit_log(row)
        end
      end

      # `metadata` IS NOT RETURNED, AND THAT IS A SECURITY DECISION.
      #
      # AuditLog runs `before_validation :redact_secret_values`, which masks
      # password digests, every `encrypts`-backed attribute and everything in
      # `filter_attributes` — but it covers `old_values` and `new_values` ONLY
      # (audit_log.rb:103-107 → Auditable.redact_values). `metadata` has no
      # filter at all, and writers merge caller-supplied hashes into it
      # wholesale (`AuditLog.log_action` merges `options[:metadata]`;
      # `Ai::SensitiveAccessAudit` writes a `context` hash built from caller
      # params). There is no known writer that puts a credential there today —
      # the risk is STRUCTURAL, which is exactly the kind that arrives later
      # via a call site nobody re-reads.
      #
      # `old_values` / `new_values` ARE returned: they carry the platform's own
      # redaction, applied at write time and covered by the integrity hash, so
      # they are exactly as safe here as on the REST surface a person already
      # uses. If `metadata` ever gains the same filter, add it back and say so
      # in the same change.
      def serialize_audit_log(row)
        {
          id: row.id,
          action: row.action,
          resource_type: row.resource_type,
          resource_id: row.resource_id,
          user_id: row.user_id,
          severity: row.severity,
          risk_level: row.risk_level,
          source: row.source,
          ip_address: row.ip_address,
          request_id: row.request_id,
          old_values: row.old_values,
          new_values: row.new_values,
          sequence_number: row.sequence_number,
          created_at: iso(row.created_at)
        }
      end

      def iso(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end
    end
  end
end

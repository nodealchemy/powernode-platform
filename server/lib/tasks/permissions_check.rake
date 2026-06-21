# frozen_string_literal: true

# Guardrail: every permission string ENFORCED in code must be DEFINED in the
# permission catalog (core + loaded extensions). Prevents the "enforced-but-
# undefined" drift the 0.4.0 permission standardization fixed from regressing.
#
#   bundle exec rails permissions:check         # current build mode
#   (run full mode to cover private extensions:)
#   BUNDLE_GEMFILE=Gemfile.private POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 \
#     bundle exec rails permissions:check
#
# Scans only core + ENABLED extensions (disabled extensions' files are skipped,
# so their perms aren't false-flagged). Names no extension — roots are derived
# from the loaded ExtensionRegistry.
namespace :permissions do
  desc "Assert every enforced permission string is defined in the catalog"
  task check: :environment do
    require "set"

    # Dotted lowercase token that looks like a permission name.
    perm_re = /['"`]([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)['"`]/
    backend_carrier = /\b(?:has_permission\?|require_permission|require_any_permission|require_all_permissions|authorize_worker_permission!)\b/
    frontend_carrier = /\b(?:hasPermission|hasPermissions|hasAnyPermission|hasAllPermissions|hasAccess|requirePermission)\b|requiredPermissions|permissions?:/

    # Non-permission false positives (wildcards, role names, test sentinels).
    deny = %w[anything.anything users.anything system.* *.* account.owner account.admin
              account.manager account.member billing.manager analytics.reader api.developer].to_set

    # Roots: core + each loaded (enabled) extension. Derived dynamically.
    roots = [Rails.root]
    if defined?(Powernode::ExtensionRegistry)
      Powernode::ExtensionRegistry.each { |_slug, ext| roots << ext[:engine].root rescue nil }
    end
    roots = roots.compact.uniq

    enforced = Set.new
    scan = lambda do |globs, carrier|
      globs.each do |g|
        Dir.glob(g).each do |f|
          next if f.include?("/spec/") || f.include?("/test") || f.end_with?(".test.tsx", ".test.ts")

          File.foreach(f) do |line|
            next unless line.match?(carrier)

            line.scan(perm_re) { |m| enforced << m[0] }
          end
        rescue StandardError
          next
        end
      end
    end

    roots.each do |r|
      scan.call(["#{r}/app/**/*.rb", "#{r}/server/app/**/*.rb"], backend_carrier)
      scan.call(["#{r}/frontend/src/**/*.{ts,tsx}", "#{r}/../frontend/src/**/*.{ts,tsx}"], frontend_carrier)
    end

    defined = Permissions.all_permissions.keys.to_set
    all_missing = (enforced - defined - deny).reject { |p| p.end_with?(".*") }.sort
    # docker/swarm/kubernetes perms are intentionally DEFERRED to the container-
    # plane relocation epic (they move into the system extension as system.*).
    # Report them, don't fail the build on them.
    deferred = all_missing.grep(/\A(docker|swarm|kubernetes)\./)
    missing = all_missing - deferred

    puts "permissions:check — defined=#{defined.size} enforced=#{enforced.size}"
    puts "ℹ️  deferred (container-plane epic, not failing): #{deferred.join(', ')}" unless deferred.empty?
    if missing.empty?
      puts "✅ all enforced permissions are defined (#{deferred.size} deferred)"
    else
      puts "❌ #{missing.size} enforced-but-undefined permission(s):"
      missing.each { |m| puts "   - #{m}" }
      abort("permissions:check failed")
    end
  end
end

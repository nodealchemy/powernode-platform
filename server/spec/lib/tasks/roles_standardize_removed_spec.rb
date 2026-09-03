# frozen_string_literal: true

require "spec_helper"

# Removal guard for the `roles` rake namespace (IMP-6477865679f4).
#
# WHAT WAS REMOVED AND WHY. lib/tasks/standardize_roles.rake defined
# `roles:standardize` and `roles:status`. `roles:standardize` was a second
# config->DB path for global-role grants and a strictly worse one than
# Role.sync_from_config!, destructive in two independent ways (line numbers below
# are in the deleted file, recoverable via
# `git show <pre-removal-sha>:server/lib/tasks/standardize_roles.rake`):
#
#   * :58 passed `config[:permissions]` to role.sync_permissions! where
#     Role.sync_from_config! correctly passes
#     Permissions.permissions_for_role(name) (app/models/role.rb:78).
#     permissions_for_role merges three sources — the role's own declared list,
#     @extension_role_permissions, and @catalog_grants
#     (config/permissions.rb:1195-1200) — and Role#sync_permissions! is FULL
#     DESTRUCTIVE reconciliation (app/models/role.rb:179-180:
#     `to_remove = current - desired`, then delete_all). So the missing two
#     sources were DELETED: every grant contributed by
#     register_role_permissions or a catalog-DSL `grant:`.
#   * :109 ran `Role.where.not(name: standard_role_names).each { ... destroy! }`
#     with NO account_id scope, destroying any role outside the catalog that had
#     no users or workers — including account-scoped custom roles created through
#     Api::V1::RolesController.
#
#   (:42 also used Role.find_or_create_by!(name:) with no account_id, where
#   app/models/role.rb:53 scopes to (name:, account_id: nil). Role uniqueness is
#   account-scoped, so an account-scoped role sharing a catalog name could be
#   matched and then mutated.)
#
# No CODE PATH ever invoked it, and no commit ever added a caller; the only
# prescription was server/docs/ROLE_STANDARDIZATION.md's own "Database
# Management" section, rewritten in the same change. `roles:status` was a
# read-only reporter removed with it, superseded by
# `permissions:role_grant_drift`.
#
# The working mechanism is Permissions::RoleGrantReconciler — absence-only, run
# every boot from the powernode-hub-backend module's rails-start.sh:356-357.
#
# SCOPE: TREE-scoped, not heading- or file-scoped.
#   * definition check — every `lib/tasks/**/*.rake` and `Rakefile` in the REPO,
#     core AND extensions (an extension can define into the same rake namespace).
#   * reference check — every .rb/.rake/.md/.sh/.yml/.yaml/.json/.erb file and
#     every Rakefile/Dockerfile/Makefile in the repo, so shell scripts (module
#     rootfs), CI configs under .gitea/, the top-level docs/ tree, worker/ and
#     the extensions are all covered. server/spec/ is excluded because this file
#     names what it guards; .claude/ is pruned because it holds a separate git
#     worktree checked out at another branch.
#
# ANTI-VACUITY, three separate properties:
#   1. the scan must have read the tree — floors on file counts plus named
#      SENTINEL files that must be in the scanned set and must contain strings
#      they really contain;
#   2. the DETECTORS must be able to fire — each predicate is exercised against
#      synthetic positive and negative strings (a scanner that reads every byte
#      with a predicate that can never match is the failure mode a sentinel
#      alone does not catch);
#   3. therefore it fails if the task file returns anywhere in the repo, under
#      any file name, rather than passing because a glob matched nothing.
#
# WHAT THIS DOES NOT COVER, stated rather than implied:
#   * a definition split across two files (`namespace :roles` in one, `task
#     :standardize` in another) — rake merges namespaces across files, and the
#     definition predicate is AND'ed per file;
#   * the same destructive body reintroduced under a different task name;
#   * a prose mention of the task name with NO rake/rails verb in front of it —
#     deliberately allowed, because the changelog entry recording the removal
#     must be free to name what it removed. The reference check bans the
#     INVOCATION form and the deleted file's path, not the string;
#   * binary/other file types, and the pruned directories listed below.
RSpec.describe "roles rake namespace removal" do
  repo_root = File.expand_path("../../../..", __dir__)
  self_path = File.expand_path(__FILE__)

  # Locals, not constants: a constant assigned in an RSpec.describe block lands on
  # Object and can clobber a same-named constant in another spec, which surfaces
  # only as an order-dependent flake.
  pruned_dirs = %w[.git .claude node_modules vendor tmp log coverage dist build .next .bundle public].freeze
  scanned_exts = %w[.rb .rake .md .sh .bash .yml .yaml .json .erb].freeze
  scanned_names = %w[Rakefile Dockerfile Makefile].freeze

  # Built at runtime so this file's own source cannot satisfy a scan of itself
  # were the exclusions below ever dropped.
  task_name = ["roles", "standardize"].join(":")
  file_stem = "standardize_roles"

  # --- detectors, hoisted so the positive-control example can exercise them ---

  # `namespace :roles` / `namespace "roles"` / `namespace('roles')`, any spacing.
  namespace_re = /\bnamespace\s*\(?\s*(?::roles\b|["']roles["'])/
  # `task standardize:` / `task :standardize` / `task "standardize"` /
  # `task(:standardize)` / `task :standardize => :environment`.
  task_re = /\btask\s*\(?\s*(?::?standardize\b|["']standardize["'])/

  defines_task = lambda do |body|
    body.match?(namespace_re) && body.match?(task_re)
  end

  # A PRESCRIPTION: the task name in command position behind a rake/rails verb,
  # with or without `bundle exec`. This is the property the guard is actually
  # about — a doc, script or CI config telling someone to RUN the deleted
  # destructive command. A bare historical mention of the name (the changelog
  # entry recording its removal) is legitimate and must stay allowed, so the
  # detector keys on the verb, not the name.
  prescribes_task = Regexp.new("(?:bundle\\s+exec\\s+)?(?:rake|rails)\\s+#{Regexp.escape(task_name)}")

  names_task = lambda do |body|
    body.match?(prescribes_task) || body.include?(file_stem)
  end

  # --- file sets -------------------------------------------------------------

  walk = lambda do |root|
    out = []
    stack = [root]
    until stack.empty?
      dir = stack.pop
      Dir.children(dir).each do |entry|
        path = File.join(dir, entry)
        if File.directory?(path)
          next if pruned_dirs.include?(entry)
          next if File.symlink?(path)

          stack << path
        elsif scanned_exts.include?(File.extname(entry)) || scanned_names.include?(entry)
          out << path
        end
      end
    end
    out.sort
  end

  all_files = walk.call(repo_root)

  rake_files = all_files.select do |p|
    p.end_with?(".rake") || File.basename(p) == "Rakefile"
  end

  reference_files = all_files.reject do |p|
    p == self_path || p.start_with?(File.join(repo_root, "server", "spec") + File::SEPARATOR)
  end

  describe "detectors (positive control)" do
    it "fire on a reintroduction and stay silent on unrelated rake code" do
      [
        "namespace :roles do\n  task standardize: :environment do\n  end\nend",
        "namespace(\"roles\") do\n  task(:standardize) do\n  end\nend",
        "namespace 'roles' do\n  task \"standardize\" => :environment do\n  end\nend",
        "namespace  :roles do\n  task :standardize => :environment do\n  end\nend"
      ].each do |sample|
        expect(defines_task.call(sample)).to be(true),
          "definition detector failed to fire on: #{sample.inspect}"
      end

      [
        "namespace :permissions do\n  task reconcile_role_grants: :environment do\n  end\nend",
        "namespace :roles do\n  task list: :environment do\n  end\nend",
        "namespace :seed do\n  task standardize_addresses: :environment do\n  end\nend"
      ].each do |sample|
        expect(defines_task.call(sample)).to be(false),
          "definition detector false-positived on: #{sample.inspect}"
      end

      [
        "run `rake #{task_name}` first",
        "bundle exec rake #{task_name}",
        "bundle exec rails #{task_name}",
        "  - run: bundle exec rails #{task_name}",
        "lib/tasks/#{file_stem}.rake"
      ].each do |sample|
        expect(names_task.call(sample)).to be(true),
          "prescription detector failed to fire on: #{sample.inspect}"
      end

      [
        "bundle exec rails permissions:role_grant_drift",
        # A historical mention with no invocation verb is deliberately ALLOWED —
        # the changelog entry recording the removal needs to name what it removed.
        "4. Created `#{task_name}` and `roles:status` — both since removed."
      ].each do |sample|
        expect(names_task.call(sample)).to be(false),
          "prescription detector false-positived on: #{sample.inspect}"
      end
    end
  end

  describe "definition" do
    it "is defined by no rake file in the repo (core or extension)" do
      # Anti-vacuity 1: the glob must have found the real rake trees, core and
      # extension, and a task that IS present must be visible to this scanner.
      expect(rake_files.size).to be >= 20,
        "rake glob found #{rake_files.size} file(s) — the scan is not reading the repo"
      sentinel = File.join(repo_root, "server/lib/tasks/permissions.rake")
      expect(rake_files).to include(sentinel)
      expect(File.read(sentinel)).to include("task reconcile_role_grants:"),
        "sentinel server/lib/tasks/permissions.rake no longer contains the expected task — fix this guard"
      expect(rake_files.any? { |p| p.include?("/extensions/") }).to be(true),
        "no extension rake files in the scanned set — the definition scope regressed to core only"

      definers = rake_files.select { |path| defines_task.call(File.read(path)) }

      expect(definers).to be_empty,
        "#{task_name} was removed as a destructive, unreachable second config->DB path for role " \
        "grants; it is defined again in #{definers.map { |p| p.sub("#{repo_root}/", "") }.inspect}. " \
        "Role grants reconcile additively via Permissions::RoleGrantReconciler at boot — do not " \
        "reintroduce destructive reconciliation."

      expect(rake_files.map { |p| File.basename(p, ".rake") }).not_to include(file_stem)
    end
  end

  describe "references" do
    it "is prescribed by no doc, script, CI config, comment or code (server/spec excluded)" do
      # Anti-vacuity 1: floor on the scanned set, the trees that motivated the
      # wide scope must actually be in it, and sentinel files must be present
      # with strings they really contain.
      expect(reference_files.size).to be >= 2000,
        "reference glob found #{reference_files.size} file(s) — the scan is not reading the repo"

      %w[server/ docs/ scripts/ worker/ extensions/ .gitea/].each do |tree|
        prefix = File.join(repo_root, tree)
        expect(reference_files.any? { |p| p.start_with?(prefix) }).to be(true),
          "#{tree} is not in the scanned set — the reference scope regressed"
      end
      expect(reference_files.any? { |p| p.end_with?(".sh") }).to be(true),
        "no shell scripts in the scanned set — a rake invocation from a start script would be invisible"

      {
        "server/docs/ROLE_STANDARDIZATION.md" => "# Role Standardization Documentation",
        "server/app/services/permissions/role_grant_reconciler.rb" => "class RoleGrantReconciler"
      }.each do |rel, sentinel_text|
        abs = File.join(repo_root, rel)
        expect(reference_files).to include(abs), "#{rel} is not in the scanned set — fix this guard"
        expect(File.read(abs)).to include(sentinel_text),
          "sentinel text missing from #{rel} — fix this guard"
      end

      offenders = reference_files.select { |path| names_task.call(File.read(path)) }

      expect(offenders).to be_empty,
        "the #{task_name} rake task no longer exists; #{offenders.map { |p| p.sub("#{repo_root}/", "") }.inspect} " \
        "still prescribes it (or names its deleted file). A doc prescribing a deleted destructive command is the trigger label on a loaded gun — " \
        "point at Permissions::RoleGrantReconciler (absence-only, runs at boot) instead."
    end
  end
end

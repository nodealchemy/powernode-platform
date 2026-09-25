# frozen_string_literal: true

require "rails_helper"
require "open3"

# Derived guard (IMP-b95b8c5b6c40): the "devops.*" vs "ci_cd.*" naming drift
# (and its swarm.*/docker.*/worker.* siblings — see audit_actions.rb's
# DEVOPS_ACTIONS/SWARM_ACTIONS/DOCKER_ACTIONS/WORKER_ACTIONS comments) was
# only discovered because a reviewer happened to read server/log/test.log.
# AuditLog validates `action` against AuditActions.all_actions, and every
# writer rescues the resulting ActiveRecord::RecordInvalid and DROPS the row
# instead of surfacing it — log_audit_event (app/controllers/concerns/
# audit_logging.rb) only re-raises when Rails.env.test?, and
# log_internal_audit (app/controllers/api/v1/internal/internal_base_
# controller.rb) never does — so an unregistered action name is invisible in
# every environment except a manual log read. This spec turns that class of
# bug into a red spec instead: it statically collects every LITERAL action
# string passed to the app's own audit-writing call sites in the DevOps/CI-CD
# controller family and asserts each one is registered. This is the
# complementary direction to AuditActions.register_actions' own guard (added
# by IMP-85fb47438be6): that one polices the SHAPE of a name at registration
# time; this one polices every name actually WRITTEN, registered or not.
#
# SCOPE, stated precisely so a future reader does not assume more coverage
# than this spec provides:
#
#   - Scans app/controllers/api/v1/devops/**, app/controllers/api/v1/
#     internal/devops/**, and app/services/workers/ensure_system_worker.rb —
#     the exact cluster IMP-b95b8c5b6c40 investigated and fixed (the
#     DevOps/CI-CD, Docker Swarm, and Docker host controller families, plus
#     the one incidental same-shape defect found while enumerating them).
#
#     THIS IS DELIBERATELY NOT A CORE-WIDE SCAN. Running this spec's
#     extraction logic against the whole of core app/ (done once, by hand, as
#     part of this task's investigation — not committed as a spec) turned up
#     225 further unregistered-literal occurrences across 52 files spanning
#     unrelated domains: ai.a2a_tasks.*, ai.agent_cards.*, ai.federation.*,
#     ai.ralph_loops.*, chat.channels.*, chat.sessions.*, and — the ones that
#     matter most — account.delete_data_deletion_requests / user.delete /
#     data_deletion.approve/execute/reject in the GDPR/CCPA deletion and
#     account-anonymization path (app/controllers/api/v1/internal/
#     accounts_controller.rb, data_deletion_requests_controller.rb,
#     users_controller.rb). Per bulk-operation-safety ("never batch-approve
#     auto-discovered code changes — review individually") and this task's
#     own escalation criteria (irreversible/outward-facing action, tenancy/
#     permission-model territory), those are OUT OF SCOPE for this task and
#     were filed as a separate finding rather than fixed here — see this
#     commit's companion report. Widening this spec's Dir.glob to core-wide
#     before that cluster is triaged would leave the suite permanently red
#     for defects this task did not touch.
#
#   - The public extensions (extensions/{system,marketing,supply-chain}/
#     server/app/) are out of scope for the same reason core-wide is: they
#     are independently-owned worktrees that can be mid-edit while this spec
#     runs in this one.
#
#   - Recognizes the LITERAL-STRING-ARGUMENT call shapes that account for
#     every real writer in this cluster:
#       * log_audit_event("literal", ...)              (AuditLogging concern)
#       * log_internal_audit("literal", ...)            (Internal base controller)
#       * AuditLog.log_action(action: "literal", ...)   (direct model call)
#       * Audit::LoggingService.instance.log(action: "literal", ...) and its
#         log_authentication/log_admin_action/log_security_event/
#         log_data_access/log_compliance_event/log_system_event siblings
#     A DYNAMIC action (a variable, a method call, a case/when expression, or
#     a bespoke local wrapper) is not resolved statically; none of the files
#     in this cluster's scope use one.
#
#   - A literal ending in ".index" is excluded ONLY for the log_audit_event
#     shape: that helper returns before ever reaching AuditLog for a
#     ".index"-suffixed action (audit_logging.rb), so it is never actually
#     validated there. log_internal_audit is a bare AuditLog.create! with no
#     such skip (internal_base_controller.rb), and neither AuditLog.log_action
#     nor Audit::LoggingService.instance.log has one either — a ".index"
#     literal through any of those three WOULD fail validation for real, so
#     exempting it there would be a false negative, not a false positive.
#     (Review finding F2, IMP-b95b8c5b6c40 review 2026-09-18: vacuous today —
#     no ".index" literal exists in this cluster's scope — but latent.)
RSpec.describe "devops/swarm/docker/worker audit action literals are registered" do
  scan_roots = [
    Rails.root.join("app", "controllers", "api", "v1", "devops", "**", "*.rb"),
    Rails.root.join("app", "controllers", "api", "v1", "internal", "devops", "**", "*.rb"),
    Rails.root.join("app", "services", "workers", "ensure_system_worker.rb")
  ].freeze

  # Keyed by shape, so the ".index" exemption (F2) can be scoped to exactly
  # the one shape it is true for, instead of applying to all four uniformly.
  literal_arg_patterns = {
    log_audit_event: /\blog_audit_event\(\s*["']([\w.]+)["']/,
    log_internal_audit: /\blog_internal_audit\(\s*["']([\w.]+)["']/
  }.freeze

  # The `action:` keyword can be the first argument on its own line
  # (ensure_system_worker.rb) as well as inline with the call. `\s` already
  # matches newlines in Ruby regex without a modifier.
  keyword_arg_pattern =
    /\b(?:AuditLog\.log_action|Audit::LoggingService\.instance\.log(?:_\w+)?)\(\s*action:\s*["']([\w.]+)["']/

  trigger_substrings = %w[
    log_audit_event log_internal_audit AuditLog.log_action
    Audit::LoggingService.instance.log
  ].freeze

  it "does not write an action string that AuditActions.valid_action? rejects" do
    offenders = {}
    total_literal_occurrences = 0

    scan_roots.flat_map { |glob| Dir.glob(glob) }.uniq.sort.each do |path|
      content = File.read(path)
      next unless trigger_substrings.any? { |needle| content.include?(needle) }

      tagged_literals = []
      literal_arg_patterns.each do |shape, pattern|
        content.scan(pattern) { |m| tagged_literals << [ m.first, shape ] }
      end
      content.scan(keyword_arg_pattern) { |m| tagged_literals << [ m.first, :keyword_arg ] }

      total_literal_occurrences += tagged_literals.size

      tagged_literals.uniq.each do |literal, shape|
        next if shape == :log_audit_event && literal.end_with?(".index")
        next if AuditActions.valid_action?(literal)

        (offenders[path.to_s.sub("#{Rails.root}/", "")] ||= []) << literal
      end
    end

    expect(offenders).to be_empty,
      "Unregistered audit action literal(s) found — AuditLog's inclusion " \
      "validation rejects these and the writer (log_audit_event / " \
      "log_internal_audit / etc.) rescues and silently drops the row:\n" +
      offenders.map { |file, actions| "  #{file}: #{actions.sort.join(', ')}" }.join("\n")

    # F1 (review finding, IMP-b95b8c5b6c40 review 2026-09-18): `offenders` is
    # empty both when every literal is registered AND when the extraction
    # matched nothing at all — a literal rewritten to reference a constant,
    # or called without parens, silently leaves the scanned set and this
    # spec would stay green while coverage quietly shrank. This floor is the
    # positive counterpart. The raw literal-occurrence count across this exact
    # glob was 113 on 2026-09-18; re-measured 85 on 2026-09-25 after cb684138e
    # deleted 4 devops_* controllers (28 literals). The floor sits a little
    # under it (not equal, which would be brittle against a legitimate future
    # addition or deletion) so that losing a whole file's worth of coverage
    # still trips it: dropping container_templates_controller.rb (9) or
    # pipelines_controller.rb (8) from the scan takes it below 80
    # (mutation-verified, not just asserted).
    expect(total_literal_occurrences).to be >= 80
  end

  it "actually covers every devops/swarm/docker/worker writer file found by an unscoped repo grep (guards the glob itself)" do
    grep_files, status = Open3.capture2(
      "git", "-C", Rails.root.to_s, "grep", "-l",
      "-e", "log_audit_event(", "-e", "log_internal_audit(",
      "--", "app/controllers/api/v1/devops", "app/controllers/api/v1/internal/devops",
      "app/services/workers/ensure_system_worker.rb"
    )
    raise "git grep failed: #{grep_files}" unless status.success? || status.exitstatus == 1

    expected = grep_files.lines.map(&:chomp).map { |f| Rails.root.join(f).to_s }.sort
    actual = scan_roots.flat_map { |glob| Dir.glob(glob) }.uniq.sort

    expect(actual).to include(*expected)
  end
end

# Prune stale Devops::GitRunner rows — records for ephemeral CI builders that
# no longer exist upstream.
#
# WHY. The runner scope sync is upsert-only (RunnerLifecycleService:150-165 ->
# GitRunner.sync_from_provider): it never deletes a row whose upstream runner
# has disappeared. Fleet builders register as EPHEMERAL, so Gitea drops each
# one after a single job, but any sync that caught it mid-life left a permanent
# local row. Hence a platform view full of "offline" runners that do not exist.
# Root fix tracked as IMP 019fd9fe; this only clears the existing backlog.
#
# SAFETY. Two independent guards:
#   1. Only rows whose name starts with "fleet-" are considered, so the
#      permanent shared runners (runner1/runner2/runner3) can never match.
#   2. Any runner named by a NON-TERMINAL CiRunnerLease is excluded, so a
#      builder serving a job right now is never removed regardless of the
#      status its last sync recorded.
# Dry run by default. Set APPLY=1 to delete.
#
#   rails runner /path/to/prune-stale-git-runners.rb          # dry run
#   APPLY=1 rails runner /path/to/prune-stale-git-runners.rb  # delete

apply = ENV["APPLY"] == "1"

live = System::CiRunnerLease
       .where.not(status: %w[released errored])
       .pluck(:runner_name).compact.uniq

scope = Devops::GitRunner.where("name LIKE ?", "fleet-%")
scope = scope.where.not(name: live) if live.any?

total  = Devops::GitRunner.count
fleet  = Devops::GitRunner.where("name LIKE ?", "fleet-%").count
doomed = scope.order(:last_seen_at).to_a

puts "GitRunner rows total: #{total} (fleet-*: #{fleet})"
puts "protected — live leases: #{live.inspect}" if live.any?
puts "DELETE CANDIDATES: #{doomed.size}"
doomed.first(3).each { |r| puts "  #{r.name}  status=#{r.status}  last_seen=#{r.last_seen_at}" }
puts "  ... #{doomed.size - 4} more ..." if doomed.size > 4
doomed.last(1).each { |r| puts "  #{r.name}  status=#{r.status}  last_seen=#{r.last_seen_at}" } if doomed.size > 3

if !apply
  puts "\nDRY RUN — re-run with APPLY=1 to delete these #{doomed.size} row(s)."
else
  # ai_runner_dispatches FKs to git_runners with NO on_delete, and
  # Ai::RunnerDispatchService stamps git_runner permanently — so delete_all on a
  # runner that ever ran a job raises ActiveRecord::InvalidForeignKey and
  # deletes NOTHING. Null the pointer first. git_runner_id is `optional: true`
  # and the dispatch row is history worth keeping; the runner it referenced no
  # longer exists anywhere to point at.
  ids = doomed.map(&:id)
  freed = Ai::RunnerDispatch.where(git_runner_id: ids).update_all(git_runner_id: nil)
  puts "cleared git_runner_id on #{freed} dispatch row(s)" if freed.positive?
  n = Devops::GitRunner.where(id: ids).delete_all
  puts "\ndeleted #{n} row(s); #{Devops::GitRunner.count} remain"
end

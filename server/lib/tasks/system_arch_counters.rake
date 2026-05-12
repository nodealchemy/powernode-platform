# frozen_string_literal: true

# Reconcile System::NodeArchitecture counter columns when drift is suspected.
#
# The three counters on each NodeArchitecture row track real-world usage
# across the platform:
#
#   - node_platform_count        # NodePlatforms FK'd to this arch
#   - package_repository_count   # PackageRepositories whose JSONB
#                                #   `architectures` array contains a
#                                #   name matching this arch (apt or rpm)
#   - package_count              # Live Package rows whose `architecture`
#                                #   string matches this arch (apt or rpm)
#
# Counter maintenance is hybrid:
#
#   - node_platform_count is a Rails counter_cache and stays accurate for
#     ordinary AR writes; bare SQL UPDATEs bypass it.
#   - package_repository_count is maintained by after_commit hooks on
#     PackageRepository (the JSONB column can't drive counter_cache).
#   - package_count is recomputed at the end of every PackageRepositorySync
#     run (Package rows land via upsert_all, which bypasses callbacks).
#
# Run this task after bare-SQL operations on system_node_platforms,
# manual edits to system_package_repositories.architectures, or anytime
# the Usage column in the catalog UI looks stale.
namespace :system do
  namespace :arch_counters do
    desc "Recompute all NodeArchitecture counter columns from authoritative source data."
    task reconcile: :environment do
      puts "Reconciling NodeArchitecture counters..."
      # Order both queries by name so before/after pairings line up — pluck
      # without ORDER BY returns rows in unspecified order, and recompute_all_
      # counters! writes can shuffle the heap.
      before = ::System::NodeArchitecture.order(:name)
                 .pluck(:name, :node_platform_count, :package_repository_count, :package_count)

      ::System::NodeArchitecture.recompute_all_counters!

      after = ::System::NodeArchitecture.order(:name)
                .pluck(:name, :node_platform_count, :package_repository_count, :package_count)

      header = ["name", "platforms (was→now)", "repos (was→now)", "packages (was→now)"]
      puts "  #{header.join('  |  ')}"
      before.zip(after).each do |(name_b, np_b, pr_b, pk_b), (_, np_a, pr_a, pk_a)|
        puts "  #{name_b.ljust(10)}  |  #{np_b}→#{np_a}  |  #{pr_b}→#{pr_a}  |  #{pk_b}→#{pk_a}"
      end
      puts "Done."
    end

    desc "Recompute only package_count (called automatically after each sync)."
    task packages: :environment do
      ::System::NodeArchitecture.recompute_package_counts!
      ::System::NodeArchitecture.order(:name).each do |a|
        puts "  #{a.name}: package_count=#{a.package_count}"
      end
    end
  end
end

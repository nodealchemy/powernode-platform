# frozen_string_literal: true

# Component status plane, A6 review G2-3: rewrite investigations that recorded a
# ranking failure in the old `evidence.errors.ranking` shape into the
# `evidence.ranking` record the A6 state-3 batch writes. There is no reader for
# the old shape, so the data is migrated.
#
# The work lives in `Platform::Investigation::LegacyRankingErrorRewrite`, which
# acts on 5 rows or fewer and changes nothing above that. Above the limit an
# operator runs `bin/rails platform:rewrite_legacy_ranking_errors
# CONFIRM=<count>`. This migration must never raise, because live nodes apply
# pending migrations at boot and a raise would abort the deploy. So even a
# constant that fails to load is caught here, and nothing changes.
#
# FROZEN once committed: a lane that already applied it would silently skip any
# edit. A change needs a new migration with a fresh version.
class RewriteLegacyInvestigationRankingErrors < ActiveRecord::Migration[8.0]
  def up
    say ::Platform::Investigation::LegacyRankingErrorRewrite.auto_rewrite.message
  rescue StandardError => e
    say "[G2-3] ranking-error rewrite did not run (#{e.class}: #{e.message}); nothing changed. " \
        "Retry with `bin/rails platform:rewrite_legacy_ranking_errors`."
  end

  # A data rewrite with no inverse worth running: the old shape is the one the
  # platform no longer reads.
  def down; end
end

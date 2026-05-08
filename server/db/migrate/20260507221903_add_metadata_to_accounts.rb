# frozen_string_literal: true

# Add a JSONB `metadata` column to accounts. Stores semi-structured
# per-account state that doesn't deserve a dedicated column —
# specifically the M2 self-serve onboarding completion timestamp
# (`metadata["onboarding_completed_at"]`) so the FirstRunWizard can
# decide whether to redirect new accounts into the BYOC flow.
#
# `settings` is the operator-tunable preferences bag (theme,
# notifications, etc.); `metadata` is the platform-managed
# bookkeeping bag — keeping the two separate prevents accidental
# settings UIs from clobbering onboarding state.
#
# Reference: docs/m1_selfserve_acceptance.md (M2 Self-Serve Hardening
# — BYOC).
class AddMetadataToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :metadata, :jsonb, default: {}, null: false
  end
end

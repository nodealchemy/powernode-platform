# frozen_string_literal: true

# IMP-6cda93db7f31 (offer 01a06997) — a GLOBAL canonical agent (account_id
# NULL: a seeded, source_key-managed platform template, proposal §5 ruling 5)
# must never depend on an account or an admin user existing. Until now
# ai_agents.creator_id and ai_agents.ai_provider_id were NOT NULL, and both a
# User and an Ai::Provider belong to an Account, so a canonical could not be
# written on a database with no account at all — every core agent seed bailed
# out instead, and a development database seeded without SEED_ADMIN_USERS held
# no canonical (the empty set that made `rake claude:sync_agents` delete the
# committed skeletons on 2026-09-03).
#
# Both columns become nullable, and a CHECK keeps the rule exact: ONLY a global
# row may lack them. An account-scoped row — every executing principal
# (ruling 8: a canonical is a template; what runs is the account's clone,
# minted by Ai::Agents::AccountPrincipalResolver with THAT account's creator
# and provider) — still carries both. The model mirrors the CHECK
# (`validates :creator, :provider, presence: ..., if: :account_scoped_row?` —
# `account_id.present? || account.present?`, so an unsaved row built with an
# unsaved account fails validation rather than the CHECK).
#
# `down` restores NOT NULL and so fails while a global row without a creator
# or provider exists; that is correct — those rows are the point of `up`, and
# rolling back past it means re-seeding them under an admin user first.
class AllowGlobalCanonicalAgentsWithoutCreatorOrProvider < ActiveRecord::Migration[8.1]
  CHECK_NAME = "chk_ai_agents_account_rows_need_creator_and_provider"
  CHECK_EXPRESSION = "account_id IS NULL OR (creator_id IS NOT NULL AND ai_provider_id IS NOT NULL)"

  def up
    change_column_null :ai_agents, :creator_id, true
    change_column_null :ai_agents, :ai_provider_id, true
    add_check_constraint :ai_agents, CHECK_EXPRESSION, name: CHECK_NAME
  end

  def down
    remove_check_constraint :ai_agents, name: CHECK_NAME
    change_column_null :ai_agents, :ai_provider_id, false
    change_column_null :ai_agents, :creator_id, false
  end
end

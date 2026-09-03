# frozen_string_literal: true

require 'rails_helper'

# IMP-a653cfbe3037 — Accounts::DelegationService#list_available_roles_for_delegation
# was dead AND broken: it filtered `Role.where(system_role: true)`, and the roles
# table has no `system_role` column (it has `is_system` and `role_type`), so the
# relation would raise ActiveRecord::StatementInvalid the first time anything
# forced it. Nothing ever did — a full-tree `command grep` over server/, worker/,
# frontend/ and every extension (public and private) found exactly one hit, the
# definition itself (plus a sibling git worktree's copy of the same file, which
# is not a call site), and no composed/symbol dispatch that could reach it.
#
# The operator decision was DELETE, not repair: `is_system` and `role_type` are
# not interchangeable, and "available FOR DELEGATION" under the conferral rule
# this same service enforces would mean roles the delegator may confer
# (Role#assignable_by?), not a system flag. The filter was a stale idea, not a
# typo, so repairing it would have meant designing an uncalled method.
#
# ORACLE CHOICE. These assertions are on ABSENCE, which cannot be observed by
# calling the method — a call-based example would go from "raises
# StatementInvalid" to "raises NoMethodError" and stay green through both the
# broken state and the deleted one. So example 1 asks the class what it defines
# (including private methods, so a demotion rather than a deletion still fails),
# and example 2 pins the schema fact the trap depended on and guards the service
# source against the same column name being reintroduced by a future "fix".
#
# Example 2's source guard matches the COLUMN-USAGE shape (`where(system_role:`,
# `where.not(system_role:`), not the bare name: `Role#system_role?` is a live and
# legitimate predicate — it backs `Role#assignable_by?`, which this service
# already calls — so forbidding the substring would fail on correct code.
RSpec.describe Accounts::DelegationService, type: :service do
  describe 'the removed role-listing surface' do
    it 'defines no list_available_roles_for_delegation method' do
      defined_here = described_class.instance_methods(false) +
                     described_class.private_instance_methods(false)

      expect(defined_here).not_to include(:list_available_roles_for_delegation)
    end

    it 'queries no `system_role` column, which the roles table does not have' do
      expect(Role.column_names).not_to include('system_role')

      source = Rails.root.join('app/services/accounts/delegation_service.rb').read

      expect(source).not_to match(/where(?:\.not)?\([^)]*system_role:/)
    end
  end
end

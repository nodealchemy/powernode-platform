# frozen_string_literal: true

require 'rails_helper'

# `create(:user, permissions: [...])` reaches User#assign_permissions_after_create,
# which mints an ad-hoc `test_role_*` row to carry the listed grants.
#
# That role used to be created with NO account_id — i.e. in the GLOBAL scope
# (account_id NULL), the same scope Role.sync_from_config! seeds the real
# catalog into and the scope every "no global role holds X" catalog assertion
# selects on. A sweep reached it two ways: within the SAME example, when the
# enclosing describe builds a `permissions: [...]` actor in a `let!`/`before`
# (no commit needed — the rollback comes after the sweep has already read the
# row); and, latently, through any non-transactional example (`truncation: true`
# in spec/rails_helper.rb, or `type: :performance` / `:integration` in
# spec/support/ai_test_configuration.rb — none exist today), which commits the
# row to the test DB shared across concurrently running agents. The resulting
# failure reads "global <role> unexpectedly holds <verb>" — indistinguishable
# from the real catalog re-widening those sweeps exist to catch, which trains
# the reader to discount the one assertion that must never be discounted.
#
# The harness role now belongs to the user's OWN account. These examples fail if
# it ever lands back in the global scope.
#
# SCOPE OF THAT CLAIM: it covers the `permissions:` transient only.
# `create(:role)` still mints a GLOBAL `test_role_*` row (spec/factories/roles.rb
# sets no account) and its `:with_permissions` trait grants real catalog verbs on
# it, so a `test_role_*` red is not automatically harness noise. Fix such a red
# by scoping the role at its CREATION site — never by excluding the prefix in
# the sweep.
RSpec.describe 'user factory permissions: transient role scope', type: :model do
  let(:account) { create(:account) }

  def harness_roles_for(user)
    user.roles.where("roles.name LIKE ?", "test_role_%")
  end

  it 'mints the ad-hoc role inside the user account, never in the global scope' do
    user = create(:user, account: account, permissions: [ 'users.read' ])

    minted = harness_roles_for(user)
    expect(minted).to be_present
    expect(minted.map(&:account_id)).to all(eq(account.id))
  end

  it 'adds no row to the global role scope' do
    # Force the account BEFORE the baseline. `account` is lazy, and Account
    # fires after_create_commit :run_account_bootstrap; taking the baseline
    # first would fold account creation into the delta this example attributes
    # to the user factory.
    account

    before_ids = Role.global.pluck(:id).sort

    create(:user, account: account, permissions: [ 'users.read' ])
    create(:user, account: account, permissions: [])

    expect(Role.global.pluck(:id).sort - before_ids).to eq([])
  end

  # The shape every catalog sweep asserts: "no global role holds <verb>".
  it 'does not put the requested permission on any global role' do
    holders = lambda do
      Role.global.joins(:role_permissions)
          .where(role_permissions: { permission_name: 'users.read' })
          .pluck(:id).sort
    end

    account # force before the baseline, as above

    before_holders = holders.call
    create(:user, account: account, permissions: [ 'users.read' ])

    expect(holders.call).to eq(before_holders)
  end

  it 'still grants exactly the requested permissions to the user' do
    user = create(:user, account: account, permissions: [ 'users.read' ])

    expect(user.has_permission?('users.read')).to be true
    expect(user.has_permission?('users.manage')).to be false
  end

  it 'keeps permissions: [] genuinely permissionless' do
    user = create(:user, account: account, permissions: [])

    expect(user.permission_names).to eq([])
  end
end

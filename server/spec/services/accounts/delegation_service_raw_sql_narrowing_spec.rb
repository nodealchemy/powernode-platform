# frozen_string_literal: true

require 'rails_helper'

# IMP-95e4904258c8 — the privilege-escalation guard for conferring a whole ROLE
# (Role#assignable_by?, server/app/models/role.rb:148-155) resolves the
# DELEGATOR's side through User#permission_names, which is Rails.cache-backed.
#
# The key it used was
#   "user:<id>:permission_names:<user.updated_at>:<sorted role ids>"
# — none of whose components can observe a change to a role's GRANTS. So a
# narrowing that removes a permission from a role left the delegator's cached
# (WIDER) set resident, and the subset check in #assignable_by? then wrongly
# PASSED. It fails OPEN, and the conferral is durable: the account_delegations
# row outlives the 5-minute cache window.
#
# WHY RAW SQL IS THE ONLY HONEST NARROWING HERE. The narrowings that matter land
# as raw-SQL remap migrations (e.g. the business extension's
# 20260830000001_remap_business_operator_permissions, whose DELETE FROM
# role_permissions is issued through #execute). Those bust no ActiveRecord
# callback, so an example that revokes through ActiveRecord would pass against a
# callback-based fix and prove nothing about the path that actually ships.
#
# AND THE CACHE MUST BE WARM. The stale read IS the defect; an example that
# starts from a cold cache passes against the broken code. Nothing here clears
# Rails.cache, and each example takes a REAL read of the delegator's permission
# set before narrowing.
RSpec.describe 'role conferral against a raw-SQL permission narrowing', type: :service do
  let(:account) { create(:account) }
  let(:external_account) { create(:account) }
  let(:delegated_user) { create(:user, account: external_account) }

  # A real catalog permission the delegator holds and the conferred role needs.
  let(:held_permission) { 'report.generate' }

  # A REAL seeded role, not a `permissions: [...]` synthetic actor: the conferral
  # rule reads the delegator's whole permission set.
  let(:delegator) do
    user = create(:user, :manager, account: account)
    role = user.roles.first
    role.role_permissions.find_or_create_by!(permission_name: 'accounts.manage')
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    user.reload
    user
  end

  let(:delegator_role) { delegator.roles.first }

  # Every permission on this role is one the delegator holds *before* the
  # narrowing => conferrable then, and NOT conferrable after.
  let(:target_role) do
    role = create(:role, name: 'conferral.narrowed', display_name: 'Conferral Narrowed', role_type: 'user')
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role
  end

  let(:service) { Accounts::DelegationService.new(delegator, account) }

  # The migration path: raw SQL straight at the table, no AR object, no callback.
  def narrow_by_raw_sql!
    sql = ActiveRecord::Base.sanitize_sql_array(
      [ 'DELETE FROM role_permissions WHERE role_id = ? AND permission_name = ?',
        delegator_role.id, held_permission ]
    )
    ActiveRecord::Base.connection.execute(sql)
  end

  # POSITIVE CONTROLS. Without these every refusal below could pass for the wrong
  # reason — an actor with no permissions at all refuses everything, and a
  # system.admin actor short-circuits the subset check entirely (admin.access no
  # longer does: IMP-1635cb7fa768 removed that exemption, and the assertions
  # below keep pinning both).
  describe 'premises' do
    it 'the delegator really holds the permission and is not admin-tier' do
      expect(delegator.has_permission?(held_permission)).to be(true),
        'the manager role is not carrying report.generate; the refusal example would pass vacuously'
      expect(delegator.has_permission?('system.admin')).to be false
      expect(delegator.has_permission?('admin.access')).to be false
      expect(Role.assignment_admin?(delegator)).to be false
    end

    it 'the target role is conferrable BEFORE the narrowing' do
      expect(target_role.assignable_by?(delegator)).to be true
    end

    it 'the raw SQL really removes the row' do
      expect(delegator_role.role_permissions.pluck(:permission_name)).to include(held_permission)
      narrow_by_raw_sql!
      expect(delegator_role.role_permissions.reload.pluck(:permission_name)).not_to include(held_permission)
    end
  end

  # THE INVARIANT. The refusal below is one consequence of it; this is the thing
  # itself. A key that cannot observe a grant change can only ever fail open.
  it 'changes the permission cache key when a role permission is revoked by raw SQL' do
    before_key = delegator.permission_names_cache_key
    narrow_by_raw_sql!

    expect(delegator.permission_names_cache_key).not_to eq(before_key),
      'the permission cache key is blind to role-grant changes: a stale, WIDER ' \
      'permission set stays addressable for the whole 5-minute window'
  end

  # THE ESCALATION. Asserting the ROW, not just the return value: a guard that
  # renders/returns a refusal does not necessarily halt the write.
  it 'refuses the conferral after the narrowing and writes NO delegation row' do
    # 1. A real read, so the WIDER set is genuinely resident in Rails.cache.
    expect(delegator.permission_names).to include(held_permission)

    # 2. The narrowing, exactly as a remap migration issues it.
    narrow_by_raw_sql!

    # 3. The conferral must now be refused...
    result = service.create_delegation(
      delegated_user_email: delegated_user.email,
      role_id: target_role.id
    )

    expect(result[:success]).to be(false),
      "conferral of a role carrying #{held_permission} succeeded after that permission " \
      'was revoked from the delegator by raw SQL — the stale permission cache made the ' \
      'subset check in Role#assignable_by? pass'

    # 4. ...and must have left nothing behind.
    expect(
      Account::Delegation.where(account: account, delegated_user: delegated_user).exists?
    ).to be(false), 'the conferral was refused but a delegation row was written anyway'
  end

  # The direct guard, independent of the service wrapper.
  it 'Role#assignable_by? refuses the role after the narrowing' do
    expect(delegator.permission_names).to include(held_permission)
    narrow_by_raw_sql!

    expect(target_role.assignable_by?(delegator)).to be(false)
  end

  # REVIEWER QUESTION (a): can the counter be read stale inside ONE request?
  # ActiveRecord's per-request query cache would do exactly that — it is dirtied
  # only by writes on the SAME connection, so a narrowing committed by another
  # process (which is what a remap migration is) does not evict it. The version
  # read is therefore taken outside it.
  it 'reads the grant version outside the ActiveRecord query cache' do
    selects = 0
    cache_hits = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next unless payload[:sql].to_s.include?('permissions_version')

      payload[:cached] ? cache_hits += 1 : selects += 1
    end

    begin
      ActiveRecord::Base.cache do
        delegator.role_cache_key
        delegator.role_cache_key
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(cache_hits).to eq(0), 'the grant version was served from the query cache'
    expect(selects).to eq(2), 'the grant version was read once and reused for the rest of the request'
  end

  # THE SAME QUESTION ONE LAYER DOWN. A fresh key is only half the job: on a
  # miss the fetch block RE-READS the grants, and the query cache would answer
  # those reads from the pre-narrowing snapshot taken earlier in the same
  # request — writing the WIDE set to the shared store under the CORRECT
  # post-narrowing key. That is the original defect with a larger blast radius,
  # so the block's reads are asserted uncached too, not just the key's.
  #
  # The Rails.cache entry is deleted between the two calls to force a second
  # block execution; in production a changed key does that instead. The AR query
  # cache is deliberately left standing — it is the thing under test.
  it 'resolves the permission SET outside the ActiveRecord query cache as well' do
    cache_hits = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next unless payload[:sql].to_s.include?('role_permissions')

      cache_hits += 1 if payload[:cached]
    end

    begin
      ActiveRecord::Base.cache do
        delegator.permission_names
        Rails.cache.delete(delegator.permission_names_cache_key)
        delegator.permission_names
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(cache_hits).to eq(0),
      'the permission set was re-read from the ActiveRecord query cache, so a narrowing \
       committed by another process would be re-cached under the new key'
  end

  # REVIEWER FINDING: the trigger SQL exists twice — canonically in the
  # migration, and again in the schema-dump initializer because Rails' :ruby
  # schema format cannot dump functions or triggers. Nothing else fails if one
  # copy drifts, and the failure mode of a drifted copy is a database built by
  # db:schema:load whose counter never moves.
  it 'keeps the migration and the schema-dump initializer SQL identical' do
    migration = Rails.root.join('db/migrate/20260901000000_add_permissions_version_to_roles.rb').read
    initializer = Rails.root.join('config/initializers/role_permissions_version_schema_dump.rb').read

    pattern = /(CREATE OR REPLACE FUNCTION.*?\$\$ LANGUAGE plpgsql;|CREATE TRIGGER.*?;|DROP TRIGGER IF EXISTS[^"\']*?;|ALTER TABLE[^"\']*?TRIGGER [a-z_]+;)/m
    normalise = lambda do |source|
      source.scan(pattern).flatten
            .map { |sql| sql.gsub(/--[^\n]*/, '').gsub(/\s+/, ' ').strip.downcase }
            .uniq.sort
    end

    from_migration = normalise.call(migration)
    from_initializer = normalise.call(initializer)

    expect(from_migration).not_to be_empty, 'the SQL extractor matched nothing; it has drifted from the files'
    expect(from_initializer).to eq(from_migration),
      'the schema-dump initializer SQL no longer matches the migration; a database built by \
       db:schema:load would get a different (or no) trigger'
  end

  # THE BUSTER ITSELF. The key above can only change if roles.permissions_version
  # moves, and it only moves if the trigger fires — on EVERY write shape, not
  # just the DELETE the example above happens to use.
  describe 'the roles.permissions_version trigger' do
    let(:role) { create(:role, name: 'trigger.probe', display_name: 'Trigger Probe', role_type: 'user') }

    def version_of(role_record)
      Role.where(id: role_record.id).pick(:permissions_version)
    end

    def raw(sql, *binds)
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([ sql, *binds ]))
    end

    it 'bumps on INSERT' do
      before_version = version_of(role)
      raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      expect(version_of(role)).to be > before_version
    end

    it 'bumps on UPDATE' do
      raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      before_version = version_of(role)
      raw('UPDATE role_permissions SET permission_name = ? WHERE role_id = ? AND permission_name = ?',
          'report.generate', role.id, 'report.export')
      expect(version_of(role)).to be > before_version
    end

    it 'bumps BOTH roles when an UPDATE re-parents a grant' do
      other = create(:role, name: 'trigger.probe.other', display_name: 'Other', role_type: 'user')
      raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      before_source = version_of(role)
      before_target = version_of(other)

      raw('UPDATE role_permissions SET role_id = ? WHERE role_id = ? AND permission_name = ?',
          other.id, role.id, 'report.export')

      expect(version_of(role)).to be > before_source
      expect(version_of(other)).to be > before_target
    end

    it 'bumps on DELETE' do
      raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      before_version = version_of(role)
      raw('DELETE FROM role_permissions WHERE role_id = ? AND permission_name = ?', role.id, 'report.export')
      expect(version_of(role)).to be > before_version
    end

    # A row trigger does not fire for TRUNCATE at all; without the separate
    # statement-level trigger, wiping the table would leave every cached set
    # addressable and WIDER than reality.
    it 'bumps on TRUNCATE' do
      raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      before_version = version_of(role)
      raw('TRUNCATE TABLE role_permissions')
      expect(version_of(role)).to be > before_version
    end

    # A logical-replication apply worker runs with session_replication_role =
    # 'replica', in which ORIGIN triggers do not fire. ENABLE ALWAYS is what
    # keeps the counter honest there.
    #
    # THE ENABLE ALWAYS IS RE-APPLIED HERE RATHER THAN ASSUMED, and that is a
    # finding, not test hygiene: DatabaseCleaner wraps its deletion in
    # ActiveRecord's #disable_referential_integrity, whose closing
    # `ALTER TABLE role_permissions ENABLE TRIGGER ALL` resets EVERY trigger on
    # the table from ALWAYS back to ORIGIN — permanently, not for the block. So
    # this database's triggers are ORIGIN by the time any example runs. See the
    # migration header for why that bypass cannot be closed from inside
    # Postgres, and note it has no application-code caller.
    it 'bumps with session_replication_role = replica when set ENABLE ALWAYS' do
      raw('ALTER TABLE role_permissions ENABLE ALWAYS TRIGGER role_permissions_version_bump')
      before_version = version_of(role)
      begin
        raw("SET session_replication_role = 'replica'")
        raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      ensure
        raw("SET session_replication_role = 'origin'")
      end
      expect(version_of(role)).to be > before_version
    end

    # The negative control for the example above: without ALWAYS the same write
    # in the same mode does NOT bump, so that example is testing the trigger's
    # configuration and not merely the fact that INSERTs bump.
    it 'does NOT bump in replica mode when the trigger is only ENABLE ORIGIN' do
      raw('ALTER TABLE role_permissions ENABLE TRIGGER role_permissions_version_bump')
      before_version = version_of(role)
      begin
        raw("SET session_replication_role = 'replica'")
        raw('INSERT INTO role_permissions (role_id, permission_name) VALUES (?, ?)', role.id, 'report.export')
      ensure
        raw("SET session_replication_role = 'origin'")
      end
      expect(version_of(role)).to eq(before_version)
    end
  end
end

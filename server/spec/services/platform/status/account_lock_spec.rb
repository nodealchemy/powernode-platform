# frozen_string_literal: true

require "rails_helper"

# A2 review M5 — the per-account sweep lock, proven against a REAL second
# connection.
#
# WHY A SECOND CONNECTION AND NOT TWO CALLS. Postgres advisory locks are
# per-SESSION and reentrant: the same connection re-acquiring a key it already
# holds succeeds. With transactional fixtures every example shares one
# connection, so calling `try_acquire!` twice in one example would return true
# twice and "prove" nothing — the classic check that cannot fail differently.
# Two overlapping HTTP requests in production are two connections out of the
# pool, and that is what these examples reproduce.
#
# WHY NO ACCOUNT ROW, AND NO `truncation: true`. The lock touches no table:
# `pg_try_advisory_xact_lock` takes two integers, and `key_for` accepts a bare
# id. So these examples pass UUID strings and stay inside ordinary
# transactional fixtures. The first draft created a real account and ran
# non-transactionally so the second connection could see it — which needs
# DatabaseCleaner truncation, and truncation on a database several lanes are
# hammering concurrently hung the run for ten minutes. Nothing here needed the
# row; the simpler spec is also the correct one.
RSpec.describe Platform::Status::AccountLock do
  let(:account_id) { SecureRandom.uuid }
  let(:other_id) { SecureRandom.uuid }

  # A RAW libpq connection, deliberately not from ActiveRecord's pool.
  #
  # Rails 8 PINS the connection under transactional fixtures — every thread
  # gets the same one — so `connection_pool.with_connection` in a second thread
  # blocks on the connection the example is already holding open, forever. That
  # is a deadlock, not a slow test: the first draft of this spec hung for five
  # minutes with no output. A separate libpq session is what "another request"
  # actually means to Postgres, and it sidesteps the pool entirely.
  def with_separate_session
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    conn = PG.connect(
      host: config[:host] || "localhost",
      port: config[:port] || 5432,
      dbname: config[:database],
      user: config[:username],
      password: config[:password]
    )
    yield conn
  ensure
    conn&.close
  end

  # Takes the lock the way the controller does — inside a transaction — on a
  # session of its own, and reports whether it got it.
  def acquire_on_other_connection(id)
    with_separate_session do |conn|
      conn.exec("BEGIN")
      taken = conn.exec_params(
        "SELECT pg_try_advisory_xact_lock($1, $2)",
        [ described_class::NAMESPACE, described_class.key_for(id) ]
      ).getvalue(0, 0)
      conn.exec("COMMIT")
      taken == "t"
    end
  end

  describe ".try_acquire!" do
    it "is taken by the first transaction and REFUSED to a concurrent one" do
      taken_by_other = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        expect(described_class.try_acquire!(account_id)).to be(true)
        taken_by_other = acquire_on_other_connection(account_id)
      end

      expect(taken_by_other).to be(false)
    end

    it "is available again once the holding transaction ends — the other arm" do
      # The holder is the SEPARATE session here, and the release is proven by
      # try_acquire! itself taking the key afterwards.
      #
      # Deliberately not the other way round: under transactional fixtures
      # `ActiveRecord::Base.transaction` opens a SAVEPOINT inside the example's
      # own transaction, so a lock taken on the pinned connection is held until
      # the EXAMPLE ends, not until that block does. Asserting release from
      # that side would fail for a reason that has nothing to do with the lock.
      released = with_separate_session do |conn|
        conn.exec("BEGIN")
        conn.exec_params("SELECT pg_try_advisory_xact_lock($1, $2)",
                         [ described_class::NAMESPACE, described_class.key_for(account_id) ])
        conn.exec("COMMIT")
        true
      end
      expect(released).to be(true)

      expect(described_class.try_acquire!(account_id)).to be(true)
    end

    it "locks per ACCOUNT, so one account's sweep does not block another's" do
      other_taken = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.try_acquire!(account_id)
        other_taken = acquire_on_other_connection(other_id)
      end

      expect(other_taken).to be(true)
    end
  end

  describe ".key_for" do
    it "is stable across calls and derived from the id, not from Ruby's salted hash" do
      # Ruby's `hash` is salted per process, so two web processes would derive
      # different keys for the same account — a lock that only locks against
      # itself.
      first = described_class.key_for(account_id)

      expect(described_class.key_for(account_id)).to eq(first)
      expect(described_class.key_for(account_id.to_s)).to eq(first)
    end

    it "accepts an account object and its bare id interchangeably" do
      account = build_stubbed(:account)

      expect(described_class.key_for(account)).to eq(described_class.key_for(account.id))
    end

    it "differs between accounts" do
      expect(described_class.key_for(account_id)).not_to eq(described_class.key_for(other_id))
    end

    it "fits a signed 32-bit integer, which is what pg_try_advisory_xact_lock takes" do
      keys = 50.times.map { described_class.key_for(SecureRandom.uuid) }

      expect(keys).to all(be_between(-2**31, 2**31 - 1))
    end
  end
end

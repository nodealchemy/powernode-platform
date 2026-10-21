# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformPurgeTask do
  def due_task(subject_id: SecureRandom.uuid)
    task = described_class.enqueue!(kind: "secret_store_account", subject_id: subject_id, error: StandardError.new("x"))
    task.update_columns(next_attempt_at: 1.minute.ago)
    task
  end

  it "never purges the secrets of an account that still exists, and marks the task dead" do
    account = create(:account)
    task = due_task(subject_id: account.id)
    expect(Security::SecretStore).not_to receive(:purge_account)

    described_class.run_due!

    expect(task.reload).to have_attributes(status: "dead", last_error_class: "AccountStillExists")
  end

  it "goes dead without purging when the cap was already exceeded (a crash before the outcome was recorded)" do
    task = due_task
    task.update_columns(attempts: described_class::MAX_ATTEMPTS)
    expect(Security::SecretStore).not_to receive(:purge_account)

    described_class.run_due!

    expect(task.reload).to have_attributes(status: "dead", last_error_class: "AttemptCapExceeded")
  end

  it "goes dead after the attempt cap instead of retrying forever" do
    task = due_task
    task.update_columns(attempts: described_class::MAX_ATTEMPTS - 1)
    allow(Security::SecretStore).to receive(:purge_account).and_raise(Security::SecretStore::BackendUnavailable)

    described_class.run_due!

    expect(task.reload).to have_attributes(status: "dead", attempts: described_class::MAX_ATTEMPTS)
    expect(described_class.due).not_to include(task)
  end

  it "claims rows with FOR UPDATE SKIP LOCKED so concurrent sweeps never run a task twice" do
    due_task
    sql = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| sql << payload[:sql] }
    allow(Security::SecretStore).to receive(:purge_account).and_return(0)

    described_class.run_due!
    ActiveSupport::Notifications.unsubscribe(sub)

    expect(sql.grep(/platform_purge_tasks/).grep(/FOR UPDATE SKIP LOCKED/)).not_to be_empty
  end

  it "counts an attempt and backs off even when the purge raises a database error (no endless instant retry)" do
    task = due_task
    allow(Security::SecretStore).to receive(:purge_account).and_raise(ActiveRecord::StatementInvalid, "PG::UndefinedTable")

    described_class.run_due!

    task.reload
    expect(task.attempts).to eq(2)
    expect(task.status).to eq("pending")
    expect(described_class.due).not_to include(task)
  end

  it "purges outside any transaction, so no row lock is held across the Vault call" do
    due_task
    baseline = ActiveRecord::Base.connection.open_transactions
    seen = nil
    allow(Security::SecretStore).to receive(:purge_account) do
      seen = ActiveRecord::Base.connection.open_transactions
      0
    end

    described_class.run_due!

    expect(seen).to eq(baseline)
  end

  it "survives a failure to record the retry (logs, does not raise)" do
    task = due_task
    allow(Security::SecretStore).to receive(:purge_account).and_raise(Security::SecretStore::BackendUnavailable)
    allow_any_instance_of(described_class).to receive(:update!).and_wrap_original do |orig, **attrs|
      raise ActiveRecord::StatementInvalid, "db down" if attrs.key?(:last_error_class) # the outcome write; the claim still succeeds

      orig.call(**attrs)
    end

    expect { described_class.run_due! }.not_to raise_error
    expect(task.reload.status).to eq("pending")
  end

  it "does not raise when the retry record itself cannot be written after a failed purge" do
    allow(described_class).to receive(:find_or_initialize_by).and_raise(ActiveRecord::StatementInvalid, "db down")
    account = create(:account)
    allow(Security::SecretStore).to receive(:purge_account).and_raise(Security::SecretStore::BackendUnavailable)

    expect(Rails.logger).to receive(:error).with(/purge retry record FAILED/).at_least(:once)
    allow(Rails.logger).to receive(:error).and_call_original

    expect { account.destroy! }.not_to raise_error
    expect(Account.exists?(account.id)).to be false
  end
end

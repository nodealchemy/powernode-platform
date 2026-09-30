# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260930140000_widen_users_last_login_ip_to_text.rb")

# IMP-7552124d35c1 -- runs the real DDL. The example transaction rolls it back;
# the after(:context) hook drops the plan cache the DDL poisons (see
# spec/lint/migration_spec_plan_cache_spec.rb).
RSpec.describe WidenUsersLastLoginIpToText do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  after(:context) { ActiveRecord::Base.connection.clear_cache! }

  def column
    ActiveRecord::Base.connection.columns(:users).find { |c| c.name == "last_login_ip" }
  end

  it "is a no-op when the column is already wide" do
    expect(column.type).to eq(:text)

    expect { migration.up }.not_to raise_error
    expect(column.type).to eq(:text)
  end

  it "widens a narrow varchar(45) column to text" do
    ActiveRecord::Base.connection.change_column(:users, :last_login_ip, :string, limit: 45)
    expect(column.limit).to eq(45)

    migration.up

    expect(column.type).to eq(:text)
    expect(column.limit).to be_nil
  end

  it "narrows back on rollback while no value exceeds the old limit" do
    migration.down

    expect(column.limit).to eq(45)
  end

  it "keeps the column wide on rollback once it holds an over-limit value" do
    user = create(:user)
    user.update!(last_login_ip: "203.0.113.42")

    migration.down

    expect(column.type).to eq(:text)
    expect(user.reload.last_login_ip).to eq("203.0.113.42")
  end
end

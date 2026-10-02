# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261001130000_widen_execution_duration_ms_columns_to_bigint.rb")

# IMP-36483b880322 -- runs the real DDL. The example transaction rolls it back;
# the after(:context) hook drops the plan cache the DDL poisons (see
# spec/lint/migration_spec_plan_cache_spec.rb).
RSpec.describe WidenExecutionDurationMsColumnsToBigint do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  after(:context) { ActiveRecord::Base.connection.clear_cache! }

  def sql_type(table)
    ActiveRecord::Base.connection.columns(table).find { |c| c.name == "duration_ms" }.sql_type
  end

  described_class::COLUMNS.map(&:first).each do |table|
    it "#{table}: is a no-op when the column is already bigint" do
      expect(sql_type(table)).to eq("bigint")

      expect { migration.up }.not_to raise_error
      expect(sql_type(table)).to eq("bigint")
    end

    it "#{table}: widens an int4 column to bigint" do
      ActiveRecord::Base.connection.change_column(table, :duration_ms, :integer)
      expect(sql_type(table)).to eq("integer")

      migration.up

      expect(sql_type(table)).to eq("bigint")
    end
  end

  it "never raises out of up when a widening fails, leaves that column int4, and still widens the rest" do
    first, *rest = described_class::COLUMNS.map(&:first)
    described_class::COLUMNS.each { |t, c| ActiveRecord::Base.connection.change_column(t, c, :integer) }

    allow(migration).to receive(:change_column).and_wrap_original do |original, table, *args|
      raise ActiveRecord::LockWaitTimeout, "canceling statement due to lock timeout" if table == first

      original.call(table, *args)
    end
    expect(Rails.logger).to receive(:warn).with(/#{first}\.duration_ms NOT widened/).at_least(:once)
    allow(Rails.logger).to receive(:warn)

    expect { migration.up }.not_to raise_error

    expect(sql_type(first)).to eq("integer")
    rest.each { |table| expect(sql_type(table)).to eq("bigint") }
  end

  it "skips a missing table instead of raising" do
    stub_const("#{described_class}::COLUMNS", [ [ :no_such_table_for_duration, :duration_ms ] ])

    expect { migration.up }.not_to raise_error
  end

  it "refuses to narrow back on rollback once a row holds an over-int4 value" do
    record = create(:ai_dag_execution)
    record.update!(duration_ms: 3_000_000_000)

    expect { migration.down }.to raise_error(ActiveRecord::StatementInvalid)
  end
end

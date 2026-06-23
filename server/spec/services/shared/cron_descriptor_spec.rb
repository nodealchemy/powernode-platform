# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::CronDescriptor do
  def described(cron)
    described_class.describe(cron)
  end

  describe ".describe" do
    it "describes a weekday range with zero-padded time" do
      expect(described("0 9 * * 1-5")).to eq("At 09:00 on Monday through Friday")
    end

    it "uses interval phrasing for step minutes/hours" do
      expect(described("*/15 * * * *")).to eq("Every 15 minutes")
      expect(described("* * * * *")).to eq("Every minute")
      expect(described("0 * * * *")).to eq("Every hour")
      expect(described("0 */2 * * *")).to eq("Every 2 hours")
    end

    it "describes an explicit day-of-month with an ordinal suffix" do
      expect(described("0 0 1 * *")).to eq("At 00:00 on the 1st")
      expect(described("30 8 2 * *")).to eq("At 08:30 on the 2nd")
      expect(described("0 0 3 * *")).to eq("At 00:00 on the 3rd")
      expect(described("0 0 21 * *")).to eq("At 00:00 on the 21st")
    end

    it "applies the 11-13 ordinal special case (th, not st/nd/rd)" do
      expect(described("0 0 11 * *")).to eq("At 00:00 on the 11th")
      expect(described("0 0 12 * *")).to eq("At 00:00 on the 12th")
      expect(described("0 0 13 * *")).to eq("At 00:00 on the 13th")
    end

    it "handles single, comma, and named-range weekdays" do
      expect(described("30 8 * * 1")).to eq("At 08:30 on Monday")
      expect(described("0 0 * * 1,3")).to eq("At 00:00 on Monday, Wednesday")
      expect(described("0 0 * * 0,6")).to eq("At 00:00 on weekends")
    end

    it "combines day-of-month and weekday when both are set" do
      expect(described("0 0 15 * 1")).to eq("At 00:00 on the 15th and on Monday")
    end

    it "appends the month" do
      expect(described("0 0 1 1 *")).to eq("At 00:00 on the 1st in January")
    end

    it "returns the invalid guard for malformed / short expressions" do
      expect(described("bad")).to eq("Invalid cron expression")
      expect(described("0 9 * *")).to eq("Invalid cron expression")
      expect(described("")).to eq("Invalid cron expression")
    end
  end
end

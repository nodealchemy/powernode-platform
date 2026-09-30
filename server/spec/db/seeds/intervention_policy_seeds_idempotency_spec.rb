# frozen_string_literal: true

require "rails_helper"

# IMP-89c398dcbc15 — the seeds that write Ai::InterventionPolicy rows are
# CREATE-ONLY for a row's verb. On the live hub an operator flipped a seeded
# release.promote row from require_approval to auto_approve, and the next
# re-seed would have written require_approval straight back over the edit: a
# seed that overwrites `policy` treats every operator decision as drift.
RSpec.describe "intervention policy seeds are idempotent and never clobber an operator edit" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account) { create(:account, name: "Powernode Admin") }
  let!(:user)    { create(:user, account: account, email: "admin@powernode.org") }

  describe "autonomy_data_seed (account-wide global rows)" do
    let(:rows) { Ai::InterventionPolicy.where(account: account, scope: "global", ai_agent_id: nil, user_id: nil) }

    it "run twice creates each row once" do
      load_seed!("autonomy_data_seed.rb")
      first = rows.pluck(:id).sort
      expect(first.size).to eq(6)

      load_seed!("autonomy_data_seed.rb")

      expect(rows.pluck(:id).sort).to eq(first)
      full_key = %i[account_id scope ai_agent_id user_id action_category priority conditions]
      expect(rows.group(*full_key).having("COUNT(*) > 1").count).to be_empty
    end

    it "leaves an operator-edited verb, priority and deactivation alone" do
      load_seed!("autonomy_data_seed.rb")
      row = rows.find_by!(action_category: "proposal")
      row.update!(policy: "auto_approve", is_active: false, preferred_channels: %w[email])

      load_seed!("autonomy_data_seed.rb")

      row.reload
      expect(row.policy).to eq("auto_approve")
      expect(row.is_active).to be(false)
      expect(row.preferred_channels).to eq(%w[email])
      expect(rows.where(action_category: "proposal").count).to eq(1)
    end

    it "does not adopt an operator's CONDITIONAL row as the seed row" do
      tier = Ai::InterventionPolicy.create!(
        account: account, scope: "global", action_category: "status_update", policy: "block",
        priority: 7, conditions: { "trust_tier_minimum" => "trusted" }
      )

      load_seed!("autonomy_data_seed.rb")

      expect(tier.reload.policy).to eq("block")
      expect(rows.where(action_category: "status_update").count).to eq(2)
    end
  end
end

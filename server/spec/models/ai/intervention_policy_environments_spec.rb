# frozen_string_literal: true

require "rails_helper"

# conditions["environments"] is a LIST of this account's environment slugs
# (IMP-5d3471cd75e4). The policy panel used to write it as a comma-separated
# string ("staging,ops"), which environment_matches? read as the single slug
# "staging,ops": no environment has that slug, so the row silently never matched.
RSpec.describe Ai::InterventionPolicy, "conditions environments", type: :model do
  let(:account) { create(:account) }
  let(:staging) { Ai::Environment.find_by!(account: account, slug: "staging") }
  let(:ops)     { Ai::Environment.find_by!(account: account, slug: "ops") }
  let(:prod)    { Ai::Environment.find_by!(account: account, slug: "prod") }

  def policy(conditions, **attrs)
    described_class.new({ account: account, scope: "global", action_category: "release.promote",
                          policy: "require_approval", priority: 5, conditions: conditions }.merge(attrs))
  end

  def match?(row, environment)
    row.matches?(action_category: "release.promote", environment: environment)
  end

  describe "normalisation" do
    it "turns a comma-separated string into an array that matches each named environment" do
      row = policy({ "environments" => "staging, ops" })

      expect(row).to be_valid
      expect(row.conditions["environments"]).to eq(%w[staging ops])
      expect(match?(row, staging)).to be true
      expect(match?(row, ops)).to be true
      expect(match?(row, prod)).to be false
    end

    it "strips, drops blanks and de-duplicates a string" do
      row = policy({ "environments" => " staging ,, ops , staging " })

      expect(row).to be_valid
      expect(row.conditions["environments"]).to eq(%w[staging ops])
    end

    it "strips, drops blanks and de-duplicates an array" do
      row = policy({ "environments" => [ " staging ", "", "ops", "staging" ] })

      expect(row).to be_valid
      expect(row.conditions["environments"]).to eq(%w[staging ops])
    end

    it "leaves the other condition keys alone" do
      row = policy({ "environments" => "ops", "trust_tier_minimum" => "trusted" })

      expect(row).to be_valid
      expect(row.conditions).to eq({ "environments" => [ "ops" ], "trust_tier_minimum" => "trusted" })
    end

    it "refuses a value that is neither a string nor an array" do
      [ 5, { "a" => 1 }, true ].each do |bad|
        row = policy({ "environments" => bad })

        expect(row).not_to be_valid
        expect(row.errors[:conditions].join).to match(/environments must be a list of environment slugs/)
      end
    end

    it "refuses an array holding a non-string element" do
      row = policy({ "environments" => [ "ops", 3 ] })

      expect(row).not_to be_valid
      expect(row.errors[:conditions].join).to match(/environments must be a list of environment slugs/)
    end

    it "does not touch a row with no environments key" do
      row = policy({ "trust_tier_minimum" => "trusted" })

      expect(row).to be_valid
      expect(row.conditions).to eq({ "trust_tier_minimum" => "trusted" })
    end
  end

  describe "empty list" do
    # Refused, not stripped: a row written for a plane that ends up naming none
    # would otherwise broaden to EVERY environment (an auto_approve meant for
    # staging then applies in prod).
    it "is refused with the way out, for a string and an array alike" do
      [ " , ", "", [], [ " ", "" ] ].each do |empty|
        row = policy({ "environments" => empty })

        expect(row).not_to be_valid
        expect(row.errors[:conditions].join).to match(/names no environment; remove the environments key/)
      end
    end
  end

  describe "unknown slugs" do
    it "refuses a slug the account does not have, naming it and the known ones" do
      row = policy({ "environments" => "staging,qa-lab,nope" })

      expect(row).not_to be_valid
      message = row.errors[:conditions].join
      expect(message).to include("unknown environment(s): qa-lab, nope.")
      expect(message).to include("known: ")
      expect(message).to include("dev", "prod")
    end

    it "refuses another account's environment slug" do
      other = create(:account)
      create(:ai_environment, account: other, slug: "only-theirs")

      row = policy({ "environments" => [ "only-theirs" ] })

      expect(row).not_to be_valid
      expect(row.errors[:conditions].join).to include("only-theirs")
    end

    it "accepts a slug this account added" do
      create(:ai_environment, account: account, slug: "qa-lab")

      expect(policy({ "environments" => "qa-lab" })).to be_valid
    end
  end

  describe "only when conditions changed" do
    let!(:row) do
      described_class.create!(account: account, scope: "global", action_category: "release.promote",
                              policy: "require_approval", priority: 5, conditions: { "environments" => %w[staging ops] })
    end

    before do
      # the environment is deleted after the row was written
      Ai::Environment.find_by!(account: account, slug: "ops").destroy!
      row.reload
    end

    it "does not block an unrelated update on a row naming a since-deleted environment" do
      expect(row.update(is_active: false)).to be true
      expect(row.reload.is_active).to be false
      expect(row.conditions["environments"]).to eq(%w[staging ops])
    end

    it "does block a conditions edit that keeps the stale slug, saying how to fix it" do
      row.conditions = { "environments" => %w[staging ops], "trust_tier_minimum" => "trusted" }

      expect(row.save).to be false
      expect(row.errors[:conditions].join).to match(/ops.*Remove or replace/)
    end

    it "accepts the edit once the stale slug is dropped" do
      row.conditions = { "environments" => [ "staging" ] }

      expect(row.save).to be true
    end
  end

  describe "#environment_matches? for a well-formed array" do
    it "is unchanged: an array matches its members, a scoped row never matches an unknown environment" do
      row = policy({ "environments" => %w[staging ops] })

      expect(row).to be_valid
      expect(match?(row, staging)).to be true
      expect(match?(row, ops)).to be true
      expect(match?(row, prod)).to be false
      expect(match?(row, nil)).to be false
    end

    it "is unchanged: a row with no environments condition matches every environment and none" do
      row = policy({})

      expect(match?(row, prod)).to be true
      expect(match?(row, nil)).to be true
    end
  end
end

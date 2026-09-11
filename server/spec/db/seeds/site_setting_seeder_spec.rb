# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "support", "site_setting_seeder").to_s

# The site-settings block in db/seeds.rb ran every setting under ONE shared
# rescue. That rescue exists for a real reason — a blank contact_email once
# raised RecordInvalid and crash-looped fresh hub installs — but because it was
# shared, one failing `SiteSetting.set` (which calls save!) silently skipped
# every setting seeded AFTER it. The seeder rescues per setting instead: a
# failure is logged with its key and error class, collected, named in the
# summary line, and never re-raised, so it can neither abort the seed nor hide
# the settings behind it.
RSpec.describe "Powernode::Seeds::SiteSettingSeeder", type: :seed do
  let(:out) { StringIO.new }
  let(:seeder) { Powernode::Seeds::SiteSettingSeeder.new(out: out) }

  before { allow(Rails.logger).to receive(:error) }

  it "seeds the settings on both sides of a failing one, and names the failure" do
    seeder.set("seeder_spec_first", "one", description: "first", setting_type: "string")
    # A valueless string setting outside SiteSetting::BLANK_ALLOWED_KEYS is
    # rejected by the model — the failure this has to survive.
    seeder.set("seeder_spec_invalid", "", description: "valueless", setting_type: "string")
    seeder.set("seeder_spec_last", "three", description: "last", setting_type: "string")

    expect(SiteSetting.find_by(key: "seeder_spec_first")&.value).to eq("one")
    expect(SiteSetting.find_by(key: "seeder_spec_last")&.value).to eq("three")
    expect(SiteSetting.exists?(key: "seeder_spec_invalid")).to be(false)
    expect(seeder.failed_keys).to eq([ "seeder_spec_invalid" ])
    expect(Rails.logger).to have_received(:error)
      .with(a_string_including("seeder_spec_invalid", "ActiveRecord::RecordInvalid"))
  end

  it "ends on a summary line that names every failed key, and never raises" do
    expect {
      seeder.set("seeder_spec_bad_a", "", setting_type: "string")
      seeder.set("seeder_spec_ok", "fine", setting_type: "string")
      seeder.set("seeder_spec_bad_b", "", setting_type: "string")
      seeder.finish
    }.not_to raise_error

    expect(out.string).to include("seeder_spec_bad_a", "seeder_spec_bad_b")
    expect(out.string).not_to include("seeder_spec_ok")
  end

  it "reports a clean run as clean" do
    seeder.set("seeder_spec_ok", "fine", setting_type: "string")
    seeder.finish

    expect(seeder.failed_keys).to be_empty
    expect(out.string).not_to include("failed")
  end

  it "writes an unless-exists setting only when it is absent, so an operator's value survives a re-seed" do
    SiteSetting.set("seeder_spec_guarded", "true", setting_type: "boolean")

    seeder.set_unless_exists("seeder_spec_guarded", "false", setting_type: "boolean")
    seeder.set_unless_exists("seeder_spec_fresh", "false", setting_type: "boolean")

    expect(SiteSetting.find_by(key: "seeder_spec_guarded").value).to eq("true")
    expect(SiteSetting.find_by(key: "seeder_spec_fresh").value).to eq("false")
  end

  it "keeps db/seeds.rb's site-settings block on the seeder, never back on a shared rescue" do
    seeds = File.read(Rails.root.join("db", "seeds.rb"))
    block = seeds[/Creating default site settings.*?(?=^if Powernode::Seeds\.demo\?)/m]

    expect(block).to be_present
    expect(block).to include("SiteSettingSeeder")
    expect(block).not_to match(/^\s*SiteSetting\.set\(/)
  end
end

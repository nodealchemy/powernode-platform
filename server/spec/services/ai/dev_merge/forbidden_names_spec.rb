# frozen_string_literal: true

require "rails_helper"

# Which private-extension names a dev_merge_increment may never publish, and
# whether this host can know. Synthetic names only: a spec is a tracked file.
RSpec.describe Ai::DevMerge::ForbiddenNames do
  let(:registry) { {} }

  before do
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return([])
    allow(Powernode::ExtensionRegistry).to receive(:all).and_return(registry)
    allow(Powernode::ExtensionRegistry).to receive(:slugs) { registry.keys }
  end

  def declare(value)
    SiteSetting.set(described_class::SETTING_KEY, value, setting_type: "json")
  end

  it "names a private extension the registry has loaded even when extensions/private/ is empty" do
    registry.merge!("zz-loaded" => { private: true }, "public-one" => { private: false })

    result = described_class.resolve

    expect(result.names).to eq(%w[zz-loaded])
    expect(result).to be_determinate
  end

  it "unions the on-disk directories, the registry and the operator's declaration" do
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return(%w[zz-disk])
    registry["zz-loaded"] = { private: true }
    declare(%w[zz-declared zz-disk])

    expect(described_class.resolve.names).to eq(%w[zz-declared zz-disk zz-loaded])
  end

  it "answers a determinate [] in core mode: no extension registered at all" do
    result = described_class.resolve

    expect(result.names).to eq([])
    expect(result).to be_determinate
  end

  it "is INDETERMINATE when extensions are loaded, none is private here, and nothing was declared" do
    registry["public-one"] = { private: false }

    result = described_class.resolve

    expect(result).not_to be_determinate
    expect(result.reason).to include(described_class::SETTING_KEY)
  end

  it "lets the operator declare that none exist, with an explicit empty list" do
    registry["public-one"] = { private: false }
    declare([])

    result = described_class.resolve

    expect(result.names).to eq([])
    expect(result).to be_determinate
  end

  it "refuses a declaration that is not a list of slugs" do
    expect { declare({ "a" => 1 }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { declare([ "Not A Slug" ]) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "keeps the declaration off every public settings surface" do
    declare(%w[zz-declared])

    expect(SiteSetting.find_by(key: described_class::SETTING_KEY).is_public).to be(false)
  end

  it "never puts a name in its reason" do
    registry["public-one"] = { private: false }
    allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return([])

    expect(described_class.resolve.reason).not_to include("public-one")
  end
end

# frozen_string_literal: true

require "rails_helper"

# Shared::ExtensionPaths.private_slugs derives private-extension names the way
# the core-purity gate does: the directory names under extensions/private/.
# Built against a temporary tree with synthetic names, so the spec neither
# depends on nor names this checkout's private extensions.
RSpec.describe Shared::ExtensionPaths, ".private_slugs" do
  before do
    @root = Pathname.new(Dir.mktmpdir("ext-paths"))
    stub_const("Shared::ExtensionPaths::EXTENSIONS_ROOT", @root)
  end

  after { FileUtils.remove_entry(@root) }

  it "lists the directories under extensions/private, sorted" do
    FileUtils.mkdir_p(@root.join("private", "zz-beta"))
    FileUtils.mkdir_p(@root.join("private", "alpha"))
    FileUtils.mkdir_p(@root.join("public-one"))
    File.write(@root.join("private", "README"), "not an extension")

    expect(described_class.private_slugs).to eq(%w[alpha zz-beta])
  end

  it "is empty in core mode, when there is no private directory" do
    FileUtils.mkdir_p(@root.join("public-one"))

    expect(described_class.private_slugs).to eq([])
  end
end

# frozen_string_literal: true

# SystemSkillsCatalog is a pure-Ruby Markdown renderer (no ActiveRecord), so this
# is a fast unit spec on spec_helper rather than the DB-booting rails_helper.
# Under the full suite rails_helper autoloads the constant via zeitwerk; run
# standalone we load it directly.
require "spec_helper"
require "active_support/core_ext/string/inflections" # String#titleize, used by the renderer
require_relative "../../lib/system_skills_catalog" unless defined?(SystemSkillsCatalog)

RSpec.describe SystemSkillsCatalog do
  describe ".github_slug" do
    it "preserves underscores (GFM keeps them in heading anchors)" do
      expect(described_class.github_slug("acme_certificate_provision"))
        .to eq("acme_certificate_provision")
    end

    it "does not hyphenate underscores" do
      expect(described_class.github_slug("attach_storage")).not_to eq("attach-storage")
    end

    it "downcases and turns spaces into hyphens" do
      expect(described_class.github_slug("Devops Tools")).to eq("devops-tools")
    end

    it "strips punctuation while keeping word characters and hyphens" do
      expect(described_class.github_slug("foo (bar)!")).to eq("foo-bar")
    end
  end

  describe ".render" do
    let(:executors) do
      [
        {
          name: "acme_certificate_provision",
          description: "Provision a cert.\nSecond line ignored in TOC.",
          category: "devops",
          executor_class: "System::Ai::Skills::AcmeCertificateProvisionExecutor",
          source_path: "extensions/system/server/app/services/system/ai/skills/acme_certificate_provision_executor.rb"
        },
        {
          name: "attach_storage",
          description: "Attach a volume.",
          category: "devops",
          executor_class: "System::Ai::Skills::AttachStorageExecutor",
          source_path: "extensions/system/server/app/services/system/ai/skills/attach_storage_executor.rb"
        },
        {
          name: "build_module_from_package",
          description: "Build a module.",
          category: "supply_chain",
          executor_class: "System::Ai::Skills::BuildModuleFromPackageExecutor",
          source_path: "extensions/system/server/app/services/system/ai/skills/build_module_from_package_executor.rb"
        }
      ]
    end

    subject(:markdown) do
      described_class.render(executors: executors, generated_at: "2026-01-01 00:00 UTC")
    end

    it "emits a TOC anchor for every executor that resolves to a detail heading" do
      toc_anchors   = markdown.scan(/^- \[`[^`]+`\]\(#([^)]+)\)/).flatten
      heading_slugs = markdown.scan(/^### `([^`]+)`$/).flatten.map { |h| described_class.github_slug(h) }

      expect(toc_anchors.size).to eq(executors.size)
      toc_anchors.each do |anchor|
        expect(heading_slugs).to include(anchor),
          "TOC link ##{anchor} points to a non-existent heading (heading slugs: #{heading_slugs.inspect})"
      end
    end

    it "preserves underscores in TOC anchors (does not hyphenate)" do
      expect(markdown).to include("[`acme_certificate_provision`](#acme_certificate_provision)")
      expect(markdown).not_to include("(#acme-certificate-provision)")
    end
  end
end

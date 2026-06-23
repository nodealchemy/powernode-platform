# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: relative image embeds in the frontend/docs Markdown must
# point at image files that actually exist. Screenshots referenced but never
# committed render as broken images in the docs.
#
# Reproduces IMP-8e1c64596d66: frontend/docs/CONTAINER_PATTERNS.md embedded
# underline-tabs.png / pill-tabs.png / default-tabs.png, none of which exist
# anywhere in the tree.
RSpec.describe 'frontend/docs image embeds' do
  repo_root = File.expand_path('../../..', __dir__)
  docs_dir = File.join(repo_root, 'frontend', 'docs')

  # ![alt](target) — capture the target path.
  image_embed = /!\[[^\]]*\]\(([^)]+)\)/

  it 'embeds only images that exist on disk' do
    broken = []

    Dir.glob(File.join(docs_dir, '**', '*.md')).sort.each do |md_path|
      File.read(md_path).scan(image_embed).flatten.each do |target|
        next if target.match?(%r{\A(?:https?:|data:|//|#)}) # external / inline / anchor

        rel_path = target.split(/[?#]/, 2).first # drop query/anchor fragments
        resolved = File.expand_path(rel_path, File.dirname(md_path))
        next if File.exist?(resolved)

        broken << "#{md_path.delete_prefix("#{repo_root}/")} → #{target}"
      end
    end

    expect(broken).to(
      be_empty,
      "Markdown files embed images that do not exist:\n#{broken.join("\n")}"
    )
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: release-process.md documents a dual-remoted repo whose
# stated policy is "Releases push to both" (origin = Gitea upstream, github =
# GitHub mirror). Every `git push origin <ref>` shown in a recipe must therefore
# be paired with a `git push github <ref>` for the SAME ref within the same
# ```bash block — otherwise a maintainer following the recipe verbatim leaves the
# public GitHub mirror lagging.
#
# (`git pull origin ...` is not a push and is intentionally not mirrored.)
#
# Scope: matches the plain `git push <remote> <ref>` form the recipes use. A
# wrapped form (`git -C <dir> push ...`, or a push behind `&&`) would not be seen
# — the recipes deliberately `cd` into the submodule and use the plain form.
RSpec.describe 'release-process.md dual-remote push pairing' do
  repo_root = File.expand_path('../../..', __dir__)
  doc_path  = File.join(repo_root, 'docs', 'contributing', 'release-process.md')
  doc       = File.read(doc_path)

  # Capture each ```bash fenced code block body.
  bash_blocks = doc.scan(/```bash\n(.*?)```/m).flatten

  def push_refs(block, remote)
    block.scan(/^[ \t]*git push #{remote} (.+)$/).flatten
         .map { |ref| ref.split('#').first.strip }
  end

  it 'pairs every `git push origin <ref>` with a `git push github <ref>`' do
    offenders = bash_blocks.each_with_index.flat_map do |block, idx|
      github_refs = push_refs(block, 'github')
      push_refs(block, 'origin').reject { |ref| github_refs.include?(ref) }
                                .map { |ref| "bash block ##{idx + 1}: `git push origin #{ref}` has no paired `git push github #{ref}`" }
    end

    expect(offenders).to(
      be_empty,
      "Unmirrored release pushes (policy: releases push to both origin + github):\n#{offenders.join("\n")}"
    )
  end
end

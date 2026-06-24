# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene guard: the dated AI-orchestration "priority next actions" session
# log must not live in the maintained docs tree. server/docs/platform/
# PRIORITY_NEXT_ACTIONS.md was a transient 2026-05-01 planning artifact —
# orphaned (zero inbound links) with every forward link dead (the four sibling
# docs it pointed at never existed). Per the File Organization conventions,
# transient session "next actions" logs do not belong in docs/.
#
# Reproduces IMP-1a8c16024ac6.
RSpec.describe 'orphaned session-artifact docs' do
  repo_root = File.expand_path('../../..', __dir__)

  it 'does not keep the transient PRIORITY_NEXT_ACTIONS session log in the docs tree' do
    orphan = File.join(repo_root, 'server', 'docs', 'platform', 'PRIORITY_NEXT_ACTIONS.md')

    expect(File.exist?(orphan)).to(
      be(false),
      'server/docs/platform/PRIORITY_NEXT_ACTIONS.md is an orphaned, dead-linked ' \
      'session artifact and should not be in the maintained docs tree'
    )
  end
end

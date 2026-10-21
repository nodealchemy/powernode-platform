# frozen_string_literal: true

require "spec_helper"

# The pre-push hook lives in the main checkout's .git/hooks, but a push from a linked
# worktree must run THAT worktree's checkers: the main checkout may sit on another branch
# with an older verify-submodule-pointers.sh that cannot verify the pushed commits.
RSpec.describe "scripts/install-git-hooks.sh pre-push hook" do
  let(:installer) { File.expand_path("../../../scripts/install-git-hooks.sh", __dir__) }
  let(:hook_body) do
    text = File.read(installer)
    start = text.index(%(cat > "$GIT_HOOKS_DIR/pre-push"))
    text[start...text.index("PUSH_HOOK_EOF", start + 40)]
  end

  it "resolves the project root from the checkout being pushed" do
    expect(hook_body).to include('PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null')
  end

  it "keeps the hooks-dir fallback for use outside a work tree" do
    expect(hook_body).to include('(cd "$SCRIPT_DIR/../.." && pwd)')
  end

  it "hands the raw push target ($1, a remote name OR a URL) to the checker, which resolves URLs" do
    expect(hook_body).to include('PUSH_REMOTE="${1:-origin}"')
    expect(hook_body).to include('--remote "$PUSH_REMOTE"')
  end
end

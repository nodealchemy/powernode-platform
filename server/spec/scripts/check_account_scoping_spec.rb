# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

# IMP-69483951e18e — the cross-tenant account-scoping (IDOR) guard
# `scripts/check-account-scoping.sh` grepped controller *.rb for the anti-pattern
# (`Model.all`, `Model.find(params[...])`) without distinguishing code from
# COMMENTS. A historical WHOLE-LINE comment in kb/comments_controller.rb
# ("# ...Previously KnowledgeBase::Comment.all surfaced every account's
# comments...") was flagged as a live IDOR, leaving pattern-validation.sh
# perpetually red on a false-positive — which erodes the gate and masks any real
# future regression.
#
# The fix suppresses a hit ONLY on a whole-line comment (first non-space char is
# '#', excluding '#{...}' interpolation). That is provably fail-safe: such a line
# holds zero executable Ruby, so it can never hide a real query. These specs pin
# both halves — the false-positive is gone, AND the guard still flags a real
# anti-pattern in every executable position (including the deceptive shapes where
# a '#' is NOT a comment: heredoc interpolation, regex/char literals).
RSpec.describe "check-account-scoping.sh comment false-positive (IMP-69483951e18e)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> /opt/powernode
  let(:script) { File.join(repo_root, "scripts/check-account-scoping.sh") }

  # Scan an isolated fixture tree (ACCOUNT_SCOPING_DIR) with an empty allowlist
  # so nothing is baselined — every genuine hit surfaces.
  def scan(controller_body)
    out = nil
    code = nil
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "fixture_controller.rb"), controller_body)
      allow = File.join(dir, "allow.txt")
      File.write(allow, "")
      o, s = Open3.capture2e(
        { "ACCOUNT_SCOPING_DIR" => dir, "ACCOUNT_SCOPING_ALLOWLIST" => allow },
        "bash", script
      )
      out = o
      code = s.exitstatus
    end
    [out, code]
  end

  # The concrete finding: the historical "# ...Previously KnowledgeBase::Comment.all
  # surfaced every account's comments..." note in kb/comments_controller.rb. Assert
  # that specific file is no longer flagged rather than whole-tree exit 0, so an
  # unrelated new hit elsewhere under api/v1 can't turn THIS spec red for reasons
  # that have nothing to do with comments.
  it "does not flag the historical whole-line comment in kb/comments_controller.rb (real tree)" do
    out, _status = Open3.capture2e("bash", script)
    expect(out).not_to include("comments_controller.rb"),
      "the historical 'KnowledgeBase::Comment.all' comment (line 58) must not be flagged; output:\n#{out}"
  end

  it "does NOT flag an anti-pattern that appears only inside a whole-line comment" do
    body = <<~RUBY
      # frozen_string_literal: true
      class WidgetsController < ApplicationController
        def index
          # Historical: Widget.all once surfaced every account's rows (cross-tenant).
          render_success(current_account.widgets)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(0), "whole-line comment match should not trip the guard; output:\n#{out}"
  end

  it "does NOT flag a whole-line comment even when indented and quoting the old code" do
    body = <<~RUBY
      class WidgetsController < ApplicationController
        def index
          # Admin view — scoped to current_account. Previously `Widget.all` and
          # "Widget.find(params[:id])" surfaced every account's rows cross-tenant.
          render_success(current_account.widgets)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(0), "indented/quoting comment lines should not trip the guard; output:\n#{out}"
  end

  # Exercise the RE_FINDER branch (find(params[...]) — the pattern behind the
  # original 17 IDOR bugs), not just RE_ALL, through the comment-suppression path.
  it "does NOT flag a find(params[...]) that appears only inside a whole-line comment" do
    body = <<~RUBY
      class WidgetsController < ApplicationController
        def show
          # Bugfix: was Widget.find(params[:id]) — now scoped through the tenant.
          render_success(current_account.widgets.find(params[:id]))
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(0), "comment-only find(params) should not trip the guard; output:\n#{out}"
  end

  it "STILL flags a bare Model.all in real code" do
    body = <<~RUBY
      class GadgetsController < ApplicationController
        def index
          render_success(Gadget.all)
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(1)
  end

  it "STILL flags real code even when a trailing comment follows it" do
    body = <<~RUBY
      class GadgetsController < ApplicationController
        def index
          render_success(Gadget.all) # list gadgets
        end
      end
    RUBY
    _out, status = scan(body)
    expect(status).to eq(1)
  end

  # Under-block guard: a heredoc body line can BEGIN with '#{...}' interpolation,
  # which is live code, not a comment. Suppressing it would hide a real IDOR — so
  # the '#{' exclusion must keep it flagged. (A naive `^\s*#` suppressor fails here.)
  it "STILL flags a real query inside heredoc interpolation that starts the line" do
    body = <<~RUBY
      class GadgetsController < ApplicationController
        def show
          body = <<~TEXT
            \#{Gadget.find(params[:id]).name}
          TEXT
          render_success(body)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "heredoc interpolation is live code, must stay flagged; output:\n#{out}"
  end

  # Under-block guard: a '#' that is NOT a comment (here a regex literal /#/) must
  # not cause the real query on the same line to be skipped.
  it "STILL flags a real query on a line whose '#' is inside a regex literal" do
    body = <<~RUBY
      class GadgetsController < ApplicationController
        def index
          _tag = (params[:q] =~ /#/) && render_success(Gadget.all)
        end
      end
    RUBY
    out, status = scan(body)
    expect(status).to eq(1), "a '#' inside a regex must not suppress the real query; output:\n#{out}"
  end
end

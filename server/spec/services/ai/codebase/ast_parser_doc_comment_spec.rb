# frozen_string_literal: true

require "rails_helper"

# Evaluated 2026-08-02 (docs/operations/code-index-retrieval-quality.md): the
# only text embedded per symbol was its own signature, so code_semantic_search
# behaved as a fuzzy identifier lookup. "kill switch emergency halt" scored 0.60
# and returned KillSwitchService; "immediately stop a runaway autonomous agent"
# returned unrelated methods at 0.49-0.52 — same target, same index. Doc
# comments are the only behavioural text available at parse time.
RSpec.describe Ai::Codebase::AstParserService do
  let(:parser) { described_class.new }

  def parse(source, name)
    path = File.join(Dir.mktmpdir, name)
    File.write(path, source)
    parser.parse(path)
  ensure
    FileUtils.remove_entry(File.dirname(path)) if path && File.exist?(path)
  end

  def doc_for(result, symbol_name)
    result[:symbols].find { |s| s[:name] == symbol_name }&.fetch(:doc)
  end

  describe "ruby" do
    it "attaches the comment directly above a method" do
      result = parse(<<~RUBY, "svc.rb")
        class KillSwitchService
          # Immediately stop every running agent and refuse new work.
          def emergency_halt!(reason:)
          end
        end
      RUBY

      expect(doc_for(result, "emergency_halt!"))
        .to eq("Immediately stop every running agent and refuse new work.")
    end

    it "joins a multi-line comment block" do
      result = parse(<<~RUBY, "svc.rb")
        # Pulls the trigger on the fleet.
        # Used by the operator kill switch.
        def halt
        end
      RUBY

      expect(doc_for(result, "halt")).to eq("Pulls the trigger on the fleet. Used by the operator kill switch.")
    end

    it "ignores a magic comment so pragmas do not become every file's description" do
      result = parse(<<~RUBY, "svc.rb")
        # frozen_string_literal: true
        def lonely
        end
      RUBY

      expect(doc_for(result, "lonely")).to be_nil
    end

    it "does not attach a comment separated by a blank line" do
      result = parse(<<~RUBY, "svc.rb")
        # Unrelated trailing note about the constant above.

        def detached
        end
      RUBY

      expect(doc_for(result, "detached")).to be_nil
    end

    it "leaves doc nil when there is no comment" do
      result = parse("def bare\nend\n", "svc.rb")
      expect(doc_for(result, "bare")).to be_nil
    end
  end

  describe "typescript" do
    it "attaches a JSDoc block" do
      result = parse(<<~TS, "widget.ts")
        /**
         * Hides the menu unless the viewer holds the permission.
         */
        export function guardMenu(user: User) {}
      TS

      expect(doc_for(result, "guardMenu")).to include("Hides the menu unless the viewer holds the permission.")
    end

    it "attaches a line comment and steps over a decorator" do
      result = parse(<<~TS, "widget.ts")
        // Renders the audit trail for one account.
        @Component({})
        export class AuditPanel {}
      TS

      expect(doc_for(result, "AuditPanel")).to eq("Renders the audit trail for one account.")
    end
  end

  describe "python" do
    it "attaches a docstring, which follows rather than precedes the def" do
      result = parse(<<~PY, "job.py")
        def reap(pool):
            """Terminate pool members that failed to drain."""
            pass
      PY

      expect(doc_for(result, "reap")).to eq("Terminate pool members that failed to drain.")
    end

    it "attaches a multi-line docstring" do
      result = parse(<<~PY, "job.py")
        def sync():
            """
            Pull upstream package metadata.
            """
            pass
      PY

      expect(doc_for(result, "sync")).to include("Pull upstream package metadata.")
    end
  end

  describe "truncation" do
    it "caps very long docs so one symbol cannot dominate a batch's token budget" do
      result = parse("# #{'x' * 900}\ndef verbose\nend\n", "svc.rb")

      expect(doc_for(result, "verbose").length).to be <= described_class::DOC_MAX_CHARS
    end
  end
end

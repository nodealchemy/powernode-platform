# frozen_string_literal: true

require "rails_helper"

# IMP-5ed95e651b80 — MCP tool results persist to
# ai_messages.processing_metadata and are FORWARDED TO THE MODEL PROVIDER.
# A raw driver/framework exception message can name tables, constraints,
# columns, paths, hostnames or other internal identifiers that have no
# business crossing that trust boundary. rescued_error_result is the shared
# seam every tool rescue arm should route through instead of echoing e.message
# straight into the provider-facing result.
RSpec.describe "BaseTool#rescued_error_result" do
  let(:account) { create(:account) }
  let!(:agent) { create(:ai_agent, account: account) }
  let(:tool) { Ai::Tools::BaseTool.new(account: account, agent: agent) }

  describe "#rescued_error_result" do
    let(:raw) { ArgumentError.new("column \"internal_secret_column\" does not exist") }

    # rescued_error_result is `protected` (same visibility as error_result/
    # success_result it sits beside) — called via .send, exactly like
    # base_tool_spec.rb calls tool.send(:account). Every example below
    # references `tool`/`agent` FIRST, forcing the (unmocked) ai_agent
    # factory's own MCP registration to run before any Rails.logger
    # expectation is installed — a strict `receive(:error).with(...)` would
    # otherwise also intercept the factory's own incidental logging and fail
    # on an unrelated argument mismatch.
    it "logs the exception class and full raw message server-side" do
      tool
      expect(Rails.logger).to receive(:error).with(a_string_including(
        "Ai::Tools::BaseTool", "ArgumentError", "internal_secret_column"
      ))
      tool.send(:rescued_error_result, raw)
    end

    it "returns the generic default when no message: is given" do
      tool
      allow(Rails.logger).to receive(:error)
      result = tool.send(:rescued_error_result, raw)
      expect(result).to eq(success: false, error: "An internal error occurred processing this request.")
    end

    it "returns the caller-supplied message: instead of the generic default" do
      tool
      allow(Rails.logger).to receive(:error)
      result = tool.send(:rescued_error_result, raw, message: "Team not found")
      expect(result).to eq(success: false, error: "Team not found")
    end

    it "never lets the raw exception message reach the returned result" do
      tool
      allow(Rails.logger).to receive(:error)
      result = tool.send(:rescued_error_result, raw, message: "Something went wrong")
      expect(result[:error]).not_to include("internal_secret_column")
    end
  end

  # THE DEFECT, DIRECTLY (IMP-5ed95e651b80's representative arm). This is the
  # exact seam the survey started from: run_through_autonomy_gate's
  # gate_context rescue (base_tool.rb ~1020-1023). Before the fix, a raw
  # ActiveRecord::RecordNotFound message — including whatever the finder's
  # own auto-generated text names — reached the provider-facing result
  # verbatim. This spec proves it no longer does, with the raw text used as
  # bait so a regression back to `error_result(e.message)` fails loudly.
  describe "run_through_autonomy_gate's gate_context rescue (representative arm)" do
    let(:tool_class) do
      klass = Class.new(::Ai::Tools::BaseTool) do
        def self.definition
          {
            name: "spec_rescued_error_result_tool",
            description: "probe for the gate_context rescue arm",
            parameters: { action: { type: "string", required: false } }
          }
        end

        declare_action "spec_gated_write",
                       mutating: true,
                       action_category: "spec.rescued_error_result.write",
                       executor_class: "Ai::Executors::DeferredToolCall",
                       gate_context: :raising_gate_context,
                       on_proceed: :never_reached_result

        define_method(:raising_gate_context) do |_params|
          # Mirrors a REAL finder's own auto-generated message shape, so the
          # bait is representative of what this arm actually guards against
          # — not a message the test author invented to be conveniently
          # revealing.
          raise ActiveRecord::RecordNotFound,
                "Couldn't find Ai::Agent with 'id'=deadbeef-internal-agent-id"
        end

        define_method(:never_reached_result) { |*| { success: true } }

        define_method(:call) { |_params| success_result(ran: true) }
      end
      klass.const_set(:REQUIRED_PERMISSION, nil)
      stub_const("SpecRescuedErrorResultTool", klass)
    end

    it "does not leak the raw finder message to the provider-facing result" do
      tool_class
      agent
      allow(Rails.logger).to receive(:error)

      result = SpecRescuedErrorResultTool.new(account: account, agent: agent)
                                          .execute(params: { action: "spec_gated_write" })

      expect(result[:success]).to be false
      expect(result[:error]).not_to include("deadbeef-internal-agent-id")
      expect(result[:error]).not_to include("Ai::Agent")
    end

    it "still logs the full raw message server-side for debugging" do
      tool_class
      agent
      expect(Rails.logger).to receive(:error).with(a_string_including("deadbeef-internal-agent-id"))

      SpecRescuedErrorResultTool.new(account: account, agent: agent)
                                 .execute(params: { action: "spec_gated_write" })
    end
  end

  # THE SPLIT, TAKE TWO. The first version of this arm keyed "safe to
  # forward" on the exception's CLASS (bare ArgumentError) — review correctly
  # rejected that as unsound: ArgumentError is not this codebase's to control,
  # Ruby and the stdlib raise it too (Integer("abc"), Date.parse, Float(), ...)
  # with messages nobody here authored. BaseTool::CallerFacingError (a
  # subclass of ArgumentError, so every EXISTING `rescue ArgumentError`
  # elsewhere keeps working unchanged) forwards by INTENT instead: a raiser
  # opts in explicitly (mutate_skill_gate_context, evolve_threshold,
  # deferred_tool_call_context all do). The two examples below are the shape
  # that actually decides this design is correct — the second is the one that
  # would have passed against the rejected class-keyed version, which is
  # exactly why it matters.
  describe "run_through_autonomy_gate's gate_context rescue — forwards by INTENT (CallerFacingError), not by class" do
    def build_gate_context_tool(raising:)
      klass = Class.new(::Ai::Tools::BaseTool) do
        def self.definition
          {
            name: "spec_gate_context_intent_tool",
            description: "probe for the CallerFacingError / bare ArgumentError split",
            parameters: { action: { type: "string", required: false } }
          }
        end

        declare_action "spec_gated_write",
                       mutating: true,
                       action_category: "spec.rescued_error_result.intent",
                       executor_class: "Ai::Executors::DeferredToolCall",
                       gate_context: :raising_gate_context,
                       on_proceed: :never_reached_result

        define_method(:never_reached_result) { |*| { success: true } }
        define_method(:call) { |_params| success_result(ran: true) }
      end
      klass.define_method(:raising_gate_context) { |_params| raising.call }
      klass.const_set(:REQUIRED_PERMISSION, nil)
      klass
    end

    # THE RESCUE ORDER ITSELF, tested directly. CallerFacingError must be
    # rescued BEFORE the bare ArgumentError clause — it IS an ArgumentError,
    # so if the clauses were swapped, Ruby's first-match dispatch would catch
    # every CallerFacingError in the (now-first) bare ArgumentError clause
    # and the verbatim-preservation behaviour would silently vanish, nothing
    # failing except this. Both shapes go through the SAME real seam in ONE
    # example specifically so a reorder — not just a merge of the two
    # clauses, already proven red/green above — shows up as a failure here.
    it "preserves CallerFacingError verbatim AND sanitizes bare ArgumentError from the SAME seam, order-sensitively" do
      caller_facing_klass = build_gate_context_tool(raising: -> { raise Ai::Tools::BaseTool::CallerFacingError, "Skill not found" })
      stub_const("SpecOrderCallerFacingTool", caller_facing_klass)
      bare_argument_error_klass = build_gate_context_tool(raising: -> { Integer("not-a-number-internal-detail") })
      stub_const("SpecOrderBareArgumentErrorTool", bare_argument_error_klass)
      agent
      allow(Rails.logger).to receive(:error)

      caller_facing_result = SpecOrderCallerFacingTool.new(account: account, agent: agent)
                                                       .execute(params: { action: "spec_gated_write" })
      bare_result = SpecOrderBareArgumentErrorTool.new(account: account, agent: agent)
                                                   .execute(params: { action: "spec_gated_write" })

      expect(caller_facing_result[:error]).to eq("Skill not found")
      expect(bare_result[:error]).to eq("An internal error occurred processing this request.")
    end

    it "returns a CallerFacingError's exact message, not the generic default — the deliberate-opt-in arm" do
      # Mirrors self_improvement_tool.rb's `raise CallerFacingError, "Skill
      # not found"`: a raiser explicitly choosing the intentional class.
      klass = build_gate_context_tool(raising: -> { raise Ai::Tools::BaseTool::CallerFacingError, "Skill not found" })
      stub_const("SpecCallerFacingTool", klass)
      agent
      allow(Rails.logger).to receive(:error)

      result = SpecCallerFacingTool.new(account: account, agent: agent)
                                    .execute(params: { action: "spec_gated_write" })

      expect(result).to eq(success: false, error: "Skill not found")
    end

    it "sanitizes an INCIDENTAL ArgumentError that never opted into CallerFacingError — the input that makes the guard fire" do
      # NOT raised by this tool's own explicit choice — stands in for a
      # stdlib/library call inside a real gate_context method (Integer(),
      # Date.parse, Float(), ...) raising bare ArgumentError with content
      # nobody here authored or reviewed. This is the exact case the
      # class-keyed version of this split would have forwarded verbatim; a
      # regression back to that shape passes the example above and fails
      # only here.
      klass = build_gate_context_tool(raising: -> { Integer("not-a-number-internal-detail") })
      stub_const("SpecIncidentalArgumentErrorTool", klass)
      agent
      allow(Rails.logger).to receive(:error)

      result = SpecIncidentalArgumentErrorTool.new(account: account, agent: agent)
                                               .execute(params: { action: "spec_gated_write" })

      expect(result[:success]).to be false
      expect(result[:error]).to eq("An internal error occurred processing this request.")
      expect(result[:error]).not_to include("not-a-number-internal-detail")
    end

    it "still logs the CallerFacingError's message server-side" do
      klass = build_gate_context_tool(raising: -> { raise Ai::Tools::BaseTool::CallerFacingError, "Skill not found" })
      stub_const("SpecCallerFacingLogTool", klass)
      agent
      expect(Rails.logger).to receive(:error).with(a_string_including("Skill not found"))

      SpecCallerFacingLogTool.new(account: account, agent: agent)
                              .execute(params: { action: "spec_gated_write" })
    end

    it "still logs the incidental ArgumentError's full raw message server-side for debugging" do
      klass = build_gate_context_tool(raising: -> { Integer("not-a-number-internal-detail") })
      stub_const("SpecIncidentalArgumentErrorLogTool", klass)
      agent
      expect(Rails.logger).to receive(:error).with(a_string_including("not-a-number-internal-detail"))

      SpecIncidentalArgumentErrorLogTool.new(account: account, agent: agent)
                                         .execute(params: { action: "spec_gated_write" })
    end
  end
end

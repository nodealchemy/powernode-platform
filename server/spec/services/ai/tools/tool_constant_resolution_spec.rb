# frozen_string_literal: true

require "rails_helper"

# IMP-4707960fc610.
#
# `platform_validate_plan` and `platform_approve_plan` were advertised on the
# MCP catalog while their bodies constantized `Ai::Autonomy::PlanValidationService`
# and `Ai::Autonomy::PlanApprovalService`, which exist in neither core nor any
# extension. Both bodies carried `rescue NameError`, so the only behaviour those
# two verbs ever had was returning "…service not available" — on every account,
# on every deployment, silently. The rescue arm made the defect look like a
# normal refusal, so nothing raised, nothing logged, and no spec went red.
#
# This guard is deliberately NOT "the registry lacks the key I just deleted",
# which would be a tautology that could never catch the next one. It asserts the
# general property: every namespaced constant a registered MCP tool class
# references must resolve. That catches this defect and every future instance of
# its shape, including in extension-registered tool maps.
#
# The computation lives in spec/support/tool_constant_resolution.rb so its
# oracle can be driven with synthetic sources (below) and so a mutant can be
# injected with `rspec -r` without editing anything in the repo.
RSpec.describe "MCP tool constant resolution" do
  subject(:report) { ToolConstantResolution.report }

  it "references no constant that does not exist" do
    expect(report[:unresolved]).to be_empty, lambda {
      "#{report[:unresolved].size} constant reference(s) in registered MCP tool classes resolve " \
      "to nothing. A verb whose body constantizes a missing class does not fail loudly — if the " \
      "body rescues NameError it is advertised on the catalog while being permanently inert:\n  " +
        report[:unresolved].map { |e| "#{e[:tool_class]} -> #{e[:constant]}  (#{e[:file]})" }.join("\n  ")
    }
  end

  it "routes every registry key to a class that loads" do
    expect(report[:unresolvable_classes]).to be_empty, lambda {
      "registry entries naming a class nobody can load:\n  " +
        report[:unresolvable_classes].join("\n  ")
    }
  end

  # Without this the whole file could go green on an empty registry, an empty
  # class list, or a walk that silently stopped extracting constants — the three
  # ways a check of this shape rots into a no-op.
  it "is not vacuous: it actually walked the registry and extracted constants" do
    expect(report[:registry_keys]).to be > 100
    expect(report[:classes_scanned]).to be > 20
    # ~319 namespaced paths exist across the core tool tree today. Pinned near
# that, not at 100: a walk that regressed to partial extraction would still
# clear a low bar, and partial under-extraction is the failure mode that
# hides an offender rather than announcing itself.
    expect(report[:paths_scanned]).to be > 250
    expect(ToolConstantResolution.registry_map).to include("decompose_goal")
  end

  describe "the oracle is genuinely red, and discriminates" do
    # `zz_` prefix: these are mutation fixtures, not real surface.
    let(:missing_constant) { "Ai::Autonomy::ZzNonexistentPlanValidationService" }

    it "flags a body that constantizes a class which exists nowhere" do
      source = <<~RUBY
        module Ai
          module Tools
            class ZzFixtureTool
              def validate_plan(goal)
                #{missing_constant}.new(goal: goal).validate
              rescue NameError
                { error: "Plan validation service not available" }
              end
            end
          end
        end
      RUBY

      expect(ToolConstantResolution.unresolved_in_source(source, "Ai::Tools::ZzFixtureTool"))
        .to contain_exactly(missing_constant)
    end

    it "does not flag the identical shape when the class DOES exist" do
      source = <<~RUBY
        module Ai
          module Tools
            class ZzFixtureTool
              def decompose(goal)
                Ai::Autonomy::GoalDecompositionService.new(account: goal.account).decompose(goal)
              rescue NameError
                { error: "not available" }
              end
            end
          end
        end
      RUBY

      expect(ToolConstantResolution.unresolved_in_source(source, "Ai::Tools::ZzFixtureTool")).to be_empty
    end

    it "resolves a path written relative to the owner's enclosing module" do
      # Written inside Ai::Tools, `Autonomy::GoalDecompositionService` is
      # Ai::Autonomy::GoalDecompositionService. A naive absolute-only resolver
      # would report this as missing.
      source = "Autonomy::GoalDecompositionService.new(account: nil)"

      expect(ToolConstantResolution.unresolved_in_source(source, "Ai::Tools::ZzFixtureTool")).to be_empty
    end

    it "skips a reference the author declared conditional with defined?" do
      source = "if defined?(Ai::Autonomy::ZzOptionalExtensionService) then 1 else 2 end"

      expect(ToolConstantResolution.unresolved_in_source(source, "Ai::Tools::ZzFixtureTool")).to be_empty
    end

    it "ignores bare unnamespaced constants rather than reporting local noise" do
      expect(ToolConstantResolution.constant_paths("ZZ_SOME_LOCAL_CONSTANT")).to be_empty
    end

    it "flags an unresolvable class reached through the extension seam" do
      # The extension arm is not inert: all_tools merges extension_tools, so a
      # map plugged in via .register_extension_tools lands in the same walk.
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:extension_tools)
        .and_return("zz_constant_fixture_action" => "ZzNonexistentFixtureTool")

      expect(ToolConstantResolution.report[:unresolvable_classes]).to include("ZzNonexistentFixtureTool")
    end
  end
end

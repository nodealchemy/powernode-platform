# frozen_string_literal: true

require "rails_helper"

# IMP-217f4496a0a2 — BaseTool now refuses a key outside the routed action's
# declared schema. That is only honest while a tool body reads nothing it has
# not declared: a key read but undeclared is advertised nowhere, so a caller
# could never learn to send it, and with strictness on it could not send it at
# all. This holds each registry tool's source to its own declarations.
#
# It is EVIDENCE, NOT PROOF, and it checks the tool as a whole: a key declared by
# any one action passes, so it cannot see a per-action gap (the runtime check in
# BaseTool is the authority, and base_tool_unknown_params_spec covers it). It
# also follows `params.slice(*CONST)` into the constant, which is how
# system_update_module's auto_promote went undeclared. It does not follow
# `params.to_h` forwarding or `params.merge`.
#
# It reads `params[:key]`, `params["key"]`, `params.dig(:key`, `params.fetch(:key`
# and `param(params, :key)` out of the tool's own file. Reads made in a helper
# file are out of its sight, so a green here is evidence, not proof; the runtime
# check is the authority.
RSpec.describe "registry tool parameter declarations" do
  READ_PATTERNS = [
    /\bparams\[\s*:([a-z_][a-z0-9_]*)\s*\]/,
    /\bparams\[\s*["']([a-z_][a-z0-9_]*)["']\s*\]/,
    /\bparams\.(?:dig|fetch)\(\s*:([a-z_][a-z0-9_]*)/,
    /\bparams\.(?:dig|fetch)\(\s*["']([a-z_][a-z0-9_]*)["']/,
    /\bparam\(\s*params\s*,\s*:([a-z_][a-z0-9_]*)\s*\)/
  ].freeze

  # Reads that are not caller input: injected by the platform, or by a binding.
  # expected_fingerprints is stamped onto tool_params by
  # SystemFleetTool#clear_ssh_host_key_gate_context at park time and read only on
  # the approved replay (which skips the unknown-parameter refusal), so a caller
  # is never asked to send it.
  PLATFORM_KEYS = %w[action ralph_loop_id expected_fingerprints].freeze

  def declared_keys(klass)
    keys = klass.action_definitions.values.flat_map do |defn|
      schema = Ai::Tools::ParameterSchema.build(defn[:parameters])
      schema["properties"].keys
    end
    umbrella = klass.definition[:parameters]
    keys += Ai::Tools::ParameterSchema.build(umbrella)["properties"].keys if umbrella.is_a?(Hash)
    (keys + PLATFORM_KEYS).uniq
  end

  def source_reads(klass)
    file = klass.instance_method(:call).source_location&.first
    file ||= Object.const_source_location(klass.name)&.first
    return [] unless file && File.file?(file)

    # Comments are prose, not reads (a comment may quote `params["x"]`).
    source = File.readlines(file).reject { |line| line.lstrip.start_with?("#") }.join
    reads = READ_PATTERNS.flat_map { |re| source.scan(re).flatten }
    reads += source.scan(/\bparams\.slice\(\*([A-Z][A-Z0-9_]*)\)/).flatten.flat_map do |const|
      value = klass.const_defined?(const) ? klass.const_get(const) : []
      Array(value).map(&:to_s)
    end
    reads.uniq
  end

  it "reads no parameter its own declarations omit" do
    offenders = Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |class_name|
      klass = class_name.constantize
      undeclared = source_reads(klass) - declared_keys(klass)
      "#{class_name}: #{undeclared.sort.join(', ')}" if undeclared.any?
    end

    expect(offenders).to eq([]), "tool bodies read parameters they never declare:\n#{offenders.join("\n")}"
  end
end

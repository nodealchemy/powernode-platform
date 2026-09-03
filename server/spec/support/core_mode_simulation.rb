# frozen_string_literal: true

# Simulates CORE mode (the `system` extension absent) inside a process that
# booted WITH the extension, for specs that build the whole MCP catalog.
#
# `hide_const("System")` alone removes the extension's model/service namespace,
# which is what a core-HOSTED, extension-BACKED tool (DiskImageOperatorTool,
# DockerProvisioningTool) checks before advertising its guarded actions. It
# leaves the extension's own tool CLASSES defined — a real core-mode boot would
# never load them — and that was harmless until an extension-hosted tool bound
# a parameter enum to one of its own model constants at definition time
# (system_storage_owner_tool.rb, `enum: ::System::StorageAssignment::OWNER_KINDS`):
# PlatformApiToolRegistry.tool_definitions then raises NameError from inside
# `action_definitions`, and tools/list answers -32603 for a catalog that, in
# real core mode, would simply not contain that tool.
#
# So the faithful simulation removes those tools from the registry's ONE
# enumeration seam (`PlatformApiToolRegistry.all_tools`, which every lookup and
# iteration path reads) for the duration of the example — the same catalog a
# core boot produces, where `available_tools` skips each of them on the
# constantize NameError. It deliberately does NOT hide the classes themselves:
# rspec-mocks restores a hidden constant with `const_set`, which moves the
# constant's recorded source location onto mutate_const.rb, and that poisons
# every later spec in the process that reads `const_source_location` (the
# tool-constant-resolution guard parsed rspec's own file as SdwanTool's source).
# Extension-hosted means "defined in a file under extensions/", read off the
# class's own methods so no list has to be maintained.
module CoreModeSimulation
  EXTENSION_SOURCE = %r{/extensions/}

  def hide_system_extension
    # Classify BEFORE hiding `System`: loading a not-yet-autoloaded tool class
    # may touch `System` at class-body level. Classify by the class's OWN method
    # source locations, not `const_source_location`, which reports Zeitwerk's
    # autoload stub for a class that has not been loaded yet.
    # A single-action tool inherits `action_definitions` from BaseTool (e.g.
    # SystemBlastRadiusTool), so also consult `definition` and the tool's own
    # `call` — every tool defines at least one of the three in its own file.
    extension_hosted = ::Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.select do |class_name|
      klass = class_name.safe_constantize
      next false unless klass

      extension_hosted_class?(klass)
    end

    registry = ::Ai::Tools::PlatformApiToolRegistry
    core_only = registry.all_tools.reject { |_name, class_name| extension_hosted.include?(class_name) }.freeze

    hide_const("System")
    allow(registry).to receive(:all_tools).and_return(core_only)
  end

  def extension_hosted_class?(klass)
    locations = []
    locations << klass.method(:action_definitions).source_location if klass.respond_to?(:action_definitions)
    locations << klass.method(:definition).source_location if klass.respond_to?(:definition)
    locations << klass.instance_method(:call).source_location if klass.method_defined?(:call, true)
    locations.compact.any? { |location| location.first.to_s.match?(EXTENSION_SOURCE) }
  end
end

RSpec.configure do |config|
  config.include CoreModeSimulation
end

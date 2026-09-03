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
# So the faithful simulation hides those classes too. The registry already
# tolerates a missing tool class (`available_tools` rescues the constantize
# NameError and skips the entry), which is exactly the path a real core boot
# takes. Extension-hosted means "defined in a file under extensions/", read off
# the constant's own source location so no list has to be maintained.
module CoreModeSimulation
  EXTENSION_SOURCE = %r{/extensions/}

  def hide_system_extension
    # Classify BEFORE hiding anything: a class Zeitwerk has not autoloaded yet
    # reports the autoload stub (zeitwerk/cref.rb) as its source location, not
    # its file, and loading it may touch `System` at class-body level.
    #
    # Classify by the class's OWN `action_definitions` source, not by
    # `const_source_location`: once a hidden constant has been restored by
    # rspec-mocks (`const_set`), the constant's recorded location is rspec's
    # mutate_const.rb, so a second spec file in the same process would classify
    # every previously hidden tool as core-hosted and hide nothing.
    # A single-action tool inherits `action_definitions` from BaseTool (e.g.
    # SystemBlastRadiusTool), so also consult `definition` and the tool's own
    # `call` — every tool defines at least one of the three in its own file.
    extension_hosted = ::Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.select do |class_name|
      klass = class_name.safe_constantize
      next false unless klass

      extension_hosted_class?(klass)
    end

    hide_const("System")
    extension_hosted.each { |class_name| hide_const(class_name) }
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

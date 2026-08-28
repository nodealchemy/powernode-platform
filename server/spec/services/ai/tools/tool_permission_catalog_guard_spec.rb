# frozen_string_literal: true

require "rails_helper"

# IMP-48abfa2f9e74 — THE GUARD THAT STOPS THE NEXT HALF-SWEEP.
#
# b7598df74 added the devops.docker.* family and retargeted the seven REST
# controllers onto it. The ten MCP tool classes covering the same surface were
# missed and kept gating on names (docker.containers.read, swarm.services.read,
# kubernetes.clusters.read, ...) that appear ZERO times in the catalog.
#
# An undeclared permission name does not fail loudly. User#has_permission? is an
# exact match against a role_permissions row plus a system.admin short-circuit,
# so an undeclared name can never match a row: the tool silently degrades to
# super-admin-only, while tools/list keeps advertising it to everyone. Nothing
# in the codebase noticed for months. Mcp::ProtocolService#invoke_tool resolves
# the same names by SUBTRACTION (required - user.permission_names) and denies an
# undeclared name to EVERYONE, system.admin included — so the two enforcement
# paths silently disagree for exactly the names this spec forbids.
#
# The oracle is therefore a whole-namespace sweep, not a list of the ten: every
# REQUIRED_PERMISSION floor and every ACTION_PERMISSIONS value on every
# Ai::Tools::BaseTool descendant (core AND extension) must be a name
# Permissions.permission_exists? recognizes.
RSpec.describe "MCP tool permission names are in the catalog" do
  # Known-uncatalogued names that this task did NOT fix, listed exactly so the
  # guard is a two-way oracle: a NEW offender fails, and so does a stale entry
  # here once its owner is fixed (remove the line at that point).
  #
  # Ai::Tools::PageManagementTool was surfaced by this very sweep. It is the
  # same defect class ("pages.manage" is not a catalog name; the page family is
  # page.read/create/update/delete/publish), but fixing it needs its own
  # read/write classification across a different action set, so it is reported
  # rather than swept in here. See the IMP-48abfa2f9e74 report.
  #
  # A method, not a constant: a constant assigned inside an RSpec block lands on
  # Object and can be clobbered by a same-named constant in another spec file,
  # which is an order-dependent flake waiting to happen.
  def known_uncatalogued
    [ "Ai::Tools::PageManagementTool REQUIRED_PERMISSION => pages.manage" ]
  end

  # LADDER COMPLETENESS — the gap the catalog check cannot see.
  #
  # The sweep above only asks "does this permission name exist in the catalog".
  # An action MISSING from its class's ACTION_PERMISSIONS falls back to the
  # class floor, and the floor is catalogued, so the catalog check passes
  # happily. In other words the guard written alongside IMP-48abfa2f9e74 could
  # not detect the very escalation that task existed to prevent: add a
  # docker_delete_everything action, forget its ladder entry, and it silently
  # sits at devops.docker.read.
  #
  # So state the rule the other way round: for each retargeted class, every
  # advertised action is EITHER laddered to .manage OR named here as a
  # deliberate read. Adding an action without classifying it fails this spec.
  # Each entry was verified against the REST twin's gate (see the commit).
  READ_TIER_ACTIONS = {
    "Ai::Tools::DockerContainerTool" => %w[
      docker_list_containers docker_get_container docker_container_logs docker_container_stats
    ],
    "Ai::Tools::DockerServiceTool" => %w[
      docker_list_services docker_get_service docker_service_logs docker_service_tasks
    ],
    "Ai::Tools::DockerClusterTool" => %w[
      docker_list_clusters docker_get_cluster docker_cluster_health docker_list_nodes
      docker_list_secrets docker_list_configs
    ],
    "Ai::Tools::DockerStackTool" => %w[docker_list_stacks docker_get_stack],
    "Ai::Tools::DockerNetworkVolumeTool" => %w[docker_list_networks docker_list_volumes],
    "Ai::Tools::DockerImageTool" => %w[docker_list_images],
    "Ai::Tools::DockerHostTool" => %w[docker_list_hosts docker_get_host docker_test_host]
  }.freeze

  it "classifies EVERY advertised action of a laddered class as manage or explicitly read" do
    unclassified = READ_TIER_ACTIONS.filter_map do |class_name, reads|
      klass = class_name.safe_constantize
      next unless klass

      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, v| v == class_name }.keys.map(&:to_s)
      laddered = klass.const_get(:ACTION_PERMISSIONS).keys.map(&:to_s)
      missing = advertised - laddered - reads
      ["#{class_name}: #{missing.join(', ')}"] if missing.any?
    end.flatten

    expect(unclassified).to be_empty,
                            "action(s) advertised but neither laddered to .manage nor listed as a deliberate " \
                            "read — they silently inherit the class's READ floor: #{unclassified.join('; ')}"
  end

  # Non-vacuity: the rule above is a "reject the bad ones" shape, which an empty
  # advertised list satisfies perfectly.
  it "has real actions to classify" do
    total = READ_TIER_ACTIONS.keys.sum do |class_name|
      ::Ai::Tools::PlatformApiToolRegistry.all_tools.count { |_, v| v == class_name }
    end
    expect(total).to be >= 50
  end

  def self.tool_classes
    Rails.application.eager_load!

    classes = ::Ai::Tools::BaseTool.descendants.dup
    # The registry is the surface MCP actually advertises; sweep it too so a
    # class that somehow escapes descendants (autoload ordering, a wrapper that
    # is not a BaseTool subclass) is still covered.
    registered = ::Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |name|
      name.safe_constantize
    end

    (classes | registered).select { |k| k.is_a?(Class) && k.name.present? }.sort_by(&:name)
  end

  # Every (class, source, permission) triple declared anywhere in the namespace.
  def declared_permissions
    self.class.tool_classes.flat_map do |klass|
      entries = []

      floor = klass::REQUIRED_PERMISSION
      entries << [ "#{klass.name} REQUIRED_PERMISSION", floor ] if floor.present?

      if klass.const_defined?(:ACTION_PERMISSIONS, false)
        klass.const_get(:ACTION_PERMISSIONS, false).each do |action, permission|
          entries << [ "#{klass.name} ACTION_PERMISSIONS[#{action}]", permission ] if permission.present?
        end
      end

      entries
    end
  end

  it "sweeps a non-trivial number of tool classes (a silent empty sweep is not a pass)" do
    expect(self.class.tool_classes.size).to be > 40
    expect(declared_permissions.size).to be > 60
  end

  it "declares no permission name that Permissions.permission_exists? rejects" do
    offenders = declared_permissions.filter_map do |label, permission|
      "#{label} => #{permission}" unless ::Permissions.permission_exists?(permission)
    end

    expect(offenders.sort).to eq(known_uncatalogued.sort), <<~MSG
      Uncatalogued MCP tool permission names.

      A name absent from config/permissions.rb can never match a role_permissions
      row, so the tool degrades to super-admin-only while tools/list still
      advertises it — and Mcp::ProtocolService denies it to everyone including
      system.admin. Either add the name to the catalog or retarget the tool onto
      a declared family (see IMP-48abfa2f9e74 / b7598df74).

      Unexpected: #{(offenders.sort - known_uncatalogued.sort).inspect}
      Stale exemptions (fixed — delete from known_uncatalogued): #{(known_uncatalogued.sort - offenders.sort).inspect}
    MSG
  end

  describe "the ten devops tool classes retargeted by IMP-48abfa2f9e74" do
    {
      "Ai::Tools::DockerContainerTool" => "devops.docker.read",
      "Ai::Tools::DockerImageTool" => "devops.docker.read",
      "Ai::Tools::DockerHostTool" => "devops.docker.read",
      "Ai::Tools::DockerProvisioningTool" => "devops.docker.manage",
      "Ai::Tools::DockerServiceTool" => "devops.swarm.read",
      "Ai::Tools::DockerStackTool" => "devops.swarm.read",
      "Ai::Tools::DockerClusterTool" => "devops.swarm.read",
      "Ai::Tools::DockerNetworkVolumeTool" => "devops.swarm.read",
      "Ai::Tools::KubernetesClusterTool" => "devops.kubernetes.read",
      "Ai::Tools::KubernetesProvisioningTool" => "devops.kubernetes.manage"
    }.each do |class_name, expected_floor|
      it "#{class_name} floors on #{expected_floor}" do
        expect(class_name.constantize::REQUIRED_PERMISSION).to eq(expected_floor)
      end
    end
  end

  # Every action the registry routes to one of these classes must resolve to a
  # catalogued permission — the ladder is only as complete as its coverage of
  # the dispatch arms.
  it "resolves every registered devops action to a catalogued permission" do
    devops_classes = %w[
      Ai::Tools::DockerContainerTool Ai::Tools::DockerImageTool Ai::Tools::DockerHostTool
      Ai::Tools::DockerProvisioningTool Ai::Tools::DockerServiceTool Ai::Tools::DockerStackTool
      Ai::Tools::DockerClusterTool Ai::Tools::DockerNetworkVolumeTool
      Ai::Tools::KubernetesClusterTool Ai::Tools::KubernetesProvisioningTool
    ]

    unresolved = []
    ::Ai::Tools::PlatformApiToolRegistry.all_tools.each do |action, class_name|
      next unless devops_classes.include?(class_name)

      klass = class_name.constantize
      permission =
        if klass.const_defined?(:ACTION_PERMISSIONS, false)
          klass.const_get(:ACTION_PERMISSIONS, false)[action]
        end
      permission ||= klass::REQUIRED_PERMISSION

      unresolved << "#{action} => #{permission.inspect}" unless ::Permissions.permission_exists?(permission.to_s)
    end

    expect(unresolved).to be_empty
  end
end

# frozen_string_literal: true

module Ai
  module Provisioning
    # Translates a provisioning plan DAG into the React-Flow-compatible JSON
    # the Plan Review modal's `<StackTopologyPreview />` consumes.
    #
    # Each plan step contributes one or more nodes to the topology graph. A
    # `provision_full_stack` step expands to: a region container node, an
    # external_provider node (the cloud), N compute nodes (per scale.initial),
    # one volume per compute, and one network node when SDWAN is in play.
    # Edges connect the user_device → gateway → network → compute, plus
    # data edges from compute → volume.
    #
    # When the plan plans network creation we ask
    # `Sdwan::TopologyCompiler.compile_for_network(network)` in dry-run mode
    # (the compiler now accepts un-persisted networks).
    #
    # Output shape (matches frontend ProvisioningPlan.topology_preview):
    #   {
    #     nodes:    [{ id, type, label, region_id?, parent_id? }],
    #     edges:    [{ from, to, label, kind: "tunnel"|"data"|"ingress" }],
    #     regions:  [{ id, name }],
    #     estimated_resources: [...]   # mirror of by_resource for tooltip overlay
    #   }
    class TopologyRendererService
      DEFAULT_INSTANCE_COUNT = 1

      COMPUTE_SKILLS = %w[
        provision_full_stack
        provision_cluster
        docker_provision
        rolling_module_upgrade
      ].freeze

      DATABASE_HINT_REGEX = /postgres|mysql|database|cluster|db|sql/i.freeze
      CACHE_HINT_REGEX    = /redis|cache|memcache/i.freeze

      attr_reader :account, :plan

      def initialize(account:, plan:)
        @account = account
        @plan = plan
      end

      def render
        brief    = brief_for(plan) || {}
        steps    = ordered_steps(plan)
        regions  = regions_for(brief)
        instance_count = instance_count_for(brief)

        nodes = []
        edges = []
        estimated_resources = []
        node_id_counter = { value: 0 }

        # User device + gateway are constants — every provisioned stack assumes
        # operator/end-user reach via SDWAN gateway.
        user_node    = build_node(node_id_counter, type: "user_device", label: "Operator")
        gateway_node = build_node(node_id_counter, type: "gateway",     label: "SDWAN Gateway")
        nodes << user_node << gateway_node
        edges << build_edge(source: user_node[:id], target: gateway_node[:id], label: "ingress", kind: "ingress")

        # One region container per region in the brief — compute nodes parent
        # under their region for visual grouping.
        region_nodes = regions.map.with_index do |region, idx|
          rnode = build_node(node_id_counter,
                             type: "network",
                             label: region[:name],
                             region_id: region[:id])
          nodes << rnode
          [region[:id], rnode]
        end.to_h

        # External provider node represents the underlying cloud — connects the
        # gateway to each region container.
        provider_node = build_node(node_id_counter, type: "external_provider", label: provider_label_for(brief))
        nodes << provider_node
        region_nodes.each_value do |rnode|
          edges << build_edge(source: gateway_node[:id], target: rnode[:id], label: "tunnel", kind: "tunnel")
        end
        edges << build_edge(source: provider_node[:id], target: gateway_node[:id], label: "control", kind: "tunnel")

        # Walk the plan steps and emit compute/volume/database/cache nodes as
        # the skills warrant.
        steps.each do |step|
          cfg    = (step.respond_to?(:execution_config) ? step.execution_config : {}) || {}
          cfg    = cfg.is_a?(Hash) ? cfg : {}
          skill  = (cfg["skill"] || cfg[:skill]).to_s
          inputs = cfg["inputs"] || cfg[:inputs] || {}
          inputs = inputs.is_a?(Hash) ? inputs : {}

          next unless COMPUTE_SKILLS.include?(skill)

          parent_region = region_nodes.values.first
          step_count = (inputs["count"] || inputs[:count] || instance_count).to_i
          step_count = 1 if step_count <= 0
          intent_text = "#{step.respond_to?(:description) ? step.description : ''} #{brief['intent']}"

          step_count.times do |idx|
            compute_label = label_for_compute(skill: skill, idx: idx, intent_text: intent_text)
            compute_type  = compute_type_for(intent_text)
            compute_node  = build_node(node_id_counter,
                                       type: compute_type,
                                       label: compute_label,
                                       parent_id: parent_region&.dig(:id),
                                       region_id: parent_region&.dig(:region_id))
            nodes << compute_node
            edges << build_edge(source: parent_region[:id], target: compute_node[:id], label: "lan", kind: "tunnel") if parent_region

            # Each compute gets a volume — UX clarity over compactness.
            volume_node = build_node(node_id_counter,
                                     type: "volume",
                                     label: "Volume #{idx + 1}",
                                     parent_id: parent_region&.dig(:id),
                                     region_id: parent_region&.dig(:region_id))
            nodes << volume_node
            edges << build_edge(source: compute_node[:id], target: volume_node[:id], label: "data", kind: "data")

            # Add a cache node for the first instance if the intent hints at one.
            if idx.zero? && intent_text.match?(CACHE_HINT_REGEX)
              cache_node = build_node(node_id_counter,
                                      type: "cache",
                                      label: "Cache",
                                      parent_id: parent_region&.dig(:id),
                                      region_id: parent_region&.dig(:region_id))
              nodes << cache_node
              edges << build_edge(source: compute_node[:id], target: cache_node[:id], label: "data", kind: "data")
            end

            estimated_resources << {
              resource_type: "compute",
              name: compute_label,
              region_id: parent_region&.dig(:region_id)
            }
          end

          # If this skill plans an SDWAN overlay, ask the compiler in dry-run
          # mode (compile_for_network now tolerates un-persisted networks and
          # returns []). This is forward-compat with M1.5 when steps will
          # carry sdwan_network: { name:, routing_protocol: } payloads.
          maybe_attach_sdwan_dry_run(inputs: inputs, gateway_node: gateway_node, edges: edges)
        end

        {
          nodes: nodes,
          edges: edges,
          regions: regions,
          estimated_resources: estimated_resources
        }
      end

      private

      def maybe_attach_sdwan_dry_run(inputs:, gateway_node:, edges:)
        sdwan_payload = inputs["sdwan_network"] || inputs[:sdwan_network]
        return unless sdwan_payload.is_a?(Hash) && defined?(::Sdwan::Network) && defined?(::Sdwan::TopologyCompiler)

        network = build_unpersisted_network(sdwan_payload)
        return unless network

        ::Sdwan::TopologyCompiler.compile_for_network(network)
      rescue StandardError => e
        Rails.logger.warn("[TopologyRendererService] sdwan dry-run failed: #{e.class}: #{e.message}")
      end

      def build_unpersisted_network(payload)
        ::Sdwan::Network.new(
          account_id: account.id,
          name: payload["name"] || payload[:name] || "preview-net",
          routing_protocol: payload["routing_protocol"] || payload[:routing_protocol] || "static",
          settings: payload["settings"] || payload[:settings] || {},
          status: "registered"
        )
      rescue StandardError
        nil
      end

      def label_for_compute(skill:, idx:, intent_text:)
        base =
          case skill
          when "provision_cluster"        then "Cluster node"
          when "docker_provision"         then "Docker host"
          when "rolling_module_upgrade"   then "Worker node"
          else "Compute node"
          end
        if intent_text.match?(DATABASE_HINT_REGEX) && idx.zero?
          "DB primary"
        elsif intent_text.match?(DATABASE_HINT_REGEX)
          "DB replica #{idx}"
        else
          "#{base} #{idx + 1}"
        end
      end

      def compute_type_for(intent_text)
        return "database" if intent_text.match?(DATABASE_HINT_REGEX)
        return "cache"    if intent_text.match?(CACHE_HINT_REGEX)
        "compute"
      end

      def regions_for(brief)
        list = Array(brief["regions"] || brief[:regions])
        list = ["default"] if list.empty?
        list.map.with_index { |code, idx| { id: "region-#{idx + 1}", name: code.to_s } }
      end

      def provider_label_for(brief)
        preferred = brief["preferred_provider"] || brief[:preferred_provider]
        preferred.presence || "Cloud provider"
      end

      def instance_count_for(brief)
        scale = brief["scale"] || brief[:scale] || {}
        scale = scale.is_a?(Hash) ? scale : {}
        (scale["initial"] || scale[:initial] || DEFAULT_INSTANCE_COUNT).to_i.then { |n| n.positive? ? n : DEFAULT_INSTANCE_COUNT }
      end

      def ordered_steps(plan)
        return [] unless plan&.respond_to?(:steps)
        relation = plan.steps
        relation.respond_to?(:in_order) ? relation.in_order.to_a : relation.to_a.sort_by { |s| s.step_number.to_i }
      end

      def brief_for(plan)
        meta = plan.respond_to?(:goal) ? plan.goal&.metadata : nil
        mission_id = meta.is_a?(Hash) ? meta["provisioning_mission_id"] : nil
        return nil unless mission_id

        mission = account.ai_missions.find_by(id: mission_id)
        cfg = mission&.configuration
        cfg.is_a?(Hash) ? (cfg["brief"] || cfg[:brief]) : nil
      rescue StandardError
        nil
      end

      def build_node(counter, type:, label:, region_id: nil, parent_id: nil)
        counter[:value] += 1
        node = { id: "n#{counter[:value]}", type: type, label: label }
        node[:region_id] = region_id if region_id
        node[:parent_id] = parent_id if parent_id
        node
      end

      def build_edge(source:, target:, label:, kind:)
        # Emit ReactFlow's canonical edge shape (source/target) so the
        # frontend StackTopologyPreview can pass these through unchanged.
        # Older callers used from/to; aligning to match the TS TopologyEdge.
        { source: source, target: target, label: label, kind: kind }
      end
    end
  end
end

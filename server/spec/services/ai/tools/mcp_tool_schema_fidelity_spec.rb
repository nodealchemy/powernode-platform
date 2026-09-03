# frozen_string_literal: true

require "rails_helper"

# IMP-e809396f9eda — the MCP parameter->JSON Schema conversion used to copy only
# `type` and `description` per parameter, so `enum`, `items`, `default` and
# nested `properties` declared on a tool parameter never reached an MCP client.
# Two independent copies did it: McpPlatformToolRegistrar.convert_to_json_schema
# (registry manifest + the mcp_tools rows) and the streamable-HTTP controller's
# build_input_schema (the tools/list wire). A strict client either drops an
# untyped array or rejects the tool outright, and a closed value set (e.g. a
# promote target of staging|blessed|live|retired) was only ever stated in prose.
#
# The second half: a tool whose action is parked by the autonomy gate returns
# success:true with a `data.pending` envelope (Ai::Tools::BaseTool#execute), and
# the advertised outputSchema declared only {success, error} — so "done" and
# "parked, nothing applied" were distinguishable only by reading a sentence.
RSpec.describe "MCP tool schema fidelity (IMP-e809396f9eda)" do
  describe "Ai::Tools::ParameterSchema" do
    subject(:described_module) { Ai::Tools::ParameterSchema }

    it "preserves enum on a closed value set" do
      schema = described_module.build(
        target: { type: "string", required: true, description: "Promote target",
                  enum: %w[staging blessed live retired] }
      )

      expect(schema["properties"]["target"]["enum"]).to eq(%w[staging blessed live retired])
    end

    it "preserves a declared items schema on an array parameter" do
      schema = described_module.build(
        tags: { type: "array", description: "Tags", items: { "type" => "string" } }
      )

      expect(schema["properties"]["tags"]["items"]).to eq({ "type" => "string" })
    end

    it "supplies a default items schema for an array that declares none" do
      schema = described_module.build(entity_types: { type: "array", description: "Filter" })

      expect(schema["properties"]["entity_types"]["items"]).to eq({ "type" => "string" })
    end

    it "preserves default and nested object properties" do
      schema = described_module.build(
        limit: { type: "integer", description: "Page size", default: 25 },
        filter: { type: "object", description: "Filter",
                  properties: { "state" => { "type" => "string" } } }
      )

      expect(schema["properties"]["limit"]["default"]).to eq(25)
      expect(schema["properties"]["filter"]["properties"]).to eq({ "state" => { "type" => "string" } })
    end

    it "marks a propertyless object as accepting free-form keys" do
      schema = described_module.build(options: { type: "object", description: "Options" })

      expect(schema["properties"]["options"]["additionalProperties"]).to be(true)
    end

    it "does not mistake a parameter NAMED type for a JSON Schema root" do
      schema = described_module.build(
        type: { type: "string", required: false, description: "Filter by notification type" },
        limit: { type: "integer", description: "Page size" }
      )

      expect(schema["properties"].keys).to contain_exactly("type", "limit")
      expect(schema["properties"]["type"]["type"]).to eq("string")
    end

    it "keeps required and properties on a passthrough schema that declares neither" do
      # Four tools ship `{ type: "object", properties: {} }`
      # (self_improvement_tool.rb, agent_memory_management_tool.rb,
      # coordination_tool.rb, governance_tool.rb). The streamable-HTTP copy this
      # replaced always emitted both containers; unifying must not drop them.
      schema = described_module.build(type: "object", properties: {})

      expect(schema).to eq({ "type" => "object", "properties" => {}, "required" => [] })
    end

    it "reads an ARRAY-valued required as the nested keyword, not the DSL flag" do
      schema = described_module.build(
        filter: { type: "object", description: "Filter",
                  properties: { "state" => { "type" => "string" } },
                  required: ["state"] }
      )

      expect(schema["required"]).to eq([])
      expect(schema["properties"]["filter"]["required"]).to eq(["state"])
    end

    it "passes through a parameter hash that is already a JSON Schema object" do
      schema = described_module.build(
        type: "object",
        properties: { "mode" => { "type" => "string", "enum" => %w[a b] } },
        required: [:mode]
      )

      expect(schema["properties"]["mode"]["enum"]).to eq(%w[a b])
      expect(schema["required"]).to eq(["mode"])
    end
  end

  describe Ai::Tools::McpPlatformToolRegistrar do
    it "carries enum/items/default through .convert_to_json_schema" do
      schema = described_class.send(
        :convert_to_json_schema,
        target: { type: "string", required: true, description: "t", enum: %w[live retired] },
        tags: { type: "array", description: "Tags" },
        limit: { type: "integer", description: "n", default: 25 }
      )

      expect(schema["properties"]["target"]["enum"]).to eq(%w[live retired])
      expect(schema["properties"]["tags"]["items"]).to eq({ "type" => "string" })
      expect(schema["properties"]["limit"]["default"]).to eq(25)
    end

    # The population the finding was MEASURED over, not one sampled class: a
    # declaration shape the converter still mishandles shows up somewhere in the
    # registry or nowhere. Walks all_tools rather than the registrar's
    # `tool_classes`, which memoizes @tool_classes on the class and would leave a
    # warm memo for other specs in the same process.
    let(:registry_tool_classes) do
      Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |class_name|
        class_name.constantize
      rescue NameError
        nil
      end
    end

    # Every array-typed property of every action of every registered tool, keyed
    # "Tool#action.param" so a failure names the declaration to fix.
    let(:array_properties) do
      registry_tool_classes.each_with_object({}) do |klass, acc|
        next unless klass.respond_to?(:action_definitions)

        klass.action_definitions.each do |action, defn|
          schema = Ai::Tools::ParameterSchema.build(defn[:parameters])
          (schema["properties"] || {}).each do |name, spec|
            next unless spec.is_a?(Hash) && spec["type"] == "array"

            acc["#{klass.name}##{action}.#{name}"] = spec
          end
        end
      end
    end

    it "gives EVERY array property of EVERY registered tool an items schema" do
      # Vacuity floor. The true count is 77 with extensions/system loaded; the
      # floor is deliberately well under that so a core-only load (no extension
      # engine) still exercises the walk rather than passing on an empty set.
      expect(array_properties.size).to be >= 40

      expect(array_properties.reject { |_k, v| v.key?("items") }).to eq({})
    end

    it "declares the pending-approval result shape in the advertised outputSchema" do
      out = described_class.send(:default_output_schema)
      data = out["properties"]["data"]

      expect(out["properties"]).to include("success", "error", "data")
      expect(data["properties"]).to include("pending", "deferred_operation_id", "approval_request_id")
      expect(data["properties"]["pending"]["type"]).to eq("boolean")
    end
  end

  # Finding from review: a declared shape with no oracle binding it to the
  # producer drifts silently — which is the defect class this task exists to
  # close. This runs the REAL :pending arm of BaseTool#run_through_autonomy_gate
  # and asserts key-set EQUALITY with the constant the outputSchema advertises,
  # so adding a key on either side reddens.
  describe "Ai::Tools::BaseTool::PENDING_RESULT_PROPERTIES" do
    let(:tool_class) do
      Class.new(Ai::Tools::BaseTool) do
        private

        def probe_gate_context(_params)
          { executor_params: {} }
        end

        def probe_on_proceed(_params, _gate)
          success_result(ran: true)
        end
      end
    end

    let(:declaration) do
      {
        action_category: "spec.pending_shape_probe",
        executor_class: "Ai::Tools::BaseTool",
        gate_context: :probe_gate_context,
        on_proceed: :probe_on_proceed
      }
    end

    it "names exactly the keys the gate's :pending arm puts in data" do
      allow(::Ai::AutonomyGate).to receive(:evaluate).and_return(
        ::Ai::AutonomyGate::Result.new(decision: :pending, deferred_operation: nil)
      )

      result = tool_class.new(account: nil).send(:run_through_autonomy_gate, declaration, {})

      expect(result[:success]).to be(true)
      expect(result[:data].keys.map(&:to_s).sort).to(
        eq(Ai::Tools::BaseTool::PENDING_RESULT_PROPERTIES.keys.map(&:to_s).sort),
        "The pending envelope BaseTool builds and the shape the MCP outputSchema " \
        "advertises have diverged. Update PENDING_RESULT_PROPERTIES (base_tool.rb) " \
        "alongside the :pending arm. NOTE the scope: a tool may add its own keys " \
        "on its own pending arm (SdwanTool splats **pending_extra); this pins the " \
        "BaseTool arm, which is the one the schema describes."
      )
    end
  end

  describe Api::V1::Mcp::StreamableHttpController do
    let(:controller) { described_class.new }

    it "carries enum and items onto the tools/list wire schema" do
      schema = controller.send(
        :build_input_schema,
        target: { type: "string", required: true, description: "t", enum: %w[live retired] },
        tags: { type: "array", description: "Tags" }
      )

      expect(schema["properties"]["target"]["enum"]).to eq(%w[live retired])
      expect(schema["properties"]["tags"]["items"]).to eq({ "type" => "string" })
    end

    it "carries enum through the already-JSON-Schema branch" do
      schema = controller.send(
        :build_input_schema,
        "type" => "object",
        "properties" => { "mode" => { "type" => "string", "enum" => %w[a b] } },
        "required" => ["mode"]
      )

      expect(schema["properties"]["mode"]["enum"]).to eq(%w[a b])
    end
  end
end

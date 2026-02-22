# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Workflows::TemplateService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, :active, :with_simple_chain, account: account, creator: user) }

  subject(:service) { described_class.new(account: account, user: user) }

  # ===========================================================================
  # #create_from_workflow
  # ===========================================================================

  describe "#create_from_workflow" do
    it "creates a template from a workflow" do
      # source_workflow_id is stored inside the metadata JSON column, not as a DB column
      result = service.create_from_workflow(workflow, name: "My Template", description: "Test")

      expect(result).to be_success
      expect(result.template).to be_persisted
      expect(result.template.name).to eq("My Template")
      expect(result.template.metadata["source_workflow_id"]).to eq(workflow.id)
    end

    it "returns failure when template name is blank" do
      result = service.create_from_workflow(workflow, name: "", description: "")

      expect(result).to be_failure
      expect(result.error).to be_present
    end
  end

  # ===========================================================================
  # #create_workflow_from_template
  # ===========================================================================

  describe "#create_workflow_from_template" do
    # The factory workflow_definition uses symbol keys, but the service accesses
    # with string keys. Build a template with string-keyed workflow_definition
    # and proper edge data for the service to work.
    let(:template) do
      create(:ai_workflow_template, account: account, created_by_user: user,
             workflow_definition: {
               "nodes" => [
                 { "node_id" => "start_1", "node_type" => "start", "name" => "Start",
                   "position" => { "x" => 100, "y" => 300 }, "configuration" => {} },
                 { "node_id" => "end_1", "node_type" => "end", "name" => "End",
                   "position" => { "x" => 400, "y" => 300 }, "configuration" => {} }
               ],
               "edges" => [
                 { "edge_id" => "edge_1", "source_node_id" => "start_1",
                   "target_node_id" => "end_1", "edge_type" => "default",
                   "priority" => 0 }
               ]
             })
    end

    it "creates a draft workflow from a template" do
      result = service.create_workflow_from_template(template)

      expect(result).to be_success
      expect(result.workflow).to be_persisted
      expect(result.workflow.status).to eq("draft")
      expect(result.workflow.account).to eq(account)
      expect(result.workflow.creator).to eq(user)
    end

    it "uses a custom name when provided" do
      result = service.create_workflow_from_template(template, name: "Custom Workflow")

      expect(result).to be_success
      expect(result.workflow.name).to eq("Custom Workflow")
    end

    it "defaults name to template name with 'Workflow' suffix" do
      result = service.create_workflow_from_template(template)

      expect(result).to be_success
      expect(result.workflow.name).to eq("#{template.name} Workflow")
    end

    it "records source template in metadata" do
      result = service.create_workflow_from_template(template)

      expect(result).to be_success
      expect(result.workflow.metadata["source_template_id"]).to eq(template.id)
    end

    it "creates nodes from template definition" do
      result = service.create_workflow_from_template(template)

      expect(result).to be_success
      expect(result.workflow.nodes.count).to eq(2)
    end

    it "creates edges from template definition" do
      result = service.create_workflow_from_template(template)

      expect(result).to be_success
      expect(result.workflow.edges.count).to eq(1)
    end

    it "returns failure for invalid template data" do
      bad_template = create(:ai_workflow_template, account: account, created_by_user: user,
                            workflow_definition: {
                              "nodes" => [
                                { "node_id" => "start_1", "node_type" => "start", "name" => "Start" }
                              ],
                              "edges" => [
                                { "source_node_id" => "start_1", "target_node_id" => "missing" }
                              ]
                            })

      result = service.create_workflow_from_template(bad_template)

      expect(result).to be_failure
    end
  end

  # ===========================================================================
  # #create_workflow_from_source
  # ===========================================================================

  describe "#create_workflow_from_source" do
    it "duplicates a workflow and returns the new copy" do
      result = service.create_workflow_from_source(workflow)

      expect(result).to be_success
      expect(result.workflow).to be_persisted
      expect(result.workflow.id).not_to eq(workflow.id)
    end

    it "overrides name when provided" do
      result = service.create_workflow_from_source(workflow, name: "My Copy")

      expect(result).to be_success
      expect(result.workflow.name).to eq("My Copy")
    end

    it "creates a draft copy" do
      result = service.create_workflow_from_source(workflow)

      expect(result).to be_success
      expect(result.workflow.status).to eq("draft")
    end
  end

  # ===========================================================================
  # #convert_to_template
  # ===========================================================================

  describe "#convert_to_template" do
    it "marks a workflow as a template with a category" do
      result = service.convert_to_template(workflow, category: "automation")

      expect(result).to be_success
      expect(workflow.reload.is_template).to be true
      expect(workflow.reload.template_category).to eq("automation")
    end

    it "records template creation metadata" do
      result = service.convert_to_template(workflow, category: "automation")

      expect(result).to be_success
      expect(workflow.reload.metadata["template_created_at"]).to be_present
      expect(workflow.reload.metadata["template_created_by"]).to eq(user.id)
    end

    it "fails without a template category (validation requires it)" do
      result = service.convert_to_template(workflow)

      expect(result).to be_failure
      expect(result.error).to include("Template category")
    end

    it "raises OwnershipError for workflows from another account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_workflow = create(:ai_workflow, account: other_account, creator: other_user)

      expect {
        service.convert_to_template(other_workflow)
      }.to raise_error(described_class::OwnershipError)
    end
  end

  # ===========================================================================
  # #publish_template
  # ===========================================================================

  describe "#publish_template" do
    let(:template) do
      create(:ai_workflow_template, account: account, created_by_user: user,
             is_public: false, published_at: nil)
    end

    it "publishes a valid template" do
      result = service.publish_template(template)

      expect(result).to be_success
      expect(template.reload.is_public).to be true
      expect(template.published_at).to be_present
    end

    it "bumps the version on publish" do
      original_version = template.version
      result = service.publish_template(template)

      expect(result).to be_success
      expect(template.reload.version).not_to eq(original_version)
    end

    it "fails for templates without workflow definition nodes" do
      template.update_columns(workflow_definition: { "nodes" => [], "edges" => [] })

      result = service.publish_template(template)

      expect(result).to be_failure
      expect(result.error).to include("node")
    end

    it "raises OwnershipError for templates from another account" do
      other_account = create(:account)
      other_template = create(:ai_workflow_template, account: other_account)

      expect {
        service.publish_template(other_template)
      }.to raise_error(described_class::OwnershipError)
    end
  end

  # ===========================================================================
  # #update_template_version
  # ===========================================================================

  describe "#update_template_version" do
    let(:template) do
      create(:ai_workflow_template, account: account, created_by_user: user, version: "1.0.0")
    end

    it "bumps patch version by default" do
      result = service.update_template_version(template, changes: { description: "Updated" })

      expect(result).to be_success
      expect(template.reload.version).to eq("1.0.1")
    end

    it "bumps minor version when specified" do
      result = service.update_template_version(template, changes: { description: "Updated" }, version_bump: "minor")

      expect(result).to be_success
      expect(template.reload.version).to eq("1.1.0")
    end

    it "bumps major version when specified" do
      result = service.update_template_version(template, changes: { description: "Updated" }, version_bump: "major")

      expect(result).to be_success
      expect(template.reload.version).to eq("2.0.0")
    end

    it "records version history in metadata" do
      service.update_template_version(template, changes: { description: "Updated" })

      history = template.reload.metadata["version_history"]
      expect(history).to be_an(Array)
      expect(history.last["version"]).to eq("1.0.0")
    end
  end

  # ===========================================================================
  # #import_template
  # ===========================================================================

  describe "#import_template" do
    let(:import_data) do
      {
        "name" => "Imported Template",
        "description" => "An imported template",
        "version" => "2.0.0",
        "category" => "automation",
        "difficulty_level" => "intermediate",
        "tags" => %w[ai imported],
        "license" => "MIT",
        "workflow_definition" => {
          "nodes" => [
            { "node_id" => "start", "node_type" => "start", "name" => "Start" },
            { "node_id" => "end", "node_type" => "end", "name" => "End" }
          ],
          "edges" => [
            { "source_node_id" => "start", "target_node_id" => "end" }
          ]
        }
      }
    end

    it "creates a template from import data" do
      result = service.import_template(import_data)

      expect(result).to be_success
      expect(result.template).to be_persisted
      expect(result.template.name).to eq("Imported Template")
      expect(result.template.version).to eq("2.0.0")
      expect(result.template.category).to eq("automation")
    end

    it "sets template as private by default" do
      result = service.import_template(import_data)

      expect(result).to be_success
      expect(result.template.is_public).to be false
    end

    it "records import metadata" do
      result = service.import_template(import_data)

      expect(result).to be_success
      expect(result.template.metadata["imported_at"]).to be_present
    end

    it "uses defaults when optional fields are missing" do
      minimal_data = {
        "name" => "Minimal Template",
        "description" => "Minimal",
        "workflow_definition" => {
          "nodes" => [
            { "node_id" => "start", "node_type" => "start", "name" => "Start" },
            { "node_id" => "end", "node_type" => "end", "name" => "End" }
          ],
          "edges" => [
            { "source_node_id" => "start", "target_node_id" => "end" }
          ]
        }
      }

      result = service.import_template(minimal_data)

      expect(result).to be_success
      expect(result.template.version).to eq("1.0.0")
      expect(result.template.category).to eq("imported")
      expect(result.template.difficulty_level).to eq("intermediate")
    end
  end
end

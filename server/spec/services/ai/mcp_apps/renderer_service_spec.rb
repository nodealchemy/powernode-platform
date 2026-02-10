# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::McpApps::RendererService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe "#list_apps" do
    before do
      create(:ai_mcp_app, :draft, account: account, name: "App A")
      create(:ai_mcp_app, :published, account: account, name: "App B")
      create(:ai_mcp_app, :archived, account: account, name: "App C")
    end

    it "returns all apps for the account" do
      apps = service.list_apps
      expect(apps.count).to eq(3)
    end

    it "filters by status" do
      apps = service.list_apps(status: "published")
      expect(apps.count).to eq(1)
      expect(apps.first.name).to eq("App B")
    end

    it "filters by app_type" do
      create(:ai_mcp_app, :template, account: account, name: "Template App")
      apps = service.list_apps(app_type: "template")
      expect(apps.count).to eq(1)
      expect(apps.first.name).to eq("Template App")
    end

    it "filters by search term" do
      apps = service.list_apps(search: "App A")
      expect(apps.count).to eq(1)
      expect(apps.first.name).to eq("App A")
    end

    it "does not return apps from other accounts" do
      other_account = create(:account)
      create(:ai_mcp_app, account: other_account, name: "Other App")

      apps = service.list_apps
      expect(apps.count).to eq(3)
    end
  end

  describe "#get_app" do
    it "returns the app by id" do
      app = create(:ai_mcp_app, account: account)
      found = service.get_app(app.id)
      expect(found.id).to eq(app.id)
    end

    it "raises RecordNotFound for unknown id" do
      expect { service.get_app(SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "scopes by account" do
      other_account = create(:account)
      other_app = create(:ai_mcp_app, account: other_account)
      expect { service.get_app(other_app.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#create_app" do
    it "creates a new MCP app" do
      app = service.create_app(
        name: "New App",
        description: "Test app",
        html_content: "<div>Content</div>"
      )

      expect(app).to be_persisted
      expect(app.name).to eq("New App")
      expect(app.account).to eq(account)
      expect(app.status).to eq("draft")
      expect(app.app_type).to eq("custom")
    end

    it "sanitizes HTML content" do
      app = service.create_app(
        name: "Sanitized App",
        html_content: '<div>Safe</div><script>alert("xss")</script>'
      )

      expect(app.html_content).to include("Safe")
      expect(app.html_content).not_to include("<script>")
    end

    it "raises on invalid params" do
      expect {
        service.create_app(name: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#update_app" do
    let!(:app) { create(:ai_mcp_app, account: account) }

    it "updates app attributes" do
      updated = service.update_app(app.id, name: "Updated Name")
      expect(updated.name).to eq("Updated Name")
    end

    it "sanitizes HTML on update" do
      updated = service.update_app(app.id, html_content: '<p>Safe</p><script>bad()</script>')
      expect(updated.html_content).not_to include("<script>")
    end

    it "raises RecordNotFound for unknown id" do
      expect { service.update_app(SecureRandom.uuid, name: "X") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#delete_app" do
    it "destroys the app" do
      app = create(:ai_mcp_app, account: account)
      service.delete_app(app.id)
      expect { Ai::McpApp.find(app.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#render_app" do
    let(:app) { create(:ai_mcp_app, account: account, html_content: "<div>Hello {{name}}</div>") }

    it "returns rendered HTML with context variables interpolated" do
      result = service.render_app(mcp_app: app, context: { "name" => "World" })

      expect(result[:html]).to include("Hello World")
    end

    it "creates an MCP app instance" do
      result = service.render_app(mcp_app: app, context: {})

      expect(result[:instance]).to be_persisted
      expect(result[:instance].mcp_app).to eq(app)
      expect(result[:instance].status).to eq("running")
    end

    it "returns CSP headers" do
      result = service.render_app(mcp_app: app, context: {})

      expect(result[:csp_headers]).to be_present
      expect(result[:csp_headers]).to include("default-src")
    end

    it "returns sandbox attributes" do
      result = service.render_app(mcp_app: app, context: {})

      expect(result[:sandbox_attrs]).to be_present
    end

    it "associates session when provided" do
      session = create(:ai_agui_session, account: account)
      result = service.render_app(mcp_app: app, context: {}, session: session)

      expect(result[:instance].session).to eq(session)
    end

    it "sanitizes interpolated values to prevent XSS" do
      result = service.render_app(
        mcp_app: app,
        context: { "name" => '<script>alert("xss")</script>' }
      )

      expect(result[:html]).not_to include("<script>")
    end
  end

  describe "#process_user_input" do
    let(:app) { create(:ai_mcp_app, :with_schema, account: account) }
    let(:instance) { create(:ai_mcp_app_instance, mcp_app: app, account: account) }

    it "processes valid input and completes the instance" do
      result = service.process_user_input(
        instance_id: instance.id,
        input_data: { "name" => "Test" }
      )

      expect(result[:response][:received]).to be true
      expect(result[:state_update]).to be_present
      expect(instance.reload.status).to eq("completed")
    end

    it "returns validation error for missing required fields" do
      result = service.process_user_input(
        instance_id: instance.id,
        input_data: {}
      )

      expect(result[:response][:error]).to eq("Invalid input")
      expect(result[:response][:details]).to include("Missing required field: name")
    end

    it "raises RecordNotFound for unknown instance" do
      expect {
        service.process_user_input(instance_id: SecureRandom.uuid, input_data: {})
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "HTML sanitization" do
    it "removes script tags" do
      app = service.create_app(
        name: "Script Test",
        html_content: '<div>OK</div><script>alert(1)</script>'
      )
      expect(app.html_content).not_to include("<script>")
    end

    it "removes iframe tags" do
      app = service.create_app(
        name: "Iframe Test",
        html_content: '<div>OK</div><iframe src="evil.html"></iframe>'
      )
      expect(app.html_content).not_to include("<iframe")
    end

    it "removes on* event handlers" do
      app = service.create_app(
        name: "Handler Test",
        html_content: '<div onclick="alert(1)">Click</div>'
      )
      expect(app.html_content).not_to include("onclick")
    end

    it "removes object and embed tags" do
      app = service.create_app(
        name: "Object Test",
        html_content: '<object data="evil.swf"></object><embed src="bad.swf"/>'
      )
      expect(app.html_content).not_to include("<object")
      expect(app.html_content).not_to include("<embed")
    end
  end

  describe "CSP header building" do
    it "uses default CSP when no custom policy" do
      app = create(:ai_mcp_app, account: account, csp_policy: {})
      result = service.render_app(mcp_app: app, context: {})

      expect(result[:csp_headers]).to include("default-src 'self'")
      expect(result[:csp_headers]).to include("script-src 'none'")
    end

    it "merges custom CSP policy with defaults" do
      app = create(:ai_mcp_app, :with_csp, account: account)
      result = service.render_app(mcp_app: app, context: {})

      expect(result[:csp_headers]).to include("script-src 'self'")
    end
  end
end

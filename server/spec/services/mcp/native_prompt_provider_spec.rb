# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::NativePromptProvider, type: :model do
  let(:account) { create(:account) }
  let(:provider) { described_class.new(account: account) }

  # ===========================================================================
  # #list_prompts
  # ===========================================================================
  describe "#list_prompts" do
    it "returns empty when no templates exist" do
      result = provider.list_prompts
      expect(result[:prompts]).to be_an(Array)
      expect(result[:prompts]).to be_empty
    end

    context "with active templates" do
      let!(:template) do
        create(:shared_prompt_template,
               account: account,
               slug: "test-prompt",
               name: "Test Prompt",
               description: "A test prompt",
               content: "Hello {{ name }}",
               variables: [
                 { "name" => "name", "type" => "string", "required" => true, "description" => "The name" }
               ])
      end

      it "returns active templates for account" do
        result = provider.list_prompts
        expect(result[:prompts].length).to eq(1)
      end

      it "includes name (slug), description, arguments" do
        result = provider.list_prompts
        prompt = result[:prompts].first

        expect(prompt[:name]).to eq("test-prompt")
        expect(prompt[:description]).to eq("A test prompt")
        expect(prompt[:arguments]).to be_an(Array)
      end

      it "maps arguments from variable_definitions" do
        result = provider.list_prompts
        prompt = result[:prompts].first
        arg = prompt[:arguments].first

        expect(arg[:name]).to eq("name")
        expect(arg[:description]).to eq("The name")
        expect(arg[:required]).to be true
      end
    end

    it "only returns active and latest_versions" do
      create(:shared_prompt_template, account: account, is_active: true)
      inactive = create(:shared_prompt_template, :inactive, account: account)

      result = provider.list_prompts
      slugs = result[:prompts].map { |p| p[:name] }
      expect(slugs).not_to include(inactive.slug)
    end

    it "excludes inactive templates" do
      create(:shared_prompt_template, :inactive, account: account, slug: "inactive-prompt")

      result = provider.list_prompts
      expect(result[:prompts]).to be_empty
    end

    it "supports cursor pagination" do
      result = provider.list_prompts(cursor: "0")
      expect(result).to include(:prompts, :nextCursor)
    end

    it "returns nextCursor as nil when fewer than page size results" do
      create(:shared_prompt_template, account: account)
      result = provider.list_prompts
      expect(result[:nextCursor]).to be_nil
    end
  end

  # ===========================================================================
  # #get_prompt
  # ===========================================================================
  describe "#get_prompt" do
    let!(:template) do
      create(:shared_prompt_template,
             account: account,
             slug: "greeting",
             name: "Greeting Prompt",
             description: "A greeting prompt",
             content: "Hello {{ name }}, welcome to {{ place }}!",
             variables: [
               { "name" => "name", "type" => "string", "required" => true, "description" => "The name" },
               { "name" => "place", "type" => "string", "required" => false, "default" => "Powernode", "description" => "The place" }
             ])
    end

    # Stub PromptTemplate#render since Liquid gem may not be loaded in test env
    before do
      allow_any_instance_of(Shared::PromptTemplate).to receive(:render) do |tmpl, variables|
        content = tmpl.content.dup
        variables.each { |k, v| content.gsub!("{{ #{k} }}", v.to_s) }
        # Apply defaults for unsubstituted variables
        tmpl.variable_definitions.each do |var_def|
          placeholder = "{{ #{var_def[:name]} }}"
          if content.include?(placeholder) && var_def[:default].present?
            content.gsub!(placeholder, var_def[:default].to_s)
          end
        end
        content
      end
    end

    it "renders template with provided arguments" do
      result = provider.get_prompt(name: "greeting", arguments: { "name" => "World", "place" => "Earth" })
      text = result[:messages].first[:content][:text]
      expect(text).to eq("Hello World, welcome to Earth!")
    end

    it "returns description and messages array" do
      result = provider.get_prompt(name: "greeting", arguments: { "name" => "World" })
      expect(result[:description]).to eq("A greeting prompt")
      expect(result[:messages]).to be_an(Array)
      expect(result[:messages]).not_to be_empty
    end

    it "message has role 'user' and content with type 'text'" do
      result = provider.get_prompt(name: "greeting", arguments: { "name" => "World" })
      message = result[:messages].first

      expect(message[:role]).to eq("user")
      expect(message[:content][:type]).to eq("text")
      expect(message[:content][:text]).to be_a(String)
    end

    it "raises ArgumentError for missing required variables" do
      expect {
        provider.get_prompt(name: "greeting", arguments: {})
      }.to raise_error(ArgumentError, /Missing required variable: name/)
    end

    it "raises ArgumentError for non-existent prompt name" do
      expect {
        provider.get_prompt(name: "does-not-exist", arguments: {})
      }.to raise_error(ArgumentError, /Prompt not found/)
    end

    it "works with template that has no variables" do
      create(:shared_prompt_template,
             account: account,
             slug: "static-prompt",
             name: "Static Prompt",
             description: "No variables",
             content: "This is a static prompt with no variables.",
             variables: [])

      result = provider.get_prompt(name: "static-prompt", arguments: {})
      expect(result[:messages].first[:content][:text]).to eq("This is a static prompt with no variables.")
    end

    it "applies default values for optional variables" do
      result = provider.get_prompt(name: "greeting", arguments: { "name" => "World" })
      text = result[:messages].first[:content][:text]
      expect(text).to eq("Hello World, welcome to Powernode!")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tool action_definitions coverage", type: :service do
  describe "every TOOLS registry entry has a matching action_definitions entry" do
    Ai::Tools::PlatformApiToolRegistry::TOOLS.each do |tool_name, class_name|
      context "#{tool_name} (#{class_name})" do
        let(:klass) { class_name.constantize }
        let(:action_defs) { klass.action_definitions }

        it "has a matching action_definitions key" do
          expect(action_defs).to have_key(tool_name),
            "#{class_name}.action_definitions is missing key '#{tool_name}'. " \
            "Available keys: #{action_defs.keys.join(', ')}"
        end

        it "has a description longer than 10 characters" do
          next unless action_defs.key?(tool_name)

          desc = action_defs[tool_name][:description]
          expect(desc).to be_a(String)
          expect(desc.length).to be > 10,
            "#{tool_name} description is too short (#{desc.length} chars): '#{desc}'"
        end

        it "does not include an :action parameter" do
          next unless action_defs.key?(tool_name)

          params = action_defs[tool_name][:parameters] || {}
          expect(params).not_to have_key(:action),
            "#{tool_name} action_definitions should not include :action parameter"
        end

        it "marks required parameters correctly" do
          next unless action_defs.key?(tool_name)

          params = action_defs[tool_name][:parameters] || {}
          params.each do |param_name, param_def|
            expect(param_def).to have_key(:type),
              "#{tool_name}.#{param_name} is missing :type"
            expect(param_def).to have_key(:description),
              "#{tool_name}.#{param_name} is missing :description"
            expect([true, false, nil]).to include(param_def[:required]),
              "#{tool_name}.#{param_name} :required must be true, false, or nil"
          end
        end
      end
    end
  end

  describe "action_definitions structure" do
    it "covers all unique tool classes" do
      unique_classes = Ai::Tools::PlatformApiToolRegistry::TOOLS.values.uniq
      unique_classes.each do |class_name|
        klass = class_name.constantize
        expect(klass).to respond_to(:action_definitions),
          "#{class_name} does not implement action_definitions"
      end
    end

    it "produces no duplicate tool names across all classes" do
      all_keys = []
      Ai::Tools::PlatformApiToolRegistry::TOOLS.values.uniq.each do |class_name|
        klass = class_name.constantize
        all_keys.concat(klass.action_definitions.keys)
      end

      duplicates = all_keys.group_by(&:itself).select { |_, v| v.size > 1 }.keys
      expect(duplicates).to be_empty,
        "Duplicate action_definitions keys found: #{duplicates.join(', ')}"
    end
  end
end

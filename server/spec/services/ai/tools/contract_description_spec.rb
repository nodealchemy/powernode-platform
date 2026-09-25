# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::ContractDescription do
  def tool_class(description, parent: Ai::Tools::BaseTool, &declarations)
    Class.new(parent) do
      define_singleton_method(:definition) { { name: "spec_action", description: description, parameters: {} } }
      class_eval(&declarations) if declarations
    end
  end

  def described(klass) = klass.action_definitions.fetch("spec_action")[:description]

  it "appends the declared contract after the hand-written text" do
    klass = tool_class("List widgets") do
      declare_action "spec_action", mutating: false, limit: 50, returns: "id and name per widget",
                                    refuses: [ "the account has no widgets module" ],
                                    see_also: { "get_widget" => "one widget's full record" }
    end

    expect(described(klass)).to eq(
      "List widgets. Returns at most 50 rows; not paginated. Returns id and name per widget. " \
      "Refuses when the account has no widgets module. For one widget's full record, use get_widget."
    )
  end

  it "states pagination instead of a cap when the action is paginated" do
    klass = tool_class("List widgets.") { declare_action "spec_action", mutating: false, paginated: true, limit: 50 }

    expect(described(klass)).to eq("List widgets. #{described_class::PAGINATED}")
  end

  it "marks a destructive action unless the text already says so" do
    plain = tool_class("Delete a widget.") { declare_action "spec_action", mutating: true, destructive: true }
    said = tool_class("Delete a widget permanently.") { declare_action "spec_action", mutating: true, destructive: true }

    expect(described(plain)).to eq("Delete a widget. #{described_class::DESTRUCTIVE}")
    expect(described(said)).to eq("Delete a widget permanently.")
  end

  it "leaves an undeclared or metadata-free action's text untouched" do
    expect(described(tool_class("Do a thing"))).to eq("Do a thing")
    expect(described(tool_class("Do a thing") { declare_action "spec_action", mutating: false })).to eq("Do a thing")
  end

  it "composes once for a subclass that inherits its parent's definitions" do
    parent = tool_class("Delete a widget.") { declare_action "spec_action", mutating: true, destructive: true }
    child = Class.new(parent)

    expect(described(child)).to eq("Delete a widget. #{described_class::DESTRUCTIVE}")
  end
end

# frozen_string_literal: true

require "rails_helper"

# IMP-f6f80b585b19 — a scoped finder's ActiveRecord::RecordNotFound carries
# ` [WHERE "table"."column" = $1]` in its message on Rails 8.1. A tool that
# rescues it and forwards e.message hands that table/column text to the model
# provider. Each example makes the tool's own action raise a REAL scoped-finder
# RecordNotFound (never a hand-built message) and asserts the returned error
# carries neither the WHERE clause nor the table name.
RSpec.describe "tool RecordNotFound rescue arms" do
  let(:account) { create(:account) }
  let(:tool_user) do
    create(:user, account: account, permissions: %w[devops.docker.read devops.docker.manage])
  end

  def raise_scoped_not_found
    account.ai_agents.find("no-such-agent")
  end

  it "premise: a scoped find puts the WHERE clause in the exception message" do
    expect { raise_scoped_not_found }
      .to raise_error(ActiveRecord::RecordNotFound, /WHERE/)
  end

  {
    "CodeAnalysisTool" => [ Ai::Tools::CodeAnalysisTool, :blast_radius, { action: "blast_radius", repository_id: "r" } ],
    "DockerHostTool" => [ Ai::Tools::DockerHostTool, :get_host, { action: "docker_get_host" } ]
  }.each do |label, (klass, seam, params)|
    it "#{label} answers a missing record without the SQL WHERE text" do
      tool = klass.new(account: account, user: tool_user)
      allow(tool).to receive(seam) { raise_scoped_not_found }

      result = tool.execute(params: params)

      expect(result[:success]).to be false
      expect(result[:error]).to include("Couldn't find")
      expect(result[:error]).not_to include("WHERE")
      expect(result[:error]).not_to include("ai_agents")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# The Budgets page (/app/ai/control/budgets) reads and writes through
# /api/v1/ai/autonomy/budgets. Every id those actions accept — the budget in the
# path, the agent in the body, and so the parent a child is allocated from —
# must resolve within the caller's account. The associations carry no account
# check of their own (the class of gap fc-30 closed on intervention policies),
# so these examples pin the lookups the controller does, door by door.
RSpec.describe "Autonomy budget endpoints stay within the caller's account", type: :request do
  let(:account)       { create(:account) }
  let(:other_account) { create(:account) }
  let(:reader)        { user_with_permissions("ai.agents.read", account: account) }
  let(:manager)       { user_with_permissions("ai.agents.read", "ai.autonomy.manage", account: account) }

  let(:own_agent)      { create(:ai_agent, account: account) }
  let(:foreign_agent)  { create(:ai_agent, account: other_account) }
  let!(:own_budget)    { create(:ai_agent_budget, account: account, agent: own_agent, total_budget_cents: 10_000) }
  let!(:foreign_budget) do
    create(:ai_agent_budget, account: other_account, agent: foreign_agent, total_budget_cents: 10_000)
  end

  def headers(user = manager)
    auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  it "lists only the caller's budgets" do
    get "/api/v1/ai/autonomy/budgets", headers: headers(reader)

    expect(response).to have_http_status(:ok)
    expect(json_response_data.map { |b| b["id"] }).to eq([ own_budget.id ])
  end

  it "refuses creating a budget for another account's agent" do
    post "/api/v1/ai/autonomy/budgets", params: { agent_id: foreign_agent.id, total_budget_cents: 500 }.to_json,
                                        headers: headers

    expect(response).to have_http_status(:not_found)
    expect(Ai::AgentBudget.where(agent_id: foreign_agent.id).count).to eq(1)
  end

  it "refuses allocating a child from another account's budget, or to another account's agent" do
    post "/api/v1/ai/autonomy/budgets/#{foreign_budget.id}/allocate_child",
         params: { agent_id: own_agent.id, amount_cents: 100 }.to_json, headers: headers
    expect(response).to have_http_status(:not_found)

    post "/api/v1/ai/autonomy/budgets/#{own_budget.id}/allocate_child",
         params: { agent_id: foreign_agent.id, amount_cents: 100 }.to_json, headers: headers
    expect(response).to have_http_status(:not_found)

    expect(Ai::AgentBudget.where.not(parent_budget_id: nil)).to be_empty
    expect([ own_budget.reload.reserved_cents, foreign_budget.reload.reserved_cents ]).to eq([ 0, 0 ])
  end

  it "refuses reading, editing or deleting another account's budget" do
    get "/api/v1/ai/autonomy/budgets/#{foreign_budget.id}/transactions", headers: headers
    expect(response).to have_http_status(:not_found)

    put "/api/v1/ai/autonomy/budgets/#{foreign_budget.id}", params: { total_budget_cents: 1 }.to_json, headers: headers
    expect(response).to have_http_status(:not_found)

    delete "/api/v1/ai/autonomy/budgets/#{foreign_budget.id}", headers: headers
    expect(response).to have_http_status(:not_found)

    expect(foreign_budget.reload.total_budget_cents).to eq(10_000)
  end

  # Positive control: the same calls within the account succeed, and allocation
  # reserves the child's amount on the parent.
  it "allocates a child from the caller's own budget to the caller's own agent" do
    child_agent = create(:ai_agent, account: account)

    post "/api/v1/ai/autonomy/budgets/#{own_budget.id}/allocate_child",
         params: { agent_id: child_agent.id, amount_cents: 2_500 }.to_json, headers: headers

    expect(response).to have_http_status(:created)
    expect(json_response_data).to include("parent_budget_id" => own_budget.id, "agent_id" => child_agent.id,
                                          "total_budget_cents" => 2_500)
    expect(own_budget.reload.reserved_cents).to eq(2_500)
  end

  it "refuses allocating more than the parent has remaining, leaving reservations untouched" do
    child_agent = create(:ai_agent, account: account)
    own_budget.update_columns(spent_cents: 8_000)

    post "/api/v1/ai/autonomy/budgets/#{own_budget.id}/allocate_child",
         params: { agent_id: child_agent.id, amount_cents: 2_001 }.to_json, headers: headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_response["error"]).to eq("Insufficient budget remaining")
    expect(own_budget.reload.reserved_cents).to eq(0)
    expect(own_budget.child_budgets).to be_empty
  end

  it "refuses allocating a zero or negative amount" do
    child_agent = create(:ai_agent, account: account)

    [ 0, -100 ].each do |amount|
      post "/api/v1/ai/autonomy/budgets/#{own_budget.id}/allocate_child",
           params: { agent_id: child_agent.id, amount_cents: amount }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content), "amount_cents #{amount}"
    end
    expect(own_budget.reload.reserved_cents).to eq(0)
    expect(own_budget.child_budgets).to be_empty
  end

  it "keeps the writes behind ai.autonomy.manage" do
    post "/api/v1/ai/autonomy/budgets/#{own_budget.id}/allocate_child",
         params: { agent_id: own_agent.id, amount_cents: 100 }.to_json, headers: headers(reader)

    expect(response).to have_http_status(:forbidden)
  end
end

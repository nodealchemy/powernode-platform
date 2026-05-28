# frozen_string_literal: true

class DailySummaryService
  def initialize(account:, date: Date.yesterday)
    @account = account
    @date = date
    @range = date.beginning_of_day..date.end_of_day
  end

  # Generate a markdown summary and persist it as a Page
  def generate!
    slug = "daily-summary-#{@date.iso8601}"

    # Avoid duplicates
    existing = Page.find_by(account: @account, slug: slug)
    return existing if existing

    markdown = build_markdown

    Page.create!(
      account: @account,
      author: system_user,
      title: "Daily Summary — #{@date.strftime('%B %d, %Y')}",
      slug: slug,
      content: markdown,
      status: "published",
      published_at: Time.current,
      meta_description: "Automated operational summary for #{@date.strftime('%B %d, %Y')}",
      meta_keywords: "daily-summary,auto-generated,#{@date.iso8601}"
    )
  end

  private

  def build_markdown
    sections = [
      header_section,
      agent_execution_section,
      knowledge_section,
      graph_section
    ].compact

    sections.join("\n\n---\n\n")
  end

  def header_section
    <<~MD.strip
      # Daily Summary — #{@date.strftime('%A, %B %d, %Y')}

      Auto-generated operational summary for **#{@account.name}**.
    MD
  end

  def agent_execution_section
    executions = Ai::AgentExecution.where(account: @account, created_at: @range)
    total = executions.count
    return nil if total.zero?

    completed = executions.completed.count
    failed = executions.failed.count
    avg_duration = executions.completed.average(:duration_ms)&.round(0) || 0
    total_cost = executions.sum(:cost_usd).round(4)
    total_tokens = executions.sum(:tokens_used)

    <<~MD.strip
      ## AI Agent Executions

      | Metric | Value |
      |--------|-------|
      | Total runs | #{total} |
      | Completed | #{completed} |
      | Failed | #{failed} |
      | Avg duration | #{avg_duration}ms |
      | Total tokens | #{total_tokens.to_fs(:delimited)} |
      | Total cost | $#{total_cost} |
    MD
  end

  def knowledge_section
    new_learnings = Ai::CompoundLearning.where(account: @account, created_at: @range).count
    new_knowledge = Ai::SharedKnowledge.where(account_id: @account.id, created_at: @range).count
    return nil if new_learnings.zero? && new_knowledge.zero?

    verified = Ai::CompoundLearning.where(account: @account, status: "verified", updated_at: @range).count
    deprecated = Ai::CompoundLearning.where(account: @account, status: "deprecated", updated_at: @range).count

    <<~MD.strip
      ## Knowledge Growth

      | Metric | Value |
      |--------|-------|
      | New learnings | #{new_learnings} |
      | Verified | #{verified} |
      | Deprecated | #{deprecated} |
      | New shared knowledge | #{new_knowledge} |
    MD
  end

  def graph_section
    new_nodes = Ai::KnowledgeGraphNode.where(account: @account, created_at: @range).count
    new_edges = Ai::KnowledgeGraphEdge.where(account: @account, created_at: @range).count
    return nil if new_nodes.zero? && new_edges.zero?

    total_nodes = Ai::KnowledgeGraphNode.where(account: @account).active.count
    total_edges = Ai::KnowledgeGraphEdge.where(account: @account).count

    <<~MD.strip
      ## Knowledge Graph

      | Metric | Value |
      |--------|-------|
      | New nodes (today) | #{new_nodes} |
      | New edges (today) | #{new_edges} |
      | Total active nodes | #{total_nodes.to_fs(:delimited)} |
      | Total edges | #{total_edges.to_fs(:delimited)} |
    MD
  end

  def system_user
    @account.users.joins(:roles).where(roles: { name: "admin" }).first || @account.users.first
  end
end

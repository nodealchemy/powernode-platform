# frozen_string_literal: true

module Ai
  class KnowledgeDocSyncService
    OUTPUT_DIR = Rails.root.join("..", "docs", "platform", "knowledge")

    # Size caps to prevent oversized files
    MAX_LEARNINGS = 100
    MAX_KNOWLEDGE = 100
    MAX_SKILLS = 50
    MAX_GRAPH_NODES = 75
    MAX_GRAPH_EDGES = 150
    MAX_TODOS = 100

    # Quality gates
    LEARNING_MIN_IMPORTANCE = 0.5
    LEARNING_MIN_CONFIDENCE = 0.7
    KNOWLEDGE_MIN_QUALITY = 0.5
    GRAPH_NODE_MIN_CONFIDENCE = 0.3

    CONTENT_TRUNCATE_LENGTH = 500

    # Tags that indicate test/synthetic data — excluded from export
    EXCLUDED_TAG_PREFIXES = %w[smoke_test_].freeze

    # Generic failure titles that carry no actionable insight
    GENERIC_FAILURE_TITLES = /\A(General failure|Timeout failure|Unknown error)\z/i

    def initialize(account:)
      @account = account
    end

    def sync_all!
      timestamp = Time.current.strftime("%Y-%m-%d %H:%M UTC")
      FileUtils.mkdir_p(OUTPUT_DIR)

      results = {
        learnings: sync_learnings(timestamp),
        knowledge: sync_knowledge(timestamp),
        skills: sync_skills(timestamp),
        graph: sync_graph(timestamp),
        todos: sync_todos(timestamp)
      }

      results[:success] = results.values.all? { |r| r[:success] }
      results[:synced_at] = timestamp
      results
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def sync_learnings(timestamp)
      entries = CompoundLearning
        .for_account(@account.id)
        .where(status: %w[active verified])
        .where("importance_score >= ? OR confidence_score >= ?", LEARNING_MIN_IMPORTANCE, LEARNING_MIN_CONFIDENCE)
        .where("title IS NOT NULL AND title != ''")
        .order(importance_score: :desc, confidence_score: :desc)
        .limit(MAX_LEARNINGS * 2) # over-fetch to allow post-query filtering

      entries = filter_learnings(entries)

      lines = doc_header("Learnings & Patterns", timestamp,
        "Source: `ai_compound_learnings` | Filter: status IN (active, verified), importance >= #{LEARNING_MIN_IMPORTANCE} OR confidence >= #{LEARNING_MIN_CONFIDENCE}, non-blank title, deduplicated")
      lines << "**#{entries.size} entries** exported (max #{MAX_LEARNINGS})"
      lines << ""

      grouped = entries.group_by(&:category)
      CompoundLearning::CATEGORIES.each do |category|
        items = grouped[category]
        next if items.blank?

        lines << "## #{category.titleize} (#{items.size})"
        lines << ""

        items.each do |learning|
          badge = learning.status == "verified" ? " [VERIFIED]" : ""
          lines << "### #{learning.title}#{badge}"
          lines << ""
          lines << truncate_content(sanitize_content(learning.content))
          lines << ""
          lines << "- **Importance**: #{format_score(learning.importance_score)} | **Confidence**: #{format_score(learning.confidence_score)} | **Effectiveness**: #{format_score(learning.effectiveness_score)}"
          lines << "- **Scope**: #{learning.scope} | **Access count**: #{learning.access_count} | **Injections**: #{learning.injection_count}"
          lines << "- **Tags**: #{learning.tags&.join(', ').presence || 'none'}"
          lines << ""
        end
      end

      write_file("LEARNINGS.md", lines)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Learnings sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    def sync_knowledge(timestamp)
      entries = SharedKnowledge
        .where(account: @account)
        .where("quality_score >= ? OR quality_score IS NULL", KNOWLEDGE_MIN_QUALITY)
        .order(quality_score: :desc, usage_count: :desc)
        .limit(MAX_KNOWLEDGE)

      lines = doc_header("Shared Knowledge", timestamp,
        "Source: `ai_shared_knowledges` | Filter: quality_score >= #{KNOWLEDGE_MIN_QUALITY}")
      lines << "**#{entries.size} entries** exported (max #{MAX_KNOWLEDGE})"
      lines << ""

      grouped = entries.group_by(&:content_type)
      SharedKnowledge::CONTENT_TYPES.each do |content_type|
        items = grouped[content_type]
        next if items.blank?

        lines << "## #{content_type.titleize} (#{items.size})"
        lines << ""

        items.each do |entry|
          lines << "### #{entry.title}"
          lines << ""
          lines << truncate_content(entry.content)
          lines << ""
          lines << "- **Quality**: #{format_score(entry.quality_score)} | **Usage**: #{entry.usage_count} | **Access level**: #{entry.access_level}"
          lines << "- **Source**: #{entry.source_type} | **Tags**: #{entry.tags&.join(', ').presence || 'none'}"
          lines << ""
        end
      end

      write_file("KNOWLEDGE.md", lines)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Knowledge sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    def sync_skills(timestamp)
      entries = Skill
        .for_account(@account.id)
        .where(status: "active", is_enabled: true)
        .order(usage_count: :desc, effectiveness_score: :desc)
        .limit(MAX_SKILLS)

      lines = doc_header("Skills Registry", timestamp,
        "Source: `ai_skills` | Filter: status = active, enabled = true")
      lines << "**#{entries.size} skills** exported (max #{MAX_SKILLS})"
      lines << ""

      # Summary table
      lines << "## Overview"
      lines << ""
      lines << "| Skill | Category | Usage | Effectiveness | System |"
      lines << "|-------|----------|-------|---------------|--------|"
      entries.each do |skill|
        sys = skill.is_system ? "Yes" : "No"
        lines << "| #{skill.name} | #{skill.category} | #{skill.usage_count} | #{format_score(skill.effectiveness_score)} | #{sys} |"
      end
      lines << ""

      # Grouped details
      grouped = entries.group_by(&:category)
      Skill::CATEGORIES.each do |category|
        items = grouped[category]
        next if items.blank?

        lines << "## #{category.titleize} (#{items.size})"
        lines << ""

        items.each do |skill|
          lines << "### #{skill.name}"
          lines << ""
          lines << truncate_content(skill.description)
          lines << ""
          lines << "- **Version**: #{skill.version} | **Usage**: #{skill.usage_count} (#{format_score(skill.usage_success_rate)} success rate)"
          lines << "- **Effectiveness**: #{format_score(skill.effectiveness_score)} | **Tags**: #{skill.tags&.join(', ').presence || 'none'}"
          lines << ""
        end
      end

      write_file("SKILLS.md", lines)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Skills sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    def sync_graph(timestamp)
      graph_service = KnowledgeGraph::GraphService.new(@account)
      stats = graph_service.statistics

      top_nodes = KnowledgeGraphNode
        .where(account: @account, status: "active")
        .where("confidence >= ?", GRAPH_NODE_MIN_CONFIDENCE)
        .order(mention_count: :desc, confidence: :desc)
        .limit(MAX_GRAPH_NODES)

      edges = KnowledgeGraphEdge
        .where(status: "active")
        .where(source_node_id: top_nodes.select(:id))
        .or(KnowledgeGraphEdge.where(status: "active").where(target_node_id: top_nodes.select(:id)))
        .limit(MAX_GRAPH_EDGES)

      lines = doc_header("Knowledge Graph", timestamp,
        "Source: `ai_knowledge_graph_nodes` + `ai_knowledge_graph_edges` | Filter: active nodes with confidence >= #{GRAPH_NODE_MIN_CONFIDENCE}")

      # Statistics
      lines << "## Graph Statistics"
      lines << ""
      lines << "| Metric | Value |"
      lines << "|--------|-------|"
      lines << "| Nodes | #{stats[:node_count]} |"
      lines << "| Edges | #{stats[:edge_count]} |"
      lines << "| Density | #{format_score(stats[:density])} |"
      lines << "| Avg Confidence | #{format_score(stats[:avg_confidence])} |"
      lines << ""

      lines << "**#{top_nodes.size} nodes** exported (max #{MAX_GRAPH_NODES}), **#{edges.size} edges** (max #{MAX_GRAPH_EDGES})"
      lines << ""

      # Nodes by type
      grouped_nodes = top_nodes.group_by(&:node_type)
      KnowledgeGraphNode::NODE_TYPES.each do |node_type|
        items = grouped_nodes[node_type]
        next if items.blank?

        lines << "## #{node_type.titleize} Nodes (#{items.size})"
        lines << ""
        lines << "| Name | Entity Type | Confidence | Mentions | Quality |"
        lines << "|------|-------------|------------|----------|---------|"
        items.each do |node|
          lines << "| #{node.name} | #{node.entity_type || '-'} | #{format_score(node.confidence)} | #{node.mention_count} | #{format_score(node.quality_score)} |"
        end
        lines << ""
      end

      # Edges summary
      if edges.any?
        lines << "## Relationships (#{edges.size})"
        lines << ""
        lines << "| Source | Relation | Target | Weight | Confidence |"
        lines << "|--------|----------|--------|--------|------------|"

        node_names = top_nodes.index_by(&:id)
        edges.includes(:source_node, :target_node).each do |edge|
          source_name = edge.source_node&.name || edge.source_node_id.to_s[0..7]
          target_name = edge.target_node&.name || edge.target_node_id.to_s[0..7]
          lines << "| #{source_name} | #{edge.relation_type} | #{target_name} | #{format_score(edge.weight)} | #{format_score(edge.confidence)} |"
        end
        lines << ""
      end

      write_file("GRAPH.md", lines)
      { success: true, nodes: top_nodes.size, edges: edges.size, stats: stats.slice(:node_count, :edge_count) }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Graph sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    def sync_todos(timestamp)
      entries = SharedKnowledge
        .where(account: @account)
        .with_tag("todo")
        .order(Arel.sql("COALESCE((provenance->>'priority'), 'low') ASC, quality_score DESC NULLS LAST"))
        .limit(MAX_TODOS)

      todo_dir = Rails.root.join("..", "docs")
      lines = doc_header("Powernode Platform — TODO", timestamp,
        "Source: `ai_shared_knowledges` | Filter: tagged \"todo\"")
      lines << "**#{entries.size} items** exported (max #{MAX_TODOS})"
      lines << ""

      grouped = entries.group_by { |e| e.provenance&.dig("phase") || e.provenance&.dig("category") || "General" }
      grouped.each do |group_name, items|
        lines << "## #{group_name} (#{items.size})"
        lines << ""

        items.each do |entry|
          status = entry.provenance&.dig("status") || "pending"
          checkbox = status == "completed" ? "[x]" : "[ ]"
          priority = entry.provenance&.dig("priority")

          lines << "- #{checkbox} #{entry.title}"
          content_preview = truncate_content(entry.content)
          lines << "  #{content_preview}" if content_preview != "_No content_"

          meta_parts = []
          meta_parts << "Priority: #{priority}" if priority.present?
          meta_parts << "Status: #{status}" if status != "completed" && status != "pending"
          lines << "  *#{meta_parts.join(' | ')}*" if meta_parts.any?

          lines << ""
        end
      end

      File.write(todo_dir.join("TODO.md"), lines.join("\n") + "\n")
      Rails.logger.info("[KnowledgeDocSync] Wrote #{todo_dir.join('TODO.md')}")
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Todos sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    # --- Learnings quality filters ---

    def filter_learnings(entries)
      entries
        .reject { |l| has_excluded_tags?(l) }
        .reject { |l| generic_failure?(l) }
        .then { |list| deduplicate_by_title(list) }
        .first(MAX_LEARNINGS)
    end

    def has_excluded_tags?(learning)
      return false if learning.tags.blank?

      learning.tags.any? { |tag| EXCLUDED_TAG_PREFIXES.any? { |prefix| tag.start_with?(prefix) } }
    end

    def generic_failure?(learning)
      return false unless learning.category == "failure_mode"

      learning.title.match?(GENERIC_FAILURE_TITLES) ||
        learning.content&.match?(/\AExecution error: Unknown error\z/)
    end

    def deduplicate_by_title(entries)
      entries.group_by(&:title).map do |_title, group|
        # Keep the entry with highest effective score (verified > active, then by importance)
        group.max_by { |l| [(l.status == "verified" ? 1 : 0), l.importance_score || 0, l.confidence_score || 0] }
      end
    end

    # --- Helpers ---

    def doc_header(title, timestamp, filter_description)
      [
        "# #{title}",
        "",
        "> Auto-generated by `rails mcp:sync_docs` on #{timestamp}",
        "> **Do not edit manually** — changes will be overwritten on next sync.",
        "> #{filter_description}",
        "",
        "---",
        ""
      ]
    end

    def sanitize_content(text)
      return nil if text.blank?

      # Replace literal \n escapes with actual newlines
      cleaned = text.gsub('\\n', "\n")
      # Strip leading/trailing whitespace and collapse excessive blank lines
      cleaned.strip.gsub(/\n{3,}/, "\n\n")
    end

    def truncate_content(text)
      return "_No content_" if text.blank?

      if text.length > CONTENT_TRUNCATE_LENGTH
        text[0...CONTENT_TRUNCATE_LENGTH].rstrip + "..."
      else
        text
      end
    end

    def format_score(value)
      return "-" if value.nil?

      format("%.2f", value)
    end

    def write_file(filename, lines)
      path = OUTPUT_DIR.join(filename)
      File.write(path, lines.join("\n") + "\n")
      Rails.logger.info("[KnowledgeDocSync] Wrote #{path}")
    end
  end
end

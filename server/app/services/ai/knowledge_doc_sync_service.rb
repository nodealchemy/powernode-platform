# frozen_string_literal: true

module Ai
  class KnowledgeDocSyncService
    PLATFORM_OUTPUT_DIR = Rails.root.join("..", "docs", "platform", "knowledge")
    EXTENSIONS_ROOT = Rails.root.join("..", "extensions")

    # Size caps per scope (platform or each extension)
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

    # Tag values that route entries to extension doc directories.
    # Keys are matched against each entry's tags array.
    # Values are extension slugs (matching extensions/<slug>/).
    EXTENSION_TAG_ROUTES = {
      "trading"       => "trading",
      "supply_chain"  => "supply-chain",
      "billing"       => "business",
      "baas"          => "business",
      "reseller"      => "business"
    }.freeze

    # Tag prefixes that imply an extension (e.g., "venue:polymarket" → trading)
    EXTENSION_TAG_PREFIX_ROUTES = {
      "venue:"    => "trading",
      "strategy:" => "trading"
    }.freeze

    # Ephemeral learnings — individual trade records, not durable knowledge
    EPHEMERAL_LEARNING_TITLE_PATTERNS = [
      /\AWin: /,
      /\ALoss: /
    ].freeze

    # Ephemeral knowledge — raw session summaries with no analytical value
    EPHEMERAL_KNOWLEDGE_TITLE_PATTERNS = [
      /\ATrading session: /,
      /\ASession idle: /,
      /\ASession profitable: /,
      /\ASession (R|r)egression /
    ].freeze

    def initialize(account:)
      @account = account
    end

    def sync_all!
      timestamp = Time.current.strftime("%Y-%m-%d %H:%M UTC")

      # Fetch and partition all data upfront
      all_learnings = fetch_learnings
      all_knowledge = fetch_knowledge
      all_skills = fetch_skills

      partitioned_learnings = partition_by_extension(all_learnings)
      partitioned_knowledge = partition_by_extension(all_knowledge)
      partitioned_skills = partition_by_extension(all_skills)

      scopes = (["platform"] + partitioned_learnings.keys + partitioned_knowledge.keys + partitioned_skills.keys).uniq

      results = {}

      scopes.each do |scope|
        output_dir = output_dir_for(scope)
        FileUtils.mkdir_p(output_dir)

        scope_learnings = partitioned_learnings[scope] || []
        scope_knowledge = partitioned_knowledge[scope] || []
        scope_skills = partitioned_skills[scope] || []

        results[scope.to_sym] = {
          learnings: render_learnings(scope_learnings.first(MAX_LEARNINGS), timestamp, output_dir, scope: scope),
          knowledge: render_knowledge(scope_knowledge.first(MAX_KNOWLEDGE), timestamp, output_dir, scope: scope),
          skills: render_skills(scope_skills.first(MAX_SKILLS), timestamp, output_dir, scope: scope)
        }
      end

      # Graph and TODOs are always platform-scoped
      results[:platform][:graph] = sync_graph(timestamp)
      results[:platform][:todos] = sync_todos(timestamp)

      results[:success] = results.values.all? do |scope_results|
        scope_results.is_a?(Hash) && scope_results.values.all? { |r| r.is_a?(Hash) ? r[:success] != false : true }
      end
      results[:synced_at] = timestamp
      results
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    private

    # =========================================================================
    # Data fetching (query once, partition later)
    # =========================================================================

    def fetch_learnings
      entries = CompoundLearning
        .for_account(@account.id)
        .where(status: %w[active verified])
        .where("importance_score >= ? OR confidence_score >= ?", LEARNING_MIN_IMPORTANCE, LEARNING_MIN_CONFIDENCE)
        .where("title IS NOT NULL AND title != ''")
        .order(importance_score: :desc, confidence_score: :desc, id: :asc)
        .limit(MAX_LEARNINGS * 5) # over-fetch to allow per-scope caps after partitioning

      filter_learnings(entries)
    end

    def fetch_knowledge
      entries = SharedKnowledge
        .where(account: @account)
        .where("quality_score >= ? OR quality_score IS NULL", KNOWLEDGE_MIN_QUALITY)
        .order(quality_score: :desc, usage_count: :desc, id: :asc)
        .limit(MAX_KNOWLEDGE * 5)

      filter_knowledge(entries)
    end

    def fetch_skills
      Skill
        .for_account(@account.id)
        .where(status: "active", is_enabled: true)
        .order(usage_count: :desc, effectiveness_score: :desc, id: :asc)
        .limit(MAX_SKILLS * 3)
        .to_a
    end

    # =========================================================================
    # Extension partitioning
    # =========================================================================

    def partition_by_extension(entries)
      result = Hash.new { |h, k| h[k] = [] }

      entries.each do |entry|
        scope = detect_extension(entry.tags)
        result[scope] << entry
      end

      result
    end

    def detect_extension(tags)
      return "platform" if tags.blank?

      tags.each do |tag|
        # Direct tag match (e.g., "trading" → "trading")
        if EXTENSION_TAG_ROUTES.key?(tag)
          return EXTENSION_TAG_ROUTES[tag]
        end

        # Prefix match (e.g., "venue:polymarket" → "trading")
        EXTENSION_TAG_PREFIX_ROUTES.each do |prefix, ext_slug|
          return ext_slug if tag.start_with?(prefix)
        end
      end

      "platform"
    end

    def output_dir_for(scope)
      if scope == "platform"
        PLATFORM_OUTPUT_DIR
      else
        EXTENSIONS_ROOT.join(scope, "docs", "knowledge")
      end
    end

    # =========================================================================
    # Rendering (entries pre-partitioned, output dir provided)
    # =========================================================================

    def render_learnings(entries, timestamp, output_dir, scope: "platform")
      scope_label = scope == "platform" ? "" : " (#{scope})"

      lines = doc_header("Learnings & Patterns#{scope_label}", timestamp,
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
          lines << "- **Scope**: #{learning.scope} | **Tags**: #{learning.tags&.join(', ').presence || 'none'}"
          lines << ""
        end
      end

      write_file("LEARNINGS.md", lines, output_dir)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Learnings sync failed (#{scope}): #{e.message}")
      { success: false, error: e.message }
    end

    def render_knowledge(entries, timestamp, output_dir, scope: "platform")
      scope_label = scope == "platform" ? "" : " (#{scope})"

      lines = doc_header("Shared Knowledge#{scope_label}", timestamp,
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

      write_file("KNOWLEDGE.md", lines, output_dir)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Knowledge sync failed (#{scope}): #{e.message}")
      { success: false, error: e.message }
    end

    def render_skills(entries, timestamp, output_dir, scope: "platform")
      scope_label = scope == "platform" ? "" : " (#{scope})"

      lines = doc_header("Skills Registry#{scope_label}", timestamp,
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

      write_file("SKILLS.md", lines, output_dir)
      { success: true, count: entries.size }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Skills sync failed (#{scope}): #{e.message}")
      { success: false, error: e.message }
    end

    # Graph stays platform-only — nodes are codebase-level, not extension-specific
    def sync_graph(timestamp)
      graph_service = KnowledgeGraph::GraphService.new(@account)
      stats = graph_service.statistics

      top_nodes = KnowledgeGraphNode
        .where(account: @account, status: "active")
        .where("confidence >= ?", GRAPH_NODE_MIN_CONFIDENCE)
        .order(mention_count: :desc, confidence: :desc, id: :asc)
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

        edges.includes(:source_node, :target_node).each do |edge|
          source_name = edge.source_node&.name || edge.source_node_id.to_s[0..7]
          target_name = edge.target_node&.name || edge.target_node_id.to_s[0..7]
          lines << "| #{source_name} | #{edge.relation_type} | #{target_name} | #{format_score(edge.weight)} | #{format_score(edge.confidence)} |"
        end
        lines << ""
      end

      write_file("GRAPH.md", lines, PLATFORM_OUTPUT_DIR)
      { success: true, nodes: top_nodes.size, edges: edges.size, stats: stats.slice(:node_count, :edge_count) }
    rescue StandardError => e
      Rails.logger.error("[KnowledgeDocSync] Graph sync failed: #{e.message}")
      { success: false, error: e.message }
    end

    # TODOs stay platform-only
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

    # =========================================================================
    # Quality filters
    # =========================================================================

    def filter_learnings(entries)
      entries
        .reject { |l| has_excluded_tags?(l) }
        .reject { |l| generic_failure?(l) }
        .reject { |l| ephemeral_learning?(l) }
        .then { |list| deduplicate_by_title(list) }
    end

    def filter_knowledge(entries)
      entries
        .reject { |k| ephemeral_knowledge?(k) }
        .to_a
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

    def ephemeral_learning?(learning)
      # Individual trade win/loss records — per-position P&L is runtime data
      return true if EPHEMERAL_LEARNING_TITLE_PATTERNS.any? { |pat| learning.title&.match?(pat) }

      # Zero-activity session idles that nobody has ever accessed
      return true if learning.title&.start_with?("Session idle:") && learning.access_count.to_i == 0

      false
    end

    def ephemeral_knowledge?(entry)
      # Raw session summaries (e.g., "Trading session: Overseer Temporal Session (overnight)")
      return true if EPHEMERAL_KNOWLEDGE_TITLE_PATTERNS.any? { |pat| entry.title&.match?(pat) }

      # System-generated entries with zero usage and low quality
      return true if entry.source_type == "system" && entry.usage_count.to_i == 0 && entry.quality_score.to_f < 0.6

      false
    end

    def deduplicate_by_title(entries)
      entries.group_by(&:title).map do |_title, group|
        # Keep the entry with highest effective score (verified > active, then by importance)
        group.max_by { |l| [(l.status == "verified" ? 1 : 0), l.importance_score || 0, l.confidence_score || 0] }
      end
    end

    # =========================================================================
    # Helpers
    # =========================================================================

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

      format("%.1f", value)
    end

    def write_file(filename, lines, output_dir)
      FileUtils.mkdir_p(output_dir)
      path = output_dir.is_a?(Pathname) ? output_dir.join(filename) : File.join(output_dir, filename)
      File.write(path, lines.join("\n") + "\n")
      Rails.logger.info("[KnowledgeDocSync] Wrote #{path}")
    end
  end
end

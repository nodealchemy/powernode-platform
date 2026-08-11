# frozen_string_literal: true

class ContentLinkService
  WIKILINK_PATTERN = /\[\[([^\]]+)\]\]/

  def initialize(account:)
    @account = account
  end

  # Extract wikilinks from page content and persist as KG edges
  def extract_links!(page)
    links = page.content.to_s.scan(WIKILINK_PATTERN).flatten.uniq
    return 0 if links.empty?

    source_node = find_or_create_page_node(page)

    # Remove stale reference edges from this source
    Ai::KnowledgeGraphEdge.where(
      source_node_id: source_node.id,
      relation_type: "references"
    ).destroy_all

    created = 0
    links.each do |link_text|
      target = resolve_link(link_text)
      next unless target

      target_node = find_or_create_content_node(target)

      Ai::KnowledgeGraphEdge.create!(
        account: @account,
        source_node: source_node,
        target_node: target_node,
        relation_type: "references",
        weight: 1.0,
        confidence: 1.0,
        bidirectional: false,
        metadata: { link_text: link_text }
      )
      created += 1
    end

    created
  end

  # Return pages/articles that link TO a given page
  def backlinks_for(page)
    node = find_page_node(page)
    return [] unless node

    edges = Ai::KnowledgeGraphEdge
      .where(target_node_id: node.id, relation_type: "references")
      .includes(:source_node)

    edges.filter_map { |edge| resolve_node_to_content(edge.source_node) }
  end

  # Find pages that mention the title as plain text but without [[]] wikilink syntax
  def unlinked_mentions_for(page)
    escaped_title = Page.sanitize_sql_like(page.title)

    Page.where(account: @account)
        .where.not(id: page.id)
        .where("content ILIKE ?", "%#{escaped_title}%")
        .where.not("content ILIKE ?", "%[[#{escaped_title}]]%")
        .order(updated_at: :desc)
        .limit(20)
  end

  # Ensure a KG node exists for a page (used by callbacks and embedding)
  def find_or_create_page_node(page)
    node = find_page_node(page)
    if node
      # Keep node name and slug in sync with the page
      node.update!(name: page.title, metadata: node.metadata.merge("slug" => page.slug)) if node.name != page.title
      node
    else
      Ai::KnowledgeGraphNode.create!(
        account: @account,
        name: page.title,
        node_type: "content",
        entity_type: "page",
        status: "active",
        confidence: 1.0,
        mention_count: 0,
        metadata: { content_type: "page", content_id: page.id, slug: page.slug }
      )
    end
  end

  # Generate and store an embedding for a page's content on its KG node
  def generate_page_embedding!(page)
    node = find_or_create_page_node(page)

    embedding_service = Ai::Memory::EmbeddingService.new(account: @account)
    text = "#{page.title}\n\n#{page.content}"
    embedding = embedding_service.generate(text)

    node.set_embedding!(embedding) if embedding
  end

  # Return pages semantically similar to this page via KG node embedding cosine similarity.
  # Yields [content_record, similarity_float] pairs sorted by similarity DESC.
  def related_pages_for(page, limit: 10)
    source_node = find_page_node(page)
    return [] unless source_node&.embedding.present?

    neighbors = Ai::KnowledgeGraphNode
      .where(account: @account, node_type: "content", entity_type: %w[page article])
      .where.not(id: source_node.id)
      .where.not(embedding: nil)
      .nearest_neighbors(:embedding, source_node.embedding, distance: "cosine")
      .limit(limit)

    neighbors.filter_map do |node|
      content = resolve_node_to_content(node)
      next unless content

      # neighbor_distance is a cosine distance (0 = identical, 2 = opposite).
      similarity = 1.0 - node.neighbor_distance.to_f
      [ content, similarity ]
    end
  end

  private

  def find_page_node(page)
    Ai::KnowledgeGraphNode
      .where(account: @account, node_type: "content", entity_type: "page")
      .where("metadata->>'content_id' = ?", page.id.to_s)
      .first
  end

  def find_or_create_content_node(content)
    case content
    when Page
      find_or_create_page_node(content)
    when KnowledgeBase::Article
      find_or_create_article_node(content)
    end
  end

  def find_or_create_article_node(article)
    node = Ai::KnowledgeGraphNode
      .where(account: @account, node_type: "content", entity_type: "article")
      .where("metadata->>'content_id' = ?", article.id.to_s)
      .first

    node || Ai::KnowledgeGraphNode.create!(
      account: @account,
      name: article.title,
      node_type: "content",
      entity_type: "article",
      status: "active",
      confidence: 1.0,
      mention_count: 0,
      metadata: { content_type: "article", content_id: article.id, slug: article.slug }
    )
  end

  def resolve_link(link_text)
    # Support [[Title|Display Text]] alias syntax — resolve using the title part
    title = link_text.split("|").first.strip
    slug = title.downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-")

    # Try Page first (account-scoped)
    Page.where(account: @account)
        .where("title ILIKE ? OR slug = ?", title, slug)
        .first ||
    # Fallback to KnowledgeBase::Article — override-aware (GLOBAL platform
    # articles + this account's own); never resolves another tenant's article.
    KnowledgeBase::Article
        .for_account(@account.id)
        .where("title ILIKE ? OR slug = ?", title, slug)
        .first
  end

  def resolve_node_to_content(node)
    return nil unless node&.metadata.is_a?(Hash)

    content_id = node.metadata["content_id"]
    return nil unless content_id

    case node.entity_type
    when "page"
      Page.find_by(id: content_id)
    when "article"
      KnowledgeBase::Article.find_by(id: content_id)
    end
  end
end

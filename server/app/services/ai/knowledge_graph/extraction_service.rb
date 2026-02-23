# frozen_string_literal: true

module Ai
  module KnowledgeGraph
    class ExtractionServiceError < StandardError; end

    class ExtractionService
      include Ai::Concerns::PromptTemplateLookup

      DEDUP_THRESHOLD = 0.92
      MAX_CHUNK_LENGTH = 4000

      PROMPT_SLUG = "ai-kg-entity-extraction"
      FALLBACK_PROMPT = "You are a knowledge graph extraction expert. Extract entities and their relationships from the given text. " \
                        "Focus on named entities (people, organizations, technologies, events, locations) and meaningful relationships between them. " \
                        "Be precise and concise. Only extract clearly stated facts."
      EXTRACTION_SCHEMA = {
        name: "knowledge_extraction",
        schema: {
          type: "object",
          properties: {
            entities: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: { type: "string" },
                  type: { type: "string", enum: %w[person organization technology event location custom] },
                  description: { type: "string" }
                },
                required: %w[name type]
              }
            },
            relations: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  source: { type: "string" },
                  target: { type: "string" },
                  type: {
                    type: "string",
                    enum: Ai::KnowledgeGraphEdge::RELATION_TYPES
                  },
                  description: { type: "string" }
                },
                required: %w[source target type]
              }
            }
          },
          required: %w[entities relations]
        }
      }.freeze

      def initialize(account)
        @account = account
        @graph_service = GraphService.new(account)
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Extract entities and relations from arbitrary text (no document required)
      def extract_from_text(text:, source_label: nil)
        raise ExtractionServiceError, "Text is required" if text.blank?

        stats = { nodes_created: 0, nodes_existing: 0, edges_created: 0, edges_existing: 0 }
        all_nodes = {}
        all_edges = []

        chunks = split_for_extraction(text)

        chunks.each do |chunk|
          extraction = extract_entities_and_relations(chunk)
          next unless extraction

          extraction["entities"]&.each do |entity|
            node = find_or_create_node(entity, document: nil, existing_nodes: all_nodes, stats: stats)
            all_nodes[entity["name"].downcase] = node if node
          end

          extraction["relations"]&.each do |relation|
            edge = create_edge_from_relation(relation, document: nil, nodes: all_nodes, stats: stats)
            all_edges << edge if edge
          end
        end

        Rails.logger.info(
          "[ExtractionService] Extracted from text#{source_label ? " (#{source_label})" : ''}: " \
          "#{stats[:nodes_created]} new nodes, #{stats[:edges_created]} new edges"
        )

        { nodes: all_nodes.values.compact, edges: all_edges.compact, stats: stats }
      rescue StandardError => e
        Rails.logger.error "[ExtractionService] Text extraction failed: #{e.message}"
        raise ExtractionServiceError, "Extraction failed: #{e.message}"
      end

      # Extract entities and relations from a document
      def extract_from_document(document:)
        content = document.content
        raise ExtractionServiceError, "Document has no content" if content.blank?

        stats = { nodes_created: 0, nodes_existing: 0, edges_created: 0, edges_existing: 0 }
        all_nodes = {}
        all_edges = []

        # Split content into chunks for extraction
        chunks = split_for_extraction(content)

        chunks.each do |chunk|
          extraction = extract_entities_and_relations(chunk)
          next unless extraction

          # Process entities
          extraction["entities"]&.each do |entity|
            node = find_or_create_node(
              entity,
              document: document,
              existing_nodes: all_nodes,
              stats: stats
            )
            all_nodes[entity["name"].downcase] = node if node
          end

          # Process relations
          extraction["relations"]&.each do |relation|
            edge = create_edge_from_relation(
              relation,
              document: document,
              nodes: all_nodes,
              stats: stats
            )
            all_edges << edge if edge
          end
        end

        Rails.logger.info(
          "[ExtractionService] Extracted from document #{document.id}: " \
          "#{stats[:nodes_created]} new nodes, #{stats[:edges_created]} new edges"
        )

        { nodes: all_nodes.values.compact, edges: all_edges.compact, stats: stats }
      rescue StandardError => e
        Rails.logger.error "[ExtractionService] Extraction failed: #{e.message}"
        raise ExtractionServiceError, "Extraction failed: #{e.message}"
      end

      private

      def split_for_extraction(content)
        return [content] if content.length <= MAX_CHUNK_LENGTH

        chunks = []
        paragraphs = content.split(/\n\n+/)
        current_chunk = ""

        paragraphs.each do |para|
          if (current_chunk.length + para.length + 2) <= MAX_CHUNK_LENGTH
            current_chunk += "\n\n" + para
          else
            chunks << current_chunk.strip unless current_chunk.blank?
            current_chunk = para
          end
        end

        chunks << current_chunk.strip unless current_chunk.blank?
        chunks
      end

      def extract_entities_and_relations(text)
        client = build_llm_client
        return fallback_extraction(text) unless client

        system_content = resolve_prompt_template(
          PROMPT_SLUG,
          account: @account,
          fallback: FALLBACK_PROMPT
        )

        messages = [
          {
            role: "system",
            content: system_content
          },
          {
            role: "user",
            content: "Extract entities and relationships from the following text:\n\n#{text}"
          }
        ]

        response = client.complete_structured(
          messages: messages,
          schema: EXTRACTION_SCHEMA,
          model: default_model
        )

        return nil unless response.success?

        parsed = response.parsed_content || response.content
        parsed.is_a?(String) ? JSON.parse(parsed) : parsed
      rescue StandardError => e
        Rails.logger.warn "[ExtractionService] LLM extraction failed: #{e.message}, using fallback"
        fallback_extraction(text)
      end

      def fallback_extraction(text)
        # Simple NER-like extraction using regex patterns
        entities = []
        relations = []

        # Extract capitalized phrases as potential entities
        text.scan(/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b/).flatten.uniq.each do |name|
          next if name.length < 3 || common_word?(name)

          entities << {
            "name" => name,
            "type" => "custom",
            "description" => nil
          }
        end

        # Extract simple relations from sentence patterns
        entities.combination(2).each do |e1, e2|
          pattern = /#{Regexp.escape(e1["name"])}[^.]*?#{Regexp.escape(e2["name"])}/i
          if text.match?(pattern)
            relations << {
              "source" => e1["name"],
              "target" => e2["name"],
              "type" => "related_to",
              "description" => nil
            }
          end
        end

        { "entities" => entities.first(20), "relations" => relations.first(30) }
      end

      def find_or_create_node(entity, document:, existing_nodes:, stats:)
        name = entity["name"]&.strip
        return nil if name.blank?

        # Check in-memory cache first
        cached = existing_nodes[name.downcase]
        if cached
          cached.record_mention!
          stats[:nodes_existing] += 1
          return cached
        end

        # Check database for existing active node with same name
        existing = @account.ai_knowledge_graph_nodes.active.find_by(
          "LOWER(name) = ? AND node_type = ?",
          name.downcase,
          "entity"
        )

        if existing
          existing.record_mention!
          stats[:nodes_existing] += 1
          return existing
        end

        # Check for semantic duplicates via embedding similarity
        if should_check_embedding_dedup?(name, entity["description"])
          embedding_text = "#{name}: #{entity['description']}"
          embedding = @embedding_service.generate(embedding_text)

          if embedding && @account.ai_knowledge_graph_nodes.active.with_embeddings.exists?
            candidates = @account.ai_knowledge_graph_nodes
              .active
              .nearest_neighbors(:embedding, embedding, distance: "cosine")
              .first(3)

            similar = candidates.find { |c| c.neighbor_distance <= (1.0 - DEDUP_THRESHOLD) }
            if similar
              similar.record_mention!
              stats[:nodes_existing] += 1
              return similar
            end
          end
        end

        # Create new node
        create_attrs = {
          name: name,
          node_type: "entity",
          entity_type: map_entity_type(entity["type"]),
          description: entity["description"]
        }
        create_attrs[:source_document_id] = document.id if document
        create_attrs[:knowledge_base_id] = document.knowledge_base_id if document

        node = @graph_service.create_node(**create_attrs)

        stats[:nodes_created] += 1
        node
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "[ExtractionService] Node creation failed for '#{name}': #{e.message}"
        nil
      end

      def create_edge_from_relation(relation, document:, nodes:, stats:)
        source_name = relation["source"]&.downcase
        target_name = relation["target"]&.downcase
        relation_type = relation["type"]

        return nil unless source_name && target_name && relation_type

        source_node = nodes[source_name]
        target_node = nodes[target_name]

        return nil unless source_node && target_node

        # Validate relation type
        unless Ai::KnowledgeGraphEdge::RELATION_TYPES.include?(relation_type)
          relation_type = "related_to"
        end

        # Check for existing edge
        existing = Ai::KnowledgeGraphEdge.find_by(
          source_node_id: source_node.id,
          target_node_id: target_node.id,
          relation_type: relation_type,
          status: "active"
        )

        if existing
          stats[:edges_existing] += 1
          return existing
        end

        edge_attrs = {
          source: source_node,
          target: target_node,
          relation_type: relation_type,
          label: relation["description"]
        }
        edge_attrs[:source_document_id] = document.id if document

        edge = @graph_service.create_edge(**edge_attrs)

        stats[:edges_created] += 1
        edge
      rescue GraphServiceError => e
        Rails.logger.warn "[ExtractionService] Edge creation failed: #{e.message}"
        nil
      end

      def should_check_embedding_dedup?(name, description)
        description.present? && name.length >= 3
      end

      def map_entity_type(type)
        return nil if type.blank?

        valid_types = Ai::KnowledgeGraphNode::ENTITY_TYPES
        valid_types.include?(type) ? type : "custom"
      end

      def common_word?(word)
        %w[The This That These Those When Where What Which Who How But And For Not
           Are Was Were Has Had Have Does Did Can Could Would Should May Might Must
           Will Shall Into From With About Between Through During Before After].include?(word)
      end

      def build_llm_client
        Ai::Llm::Client.for_account(@account)
      rescue StandardError => e
        Rails.logger.warn "[ExtractionService] LLM client unavailable: #{e.message}"
        nil
      end

      def default_model
        "gpt-4.1"
      end
    end
  end
end

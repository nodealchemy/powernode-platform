# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # KB Article Create node executor - creates knowledge base articles
    class KbArticleCreate < Base
      protected

      def perform_execution
        log_info "Creating knowledge base article"

        # Extract article data from configuration and input
        article_data = extract_article_data

        # Validate required fields
        validate_article_data!(article_data)

        # Create the article
        article = create_article(article_data)

        # Store article ID in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], article.id)
        end

        log_info "Created KB article: #{article.title} (#{article.id})"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Knowledge base article '#{article.title}' created successfully",
          result: {
            article_id: article.id,
            slug: article.slug,
            status: article.status,
            published: article.published?
          },
          data: {
            article: {
              id: article.id,
              title: article.title,
              slug: article.slug,
              content: article.content,
              excerpt: article.excerpt,
              status: article.status,
              category_id: article.category_id,
              tags: article.tag_names,
              is_public: article.is_public,
              is_featured: article.is_featured,
              created_at: article.created_at.iso8601,
              updated_at: article.updated_at.iso8601
            }
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "kb_article_create",
            executed_at: Time.current.iso8601,
            operation: "create",
            record_type: "KnowledgeBaseArticle"
          }
        }
      end

      private

      def extract_article_data
        data = {}

        # Get data from configuration
        data[:title] = configuration["title"] || get_variable("title")
        data[:content] = configuration["content"] || get_variable("content")
        data[:excerpt] = configuration["excerpt"] || get_variable("excerpt")
        data[:meta_title] = configuration["meta_title"] || get_variable("meta_title")
        data[:meta_description] = configuration["meta_description"] || get_variable("meta_description")
        data[:status] = configuration["status"] || get_variable("status") || "draft"
        data[:category_id] = configuration["category_id"] || get_variable("category_id")
        data[:is_public] = configuration["is_public"] || get_variable("is_public") || false
        data[:is_featured] = configuration["is_featured"] || get_variable("is_featured") || false

        # Handle tags (array or comma-separated string)
        tags = configuration["tags"] || get_variable("tags")
        data[:tag_names] = normalize_tags(tags) if tags.present?

        # Apply template rendering to content if needed
        if data[:content].present? && data[:content].include?("{{")
          data[:content] = render_template(data[:content])
        end

        # Apply template rendering to title if needed
        if data[:title].present? && data[:title].include?("{{")
          data[:title] = render_template(data[:title])
        end

        # Fallback: Extract content from previous node outputs if not explicitly set
        if data[:content].blank? || data[:title].blank?
          extract_from_previous_results(data)
        end

        # Parse SEO-formatted content if detected
        parse_seo_formatted_content!(data) if seo_formatted_content?(data[:content])

        # Ensure title is properly capitalized
        data[:title] = capitalize_title(data[:title]) if data[:title].present?

        data
      end

      def extract_from_previous_results(data)
        # Try to extract content from previous AI agent outputs
        previous_results.each do |node_id, result|
          next unless result.is_a?(Hash)

          # Look for output content from AI agents
          output = result[:output] || result["output"] ||
                   result.dig(:data, :output) || result.dig("data", "output")

          if output.present? && data[:content].blank?
            data[:content] = output.to_s
            log_info "Extracted content from node '#{node_id}'"
          end

          # Try to extract title from result
          title = result[:title] || result["title"] ||
                  result.dig(:data, :title) || result.dig("data", "title")

          if title.present? && data[:title].blank?
            data[:title] = title.to_s
            log_info "Extracted title from node '#{node_id}'"
          end
        end

        # Generate title from content if still missing
        if data[:title].blank? && data[:content].present?
          # Use first line or first 50 chars as title
          first_line = data[:content].to_s.split("\n").first.to_s.strip
          data[:title] = first_line.truncate(100)
          log_info "Generated title from content: #{data[:title]}"
        end

        # Use workflow input prompt as title fallback
        if data[:title].blank?
          prompt = get_variable("prompt") || get_variable("input")
          data[:title] = prompt.to_s.truncate(100) if prompt.present?
          log_info "Using input prompt as title: #{data[:title]}" if data[:title].present?
        end
      end

      def validate_article_data!(data)
        errors = []
        errors << "Title is required" if data[:title].blank?
        errors << "Content is required" if data[:content].blank?

        # Auto-assign default category if not provided
        if data[:category_id].blank?
          data[:category_id] = find_or_create_default_category.id
          log_info "Using default category: #{data[:category_id]}"
        end

        unless errors.empty?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "KB Article validation failed: #{errors.join(', ')}"
        end

        # Validate status
        valid_statuses = %w[draft review published archived]
        unless valid_statuses.include?(data[:status])
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Invalid status '#{data[:status]}'. Must be one of: #{valid_statuses.join(', ')}"
        end

        # Validate category exists
        unless KnowledgeBaseCategory.exists?(data[:category_id])
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Category not found: #{data[:category_id]}"
        end
      end

      def find_or_create_default_category
        # Try to find an existing default category
        category = KnowledgeBaseCategory.find_by(slug: "ai-generated") ||
                   KnowledgeBaseCategory.find_by(slug: "general") ||
                   KnowledgeBaseCategory.first

        # Create a default category if none exists
        unless category
          category = KnowledgeBaseCategory.create!(
            name: "AI Generated",
            slug: "ai-generated",
            description: "Articles generated by AI workflows"
          )
        end

        category
      end

      def create_article(data)
        # Get author from workflow context
        author = @orchestrator.user || User.find_by(email: "system@powernode.ai")

        # Create the article with all fields including SEO metadata
        article = KnowledgeBaseArticle.create!(
          title: data[:title],
          content: data[:content],
          excerpt: data[:excerpt],
          meta_title: data[:meta_title],
          meta_description: data[:meta_description],
          status: data[:status],
          category_id: data[:category_id],
          author: author,
          is_public: data[:is_public],
          is_featured: data[:is_featured]
        )

        # Assign tags if provided
        if data[:tag_names].present?
          article.tag_names = data[:tag_names]
          article.save!
        end

        article
      rescue ActiveRecord::RecordInvalid => e
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Failed to create KB article: #{e.message}"
      end

      # Check if content appears to be SEO-formatted output
      def seo_formatted_content?(content)
        return false if content.blank?

        content.to_s.include?("## SEO Optimization Package") ||
          content.to_s.include?("### 1. SEO-Optimized Title") ||
          (content.to_s.include?("### 4. Optimized Article") && content.to_s.include?("Meta Description"))
      end

      # Parse SEO-formatted content and extract proper fields
      def parse_seo_formatted_content!(data)
        content = data[:content].to_s
        log_info "Parsing SEO-formatted content structure"

        # Extract SEO-optimized title (between ** markers after "SEO-Optimized Title")
        if content =~ /###\s*\d*\.?\s*SEO[- ]Optimized Title[^\n]*\n\**([^*\n]+)\**/i
          extracted_title = $1.strip
          if extracted_title.present? && extracted_title.length > 10
            data[:meta_title] = extracted_title
            # Use SEO title as main title if current title is just the prompt
            if data[:title].blank? || data[:title].length < 50
              data[:title] = extracted_title
            end
            log_info "Extracted SEO title: #{extracted_title[0..50]}..."
          end
        end

        # Extract meta description (text after "Meta Description" heading, before next section)
        if content =~ /###\s*\d*\.?\s*Meta Description[^\n]*\n([^\n#]+)/i
          extracted_meta = $1.strip
          # Clean up any character count annotations
          extracted_meta = extracted_meta.gsub(/\(\d+\s*characters?\)/i, "").strip
          if extracted_meta.present? && extracted_meta.length > 20
            data[:meta_description] = extracted_meta.truncate(160)
            log_info "Extracted meta description: #{data[:meta_description][0..50]}..."
          end
        end

        # Extract keywords for tags
        if content =~ /###\s*\d*\.?\s*Target Keywords[^\n]*\n(.*?)(?=###|\z)/im
          keywords_section = $1
          # Extract keywords from bullet points (lines starting with -)
          keywords = keywords_section.scan(/^-\s*([^*\n]+)$/m).flatten
                                     .map(&:strip)
                                     .reject { |k| k.include?("Keywords") || k.length > 50 || k.blank? }
                                     .first(10)
          if keywords.any? && data[:tag_names].blank?
            data[:tag_names] = keywords
            log_info "Extracted #{keywords.length} keywords as tags"
          end
        end

        # Extract only the optimized article content (after "Optimized Article" heading)
        if content =~ /###\s*\d*\.?\s*Optimized Article\s*\n(.+)/im
          article_content = $1.strip
          if article_content.present? && article_content.length > 100
            data[:content] = article_content
            log_info "Extracted article content (#{article_content.length} chars)"
          end
        end

        # Generate excerpt from first paragraph of actual content
        if data[:excerpt].blank? && data[:content].present?
          # Find first substantial paragraph (skip headings)
          paragraphs = data[:content].split(/\n\n+/)
          first_paragraph = paragraphs.find { |p| p.strip.length > 50 && !p.strip.start_with?("#") }
          if first_paragraph
            # Strip markdown formatting for excerpt
            clean_excerpt = first_paragraph.gsub(/\*\*([^*]+)\*\*/, '\1')
                                           .gsub(/\*([^*]+)\*/, '\1')
                                           .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
                                           .strip
            data[:excerpt] = clean_excerpt.truncate(300)
          end
        end
      end

      # Properly capitalize a title (Title Case)
      def capitalize_title(title)
        return title if title.blank?

        # Words that should stay lowercase (unless first word)
        minor_words = %w[a an the and but or nor for yet so at by in of on to up as]

        words = title.strip.split(/\s+/)
        words.map.with_index do |word, index|
          # Always capitalize first word
          if index == 0
            word.capitalize
          # Don't change acronyms (all caps) or words with mixed case like "iPhone"
          elsif word == word.upcase && word.length > 1
            word
          elsif word =~ /[A-Z]/ && word =~ /[a-z]/
            word
          # Keep minor words lowercase unless first word
          elsif minor_words.include?(word.downcase)
            word.downcase
          else
            word.capitalize
          end
        end.join(" ")
      end

      def normalize_tags(tags)
        return [] if tags.blank?

        if tags.is_a?(Array)
          tags.map(&:to_s).map(&:strip).reject(&:blank?)
        elsif tags.is_a?(String)
          tags.split(",").map(&:strip).reject(&:blank?)
        else
          []
        end
      end

      def render_template(template)
        return template unless template.is_a?(String)

        result = template.dup

        # Find all {{variable}} patterns and replace with values from execution context
        result.gsub(/\{\{(\w+)\}\}/) do |match|
          variable_name = $1
          value = get_variable(variable_name)
          value.present? ? value.to_s : match
        end
      end
    end
  end
end

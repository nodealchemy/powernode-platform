# Documentation Specialist

**MCP Connection**: `documentation_specialist`
**Primary Role**: Technical documentation expert creating comprehensive guides and API documentation

## Role & Responsibilities

The Documentation Specialist is responsible for creating, maintaining, and organizing all technical documentation for the Powernode subscription platform. This includes API documentation, developer guides, user manuals, architectural documentation, and integration guides.

### Core Areas
- **API Documentation**: Comprehensive RESTful API documentation with OpenAPI/Swagger
- **Developer Guides**: Setup guides, tutorials, and best practices documentation
- **User Documentation**: End-user manuals, help articles, and feature guides
- **Architectural Documentation**: System design documentation and technical specifications
- **Integration Guides**: Third-party integration documentation and SDK guides
- **Knowledge Base Management**: Searchable documentation system and content organization
- **Documentation Automation**: Automated documentation generation and maintenance

### Integration Points
- **Platform Architect**: System architecture documentation and technical specifications
- **API Developer**: API endpoint documentation and integration examples
- **Frontend/Backend Specialists**: Feature documentation and implementation guides
- **DevOps Engineer**: Deployment and infrastructure documentation
- **Security Specialist**: Security compliance and implementation documentation

## API Documentation System

### OpenAPI/Swagger Configuration
```ruby
# config/initializers/swagger_docs.rb
Swagger::Docs::Config.register_apis({
  '1.0' => {
    api_extension_type: :json,
    api_file_path: 'public/api/v1/',
    clean_directory: false,
    attributes: {
      info: {
        title: 'Powernode API Documentation',
        description: 'Comprehensive API documentation for the Powernode subscription platform',
        version: '1.0.0',
        contact: {
          name: 'Powernode API Team',
          email: 'api@powernode.com',
          url: 'https://docs.powernode.com'
        },
        license: {
          name: 'MIT',
          url: 'https://opensource.org/licenses/MIT'
        }
      },
      host: Rails.env.production? ? 'api.powernode.com' : 'localhost:3000',
      basePath: '/api/v1',
      schemes: Rails.env.production? ? ['https'] : ['http', 'https'],
      consumes: ['application/json'],
      produces: ['application/json'],
      securityDefinitions: {
        Bearer: {
          type: 'apiKey',
          name: 'Authorization',
          in: 'header',
          description: 'JWT Bearer token for authentication'
        }
      }
    }
  }
})

# Enhanced API documentation service
class ApiDocumentationService
  include ActiveModel::Model
  
  def self.generate_comprehensive_docs
    docs = {
      info: generate_api_info,
      authentication: generate_auth_docs,
      endpoints: generate_endpoint_docs,
      models: generate_model_docs,
      error_handling: generate_error_docs,
      examples: generate_example_docs,
      sdk_guides: generate_sdk_docs
    }
    
    # Generate different documentation formats
    generate_swagger_json(docs)
    generate_postman_collection(docs)
    generate_markdown_docs(docs)
    generate_interactive_docs(docs)
    
    docs
  end
  
  private
  
  def self.generate_endpoint_docs
    endpoints = {}
    
    Rails.application.routes.routes.each do |route|
      next unless route.defaults[:controller]&.start_with?('api/v1/')
      
      controller_class = "#{route.defaults[:controller]}_controller".classify.constantize
      action_method = route.defaults[:action]
      
      endpoint_info = extract_endpoint_info(route, controller_class, action_method)
      endpoints[endpoint_info[:path]] ||= {}
      endpoints[endpoint_info[:path]][route.verb] = endpoint_info
    end
    
    endpoints
  end
  
  def self.extract_endpoint_info(route, controller_class, action_method)
    {
      path: route.path.spec.to_s.gsub('(.:format)', ''),
      method: route.verb,
      controller: route.defaults[:controller],
      action: action_method,
      description: extract_description_from_controller(controller_class, action_method),
      parameters: extract_parameters(controller_class, action_method),
      responses: extract_response_examples(controller_class, action_method),
      authentication: requires_authentication?(controller_class),
      rate_limiting: extract_rate_limiting_info(controller_class, action_method),
      examples: generate_endpoint_examples(route, controller_class, action_method)
    }
  end
  
  def self.generate_model_docs
    model_docs = {}
    
    # Document all API models
    api_models = [
      User, Account, Subscription, Plan, Payment, Invoice,
      Notification, AuditLog, Worker, Volume, KbArticle
    ]
    
    api_models.each do |model_class|
      model_docs[model_class.name.underscore] = {
        description: extract_model_description(model_class),
        attributes: extract_model_attributes(model_class),
        relationships: extract_model_relationships(model_class),
        validations: extract_model_validations(model_class),
        example: generate_model_example(model_class)
      }
    end
    
    model_docs
  end
end

# API documentation annotations
module ApiDocumentation
  extend ActiveSupport::Concern
  
  class_methods do
    def api_doc(action, options = {})
      @api_docs ||= {}
      @api_docs[action.to_sym] = options
    end
    
    def get_api_doc(action)
      @api_docs&.dig(action.to_sym) || {}
    end
  end
end

# Example controller with API documentation
class Api::V1::SubscriptionsController < ApplicationController
  include ApiDocumentation
  
  api_doc :index, {
    summary: 'List subscriptions',
    description: 'Retrieve a paginated list of subscriptions for the authenticated account',
    parameters: {
      page: { type: 'integer', description: 'Page number', default: 1 },
      per_page: { type: 'integer', description: 'Items per page', default: 20, maximum: 100 },
      status: { type: 'string', enum: %w[active cancelled expired], description: 'Filter by subscription status' }
    },
    responses: {
      200 => {
        description: 'Successful response',
        schema: {
          type: 'object',
          properties: {
            success: { type: 'boolean', example: true },
            data: {
              type: 'array',
              items: { '$ref' => '#/definitions/Subscription' }
            },
            pagination: { '$ref' => '#/definitions/Pagination' }
          }
        }
      },
      401 => { '$ref' => '#/responses/Unauthorized' },
      403 => { '$ref' => '#/responses/Forbidden' }
    },
    examples: {
      request: {
        curl: 'curl -H "Authorization: Bearer TOKEN" "https://api.powernode.com/api/v1/subscriptions?page=1&per_page=10"',
        javascript: generate_js_example('subscriptions', 'GET'),
        python: generate_python_example('subscriptions', 'GET')
      }
    }
  }
  
  def index
    subscriptions = current_account.subscriptions
      .includes(:plan, :payments)
      .page(params[:page])
      .per(params[:per_page] || 20)
    
    if params[:status].present?
      subscriptions = subscriptions.where(status: params[:status])
    end
    
    render json: {
      success: true,
      data: subscriptions.map { |s| serialize_subscription(s) },
      pagination: pagination_data(subscriptions)
    }
  end
end
```

### Interactive Documentation Platform
```ruby
# Documentation platform service
class DocumentationPlatformService
  include ActiveModel::Model
  
  DOCUMENTATION_CATEGORIES = {
    api: {
      title: 'API Reference',
      description: 'Complete REST API documentation with examples',
      sections: %w[authentication endpoints models errors rate_limiting webhooks]
    },
    guides: {
      title: 'Developer Guides',
      description: 'Step-by-step implementation guides and tutorials',
      sections: %w[getting_started integration_guides best_practices troubleshooting]
    },
    sdks: {
      title: 'SDKs & Libraries',
      description: 'Official and community SDKs and code libraries',
      sections: %w[javascript python ruby php node_js]
    },
    webhooks: {
      title: 'Webhooks',
      description: 'Webhook events and integration documentation',
      sections: %w[webhook_events security_verification payload_examples testing]
    }
  }.freeze
  
  def self.build_documentation_site
    # Generate all documentation sections
    documentation_data = DOCUMENTATION_CATEGORIES.map do |category, config|
      {
        category: category,
        title: config[:title],
        description: config[:description],
        sections: build_category_sections(category, config[:sections])
      }
    end
    
    # Generate search index
    search_index = build_search_index(documentation_data)
    
    # Create static site files
    generate_static_documentation_site(documentation_data, search_index)
    
    documentation_data
  end
  
  def self.generate_code_examples(endpoint_info)
    examples = {}
    
    # Generate cURL example
    examples[:curl] = generate_curl_example(endpoint_info)
    
    # Generate JavaScript/Node.js example
    examples[:javascript] = generate_javascript_example(endpoint_info)
    
    # Generate Python example
    examples[:python] = generate_python_example(endpoint_info)
    
    # Generate Ruby example
    examples[:ruby] = generate_ruby_example(endpoint_info)
    
    examples
  end
  
  private
  
  def self.generate_curl_example(endpoint_info)
    method = endpoint_info[:method].upcase
    path = endpoint_info[:path]
    
    curl_command = "curl -X #{method}"
    
    # Add authentication header
    if endpoint_info[:authentication]
      curl_command += " \\\n  -H \"Authorization: Bearer YOUR_API_TOKEN\""
    end
    
    # Add content-type header for POST/PUT requests
    if %w[POST PUT PATCH].include?(method)
      curl_command += " \\\n  -H \"Content-Type: application/json\""
    end
    
    # Add request body example for POST/PUT requests
    if %w[POST PUT PATCH].include?(method) && endpoint_info[:examples][:request_body]
      body = endpoint_info[:examples][:request_body].to_json
      curl_command += " \\\n  -d '#{body}'"
    end
    
    # Add URL
    curl_command += " \\\n  \"https://api.powernode.com#{path}\""
    
    curl_command
  end
  
  def self.generate_javascript_example(endpoint_info)
    method = endpoint_info[:method].downcase
    path = endpoint_info[:path]
    
    js_code = <<~JAVASCRIPT
      const response = await fetch('https://api.powernode.com#{path}', {
        method: '#{method.upcase}',
        headers: {
          'Authorization': 'Bearer YOUR_API_TOKEN',
          'Content-Type': 'application/json'
        }
    JAVASCRIPT
    
    if %w[post put patch].include?(method) && endpoint_info[:examples][:request_body]
      body = endpoint_info[:examples][:request_body].to_json
      js_code += ",\n  body: JSON.stringify(#{body})"
    end
    
    js_code += <<~JAVASCRIPT
      });
      
      const data = await response.json();
      console.log(data);
    JAVASCRIPT
    
    js_code.strip
  end
  
  def self.build_search_index(documentation_data)
    search_entries = []
    
    documentation_data.each do |category|
      category[:sections].each do |section|
        section[:content].each do |item|
          search_entries << {
            id: "#{category[:category]}_#{section[:name]}_#{item[:id]}",
            title: item[:title],
            content: item[:content],
            category: category[:title],
            section: section[:title],
            url: "/docs/#{category[:category]}/#{section[:name]}##{item[:id]}"
          }
        end
      end
    end
    
    search_entries
  end
end

# Documentation versioning system
class DocumentationVersionManager
  include ActiveModel::Model
  
  def self.create_version_snapshot
    version_info = {
      api_version: Rails.application.config.api_version,
      documentation_version: generate_documentation_version,
      generated_at: Time.current,
      git_commit: get_git_commit_hash
    }
    
    # Create documentation snapshot
    snapshot = DocumentationSnapshot.create!(
      version: version_info[:documentation_version],
      api_version: version_info[:api_version],
      content: capture_documentation_content,
      metadata: version_info,
      created_at: Time.current
    )
    
    # Generate versioned documentation files
    generate_versioned_docs(snapshot)
    
    snapshot
  end
  
  def self.compare_versions(version1, version2)
    snapshot1 = DocumentationSnapshot.find_by(version: version1)
    snapshot2 = DocumentationSnapshot.find_by(version: version2)
    
    return nil unless snapshot1 && snapshot2
    
    # Compare API changes
    api_changes = compare_api_changes(snapshot1, snapshot2)
    
    # Compare content changes
    content_changes = compare_content_changes(snapshot1, snapshot2)
    
    {
      version_from: version1,
      version_to: version2,
      api_changes: api_changes,
      content_changes: content_changes,
      breaking_changes: identify_breaking_changes(api_changes),
      migration_guide: generate_migration_guide(api_changes)
    }
  end
end
```

## Knowledge Base System

### Knowledge Base Management
```ruby
# Knowledge base article management
class KnowledgeBaseService
  include ActiveModel::Model
  
  ARTICLE_CATEGORIES = {
    getting_started: {
      title: 'Getting Started',
      description: 'Quick start guides and basic setup instructions',
      icon: '🚀',
      order: 1
    },
    api_integration: {
      title: 'API Integration',
      description: 'API usage examples and integration patterns',
      icon: '⚡',
      order: 2
    },
    troubleshooting: {
      title: 'Troubleshooting',
      description: 'Common issues and solutions',
      icon: '🔧',
      order: 3
    },
    billing_payments: {
      title: 'Billing & Payments',
      description: 'Payment processing and billing guides',
      icon: '💳',
      order: 4
    },
    security: {
      title: 'Security',
      description: 'Security implementation and best practices',
      icon: '🔒',
      order: 5
    },
    advanced_features: {
      title: 'Advanced Features',
      description: 'Advanced functionality and customization',
      icon: '⚙️',
      order: 6
    }
  }.freeze
  
  def self.create_knowledge_base_article(article_data)
    article = KbArticle.create!(
      title: article_data[:title],
      slug: generate_article_slug(article_data[:title]),
      content: article_data[:content],
      excerpt: generate_excerpt(article_data[:content]),
      category: article_data[:category],
      tags: article_data[:tags] || [],
      difficulty_level: article_data[:difficulty_level] || 'beginner',
      estimated_read_time: calculate_read_time(article_data[:content]),
      author_name: article_data[:author_name],
      status: 'published',
      seo_title: article_data[:seo_title] || article_data[:title],
      meta_description: article_data[:meta_description] || generate_excerpt(article_data[:content]),
      published_at: Time.current
    )
    
    # Generate related articles suggestions
    update_article_relationships(article)
    
    # Index for search
    index_article_for_search(article)
    
    article
  end
  
  def self.update_article_content(article_id, content_updates)
    article = KbArticle.find(article_id)
    
    # Create version history
    create_article_version(article)
    
    # Update article
    article.update!(
      content: content_updates[:content] || article.content,
      title: content_updates[:title] || article.title,
      excerpt: content_updates[:excerpt] || generate_excerpt(content_updates[:content] || article.content),
      tags: content_updates[:tags] || article.tags,
      difficulty_level: content_updates[:difficulty_level] || article.difficulty_level,
      estimated_read_time: calculate_read_time(content_updates[:content] || article.content),
      updated_at: Time.current
    )
    
    # Update search index
    update_search_index(article)
    
    article
  end
  
  def self.generate_article_templates
    templates = {
      getting_started: generate_getting_started_template,
      api_guide: generate_api_guide_template,
      troubleshooting: generate_troubleshooting_template,
      integration_guide: generate_integration_guide_template
    }
    
    templates.each do |template_type, template_content|
      ArticleTemplate.find_or_create_by(template_type: template_type) do |template|
        template.name = template_type.to_s.humanize
        template.content = template_content
        template.variables = extract_template_variables(template_content)
        template.description = "Template for #{template_type.to_s.humanize.downcase} articles"
      end
    end
    
    templates
  end
  
  private
  
  def self.generate_getting_started_template
    <<~MARKDOWN
      # {{article_title}}
      
      ## Overview
      {{overview_description}}
      
      ## Prerequisites
      - {{prerequisite_1}}
      - {{prerequisite_2}}
      
      ## Step-by-Step Guide
      
      ### Step 1: {{step_1_title}}
      {{step_1_content}}
      
      ```{{code_language}}
      {{step_1_code_example}}
      ```
      
      ### Step 2: {{step_2_title}}
      {{step_2_content}}
      
      ```{{code_language}}
      {{step_2_code_example}}
      ```
      
      ## What's Next?
      {{next_steps_content}}
      
      ## Related Articles
      - [{{related_article_1_title}}]({{related_article_1_url}})
      - [{{related_article_2_title}}]({{related_article_2_url}})
      
      ## Need Help?
      If you encounter any issues, please [contact our support team](mailto:support@powernode.com) or check our [troubleshooting guide]({{troubleshooting_url}}).
    MARKDOWN
  end
  
  def self.calculate_read_time(content)
    # Average reading speed: 200 words per minute
    word_count = content.split.size
    read_time = (word_count / 200.0).ceil
    [read_time, 1].max # Minimum 1 minute
  end
  
  def self.generate_excerpt(content, max_length = 200)
    # Remove markdown formatting and extract first paragraph
    plain_text = content.gsub(/[#*`_\[\](){}]/, '').strip
    first_paragraph = plain_text.split("\n\n").first || plain_text
    
    if first_paragraph.length <= max_length
      first_paragraph
    else
      first_paragraph[0...max_length].gsub(/\s+\S*$/, '') + '...'
    end
  end
end

# Article search and indexing
class ArticleSearchService
  include ActiveModel::Model
  
  def self.search_articles(query, filters = {})
    base_query = KbArticle.published
    
    # Text search across title and content
    if query.present?
      base_query = base_query.where(
        "title ILIKE ? OR content ILIKE ? OR tags::text ILIKE ?",
        "%#{query}%", "%#{query}%", "%#{query}%"
      )
    end
    
    # Apply category filter
    if filters[:category].present?
      base_query = base_query.where(category: filters[:category])
    end
    
    # Apply difficulty filter
    if filters[:difficulty].present?
      base_query = base_query.where(difficulty_level: filters[:difficulty])
    end
    
    # Apply tag filter
    if filters[:tags].present?
      tag_conditions = filters[:tags].map { |tag| "tags @> '[\"#{tag}\"]'" }.join(' OR ')
      base_query = base_query.where(tag_conditions)
    end
    
    # Order by relevance and popularity
    articles = base_query.order('updated_at DESC, view_count DESC')
      .limit(filters[:limit] || 20)
    
    # Track search query for analytics
    track_search_query(query, filters, articles.count)
    
    {
      query: query,
      filters: filters,
      results: articles.map { |article| serialize_article_for_search(article) },
      total_count: articles.count
    }
  end
  
  def self.get_popular_articles(category = nil, limit = 10)
    base_query = KbArticle.published
    
    if category.present?
      base_query = base_query.where(category: category)
    end
    
    base_query.order('view_count DESC, updated_at DESC').limit(limit)
  end
  
  def self.get_related_articles(article, limit = 5)
    # Find articles with similar tags or category
    related = KbArticle.published
      .where.not(id: article.id)
      .where(category: article.category)
    
    # Add tag-based similarity
    if article.tags.present?
      tag_conditions = article.tags.map { |tag| "tags @> '[\"#{tag}\"]'" }.join(' OR ')
      related = related.or(
        KbArticle.published.where.not(id: article.id).where(tag_conditions)
      )
    end
    
    related.order('updated_at DESC').limit(limit)
  end
  
  private
  
  def self.serialize_article_for_search(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      excerpt: article.excerpt,
      category: article.category,
      tags: article.tags,
      difficulty_level: article.difficulty_level,
      estimated_read_time: article.estimated_read_time,
      view_count: article.view_count,
      updated_at: article.updated_at
    }
  end
  
  def self.track_search_query(query, filters, result_count)
    SearchAnalytics.create!(
      query: query,
      filters: filters,
      result_count: result_count,
      searched_at: Time.current
    )
  end
end
```

## Developer Guide Generation

### Automated Guide Generation
```ruby
# Developer guide generator
class DeveloperGuideGenerator
  include ActiveModel::Model
  
  GUIDE_TEMPLATES = {
    quickstart: {
      title: 'Quick Start Guide',
      sections: %w[installation authentication first_request error_handling next_steps]
    },
    integration: {
      title: 'Integration Guide',
      sections: %w[overview setup authentication endpoints webhooks testing deployment]
    },
    advanced: {
      title: 'Advanced Implementation Guide',
      sections: %w[architecture patterns optimization security monitoring troubleshooting]
    }
  }.freeze
  
  def self.generate_all_guides
    guides = {}
    
    GUIDE_TEMPLATES.each do |guide_type, config|
      guides[guide_type] = generate_guide(guide_type, config)
    end
    
    # Generate language-specific guides
    generate_language_specific_guides(guides)
    
    guides
  end
  
  def self.generate_quickstart_guide
    guide_content = {
      title: 'Powernode API Quick Start Guide',
      sections: [
        generate_installation_section,
        generate_authentication_section,
        generate_first_request_section,
        generate_error_handling_section,
        generate_next_steps_section
      ]
    }
    
    # Render as markdown
    markdown_content = render_guide_as_markdown(guide_content)
    
    # Save guide file
    save_guide_file('quickstart.md', markdown_content)
    
    guide_content
  end
  
  private
  
  def self.generate_authentication_section
    {
      title: 'Authentication',
      content: <<~MARKDOWN,
        ## Authentication
        
        The Powernode API uses JWT (JSON Web Tokens) for authentication. You'll need to include your API token in the Authorization header of each request.
        
        ### Getting Your API Token
        
        1. Log in to your Powernode dashboard
        2. Navigate to Settings > API Keys
        3. Click "Generate New API Key"
        4. Copy and securely store your token
        
        ### Making Authenticated Requests
        
        Include your token in the `Authorization` header:
        
        ```http
        Authorization: Bearer YOUR_API_TOKEN
        ```
        
        ### Example Request
        
        ```bash
        curl -H "Authorization: Bearer YOUR_API_TOKEN" \\
             -H "Content-Type: application/json" \\
             https://api.powernode.com/api/v1/account
        ```
        
        ### Token Security Best Practices
        
        - Store tokens securely (environment variables, secrets manager)
        - Rotate tokens regularly
        - Use different tokens for different environments
        - Never commit tokens to version control
      MARKDOWN
      code_examples: generate_auth_code_examples
    }
  end
  
  def self.generate_first_request_section
    {
      title: 'Your First API Request',
      content: <<~MARKDOWN,
        ## Your First API Request
        
        Let's start with a simple request to get your account information.
        
        ### Account Information Request
        
        This endpoint returns basic information about your account:
        
        ```http
        GET /api/v1/account
        ```
        
        ### Response Format
        
        All API responses follow a consistent format:
        
        ```json
        {
          "success": true,
          "data": {
            "id": "account_123",
            "name": "Your Company",
            "subdomain": "yourcompany",
            "status": "active",
            "created_at": "2024-01-01T00:00:00Z"
          }
        }
        ```
        
        ### Handling Responses
        
        - Check the `success` field to determine if the request was successful
        - The `data` field contains the requested information
        - Error responses include an `error` field with details
      MARKDOWN
      code_examples: generate_first_request_examples
    }
  end
  
  def self.generate_auth_code_examples
    {
      curl: <<~BASH,
        # Store your token in an environment variable
        export POWERNODE_API_TOKEN="your_api_token_here"
        
        # Make authenticated request
        curl -H "Authorization: Bearer $POWERNODE_API_TOKEN" \\
             https://api.powernode.com/api/v1/account
      BASH
      javascript: <<~JAVASCRIPT,
        const apiToken = process.env.POWERNODE_API_TOKEN;
        
        const response = await fetch('https://api.powernode.com/api/v1/account', {
          method: 'GET',
          headers: {
            'Authorization': `Bearer ${apiToken}`,
            'Content-Type': 'application/json'
          }
        });
        
        const data = await response.json();
        console.log(data);
      JAVASCRIPT
      python: <<~PYTHON
        import os
        import requests
        
        api_token = os.getenv('POWERNODE_API_TOKEN')
        
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
        
        response = requests.get('https://api.powernode.com/api/v1/account', headers=headers)
        data = response.json()
        print(data)
      PYTHON
    }
  end
  
  def self.render_guide_as_markdown(guide_content)
    markdown = "# #{guide_content[:title]}\n\n"
    
    guide_content[:sections].each do |section|
      markdown += section[:content]
      
      if section[:code_examples]
        section[:code_examples].each do |language, code|
          markdown += "\n#### #{language.to_s.capitalize}\n\n"
          markdown += "```#{language}\n#{code}\n```\n\n"
        end
      end
      
      markdown += "\n---\n\n"
    end
    
    markdown
  end
  
  def self.save_guide_file(filename, content)
    guides_dir = Rails.root.join('public', 'docs', 'guides')
    FileUtils.mkdir_p(guides_dir)
    
    File.write(guides_dir.join(filename), content)
  end
end

# SDK documentation generator
class SdkDocumentationGenerator
  include ActiveModel::Model
  
  SUPPORTED_LANGUAGES = {
    javascript: {
      name: 'JavaScript/Node.js',
      package_name: '@powernode/api-client',
      repository: 'https://github.com/powernode/javascript-sdk'
    },
    python: {
      name: 'Python',
      package_name: 'powernode-api',
      repository: 'https://github.com/powernode/python-sdk'
    },
    ruby: {
      name: 'Ruby',
      package_name: 'powernode',
      repository: 'https://github.com/powernode/ruby-sdk'
    },
    php: {
      name: 'PHP',
      package_name: 'powernode/api-client',
      repository: 'https://github.com/powernode/php-sdk'
    }
  }.freeze
  
  def self.generate_sdk_documentation
    sdk_docs = {}
    
    SUPPORTED_LANGUAGES.each do |language, config|
      sdk_docs[language] = generate_language_sdk_doc(language, config)
    end
    
    # Generate SDK comparison guide
    generate_sdk_comparison_guide(sdk_docs)
    
    sdk_docs
  end
  
  private
  
  def self.generate_language_sdk_doc(language, config)
    {
      language: language,
      name: config[:name],
      package_name: config[:package_name],
      repository: config[:repository],
      installation: generate_installation_instructions(language, config),
      quickstart: generate_sdk_quickstart(language, config),
      api_reference: generate_sdk_api_reference(language),
      examples: generate_sdk_examples(language),
      error_handling: generate_sdk_error_handling(language),
      advanced_usage: generate_sdk_advanced_usage(language)
    }
  end
  
  def self.generate_installation_instructions(language, config)
    case language
    when :javascript
      {
        npm: "npm install #{config[:package_name]}",
        yarn: "yarn add #{config[:package_name]}",
        cdn: "<script src=\"https://cdn.powernode.com/js/api-client.min.js\"></script>"
      }
    when :python
      {
        pip: "pip install #{config[:package_name]}",
        poetry: "poetry add #{config[:package_name]}",
        requirements: "#{config[:package_name]}>=1.0.0"
      }
    when :ruby
      {
        gem: "gem install #{config[:package_name]}",
        gemfile: "gem '#{config[:package_name]}', '~> 1.0'"
      }
    when :php
      {
        composer: "composer require #{config[:package_name]}"
      }
    end
  end
end
```

## Documentation Analytics & Maintenance

### Documentation Analytics System
```ruby
# Documentation analytics and insights
class DocumentationAnalyticsService
  include ActiveModel::Model
  
  def self.generate_analytics_report(start_date, end_date)
    report_data = {
      period: { start: start_date, end: end_date },
      article_performance: analyze_article_performance(start_date, end_date),
      search_analytics: analyze_search_patterns(start_date, end_date),
      user_engagement: analyze_user_engagement(start_date, end_date),
      content_gaps: identify_content_gaps,
      recommendations: generate_content_recommendations
    }
    
    # Store analytics report
    DocumentationAnalyticsReport.create!(
      report_data: report_data,
      report_period_start: start_date,
      report_period_end: end_date,
      generated_at: Time.current
    )
    
    report_data
  end
  
  def self.track_article_view(article_id, user_info = {})
    article = KbArticle.find(article_id)
    
    # Increment view count
    article.increment!(:view_count)
    
    # Track detailed view analytics
    ArticleView.create!(
      kb_article_id: article_id,
      user_id: user_info[:user_id],
      session_id: user_info[:session_id],
      ip_address: user_info[:ip_address],
      user_agent: user_info[:user_agent],
      referrer: user_info[:referrer],
      time_on_page: user_info[:time_on_page],
      scroll_depth: user_info[:scroll_depth],
      viewed_at: Time.current
    )
  end
  
  def self.track_documentation_feedback(article_id, feedback_data)
    DocumentationFeedback.create!(
      kb_article_id: article_id,
      rating: feedback_data[:rating],
      feedback_type: feedback_data[:type], # helpful, not_helpful, suggestion
      comment: feedback_data[:comment],
      user_email: feedback_data[:email],
      created_at: Time.current
    )
    
    # Update article rating
    update_article_rating(article_id)
  end
  
  private
  
  def self.analyze_article_performance(start_date, end_date)
    views = ArticleView.where(viewed_at: start_date..end_date)
    
    {
      total_views: views.count,
      unique_visitors: views.distinct.count(:session_id),
      most_viewed_articles: views.group(:kb_article_id)
        .order('count_all desc')
        .limit(10)
        .count
        .map { |article_id, view_count|
          article = KbArticle.find(article_id)
          { id: article_id, title: article.title, views: view_count }
        },
      average_time_on_page: views.average(:time_on_page)&.round(2),
      bounce_rate: calculate_bounce_rate(views),
      conversion_metrics: calculate_conversion_metrics(views)
    }
  end
  
  def self.analyze_search_patterns(start_date, end_date)
    searches = SearchAnalytics.where(searched_at: start_date..end_date)
    
    {
      total_searches: searches.count,
      unique_queries: searches.distinct.count(:query),
      top_search_terms: searches.group(:query)
        .order('count_all desc')
        .limit(20)
        .count,
      no_result_searches: searches.where(result_count: 0)
        .group(:query)
        .count,
      average_results_per_search: searches.average(:result_count)&.round(2)
    }
  end
  
  def self.identify_content_gaps
    # Analyze search queries with no results
    no_result_queries = SearchAnalytics.where(result_count: 0)
      .group(:query)
      .having('count(*) > 5') # Queries searched multiple times
      .count
    
    # Analyze low-performing articles
    low_rating_articles = KbArticle.where('average_rating < 3.0 OR average_rating IS NULL')
      .where('view_count > 10') # Only consider articles with some traffic
    
    # Analyze categories with few articles
    category_counts = KbArticle.group(:category).count
    under_represented_categories = ARTICLE_CATEGORIES.keys.select do |category|
      (category_counts[category.to_s] || 0) < 3
    end
    
    {
      missing_content_queries: no_result_queries,
      low_performing_articles: low_rating_articles.map do |article|
        {
          id: article.id,
          title: article.title,
          rating: article.average_rating,
          views: article.view_count
        }
      end,
      under_represented_categories: under_represented_categories
    }
  end
  
  def self.generate_content_recommendations
    recommendations = []
    
    # Recommend articles for popular search terms with no results
    no_result_queries = SearchAnalytics.where(result_count: 0)
      .group(:query)
      .having('count(*) > 3')
      .order('count_all desc')
      .limit(10)
      .pluck(:query)
    
    no_result_queries.each do |query|
      recommendations << {
        type: 'create_article',
        priority: 'high',
        suggestion: "Create article for '#{query}'",
        estimated_impact: 'high'
      }
    end
    
    # Recommend updates for low-rated articles
    low_rated_articles = KbArticle.where('average_rating < 3.0 AND view_count > 50')
    
    low_rated_articles.each do |article|
      recommendations << {
        type: 'update_article',
        priority: 'medium',
        article_id: article.id,
        suggestion: "Update article '#{article.title}' (rating: #{article.average_rating})",
        estimated_impact: 'medium'
      }
    end
    
    recommendations
  end
end

# Documentation maintenance automation
class DocumentationMaintenanceService
  include ActiveModel::Model
  
  def self.run_maintenance_tasks
    maintenance_results = {
      link_validation: validate_all_links,
      content_freshness: check_content_freshness,
      broken_references: find_broken_references,
      optimization_suggestions: generate_optimization_suggestions
    }
    
    # Create maintenance report
    DocumentationMaintenanceReport.create!(
      maintenance_results: maintenance_results,
      performed_at: Time.current
    )
    
    # Send alerts for critical issues
    send_maintenance_alerts(maintenance_results)
    
    maintenance_results
  end
  
  private
  
  def self.validate_all_links
    broken_links = []
    
    KbArticle.published.find_each do |article|
      links = extract_links_from_content(article.content)
      
      links.each do |link|
        unless link_valid?(link)
          broken_links << {
            article_id: article.id,
            article_title: article.title,
            broken_link: link
          }
        end
      end
    end
    
    broken_links
  end
  
  def self.check_content_freshness
    stale_articles = KbArticle.published
      .where('updated_at < ?', 6.months.ago)
      .where('view_count > 100') # Only check popular articles
    
    stale_articles.map do |article|
      {
        id: article.id,
        title: article.title,
        last_updated: article.updated_at,
        view_count: article.view_count,
        staleness_score: calculate_staleness_score(article)
      }
    end
  end
  
  def self.link_valid?(url)
    uri = URI.parse(url)
    return false unless %w[http https].include?(uri.scheme)
    
    begin
      response = Net::HTTP.get_response(uri)
      response.code.start_with?('2') || response.code.start_with?('3')
    rescue => e
      Rails.logger.warn "Link validation failed for #{url}: #{e.message}"
      false
    end
  end
end
```

## Development Commands

### Documentation Generation
```bash
# API documentation
cd server && rails runner "ApiDocumentationService.generate_comprehensive_docs"  # Generate API docs
cd server && rake swagger:docs                                                   # Generate Swagger docs

# Knowledge base
cd server && rails runner "KnowledgeBaseService.generate_article_templates"     # Create article templates
cd server && rails runner "ArticleSearchService.rebuild_search_index"          # Rebuild search index

# Developer guides
cd server && rails runner "DeveloperGuideGenerator.generate_all_guides"         # Generate all guides
cd server && rails runner "SdkDocumentationGenerator.generate_sdk_documentation" # Generate SDK docs

# Documentation platform
cd server && rails runner "DocumentationPlatformService.build_documentation_site" # Build static site
```

### Analytics & Maintenance
```bash
# Analytics
cd server && rails runner "DocumentationAnalyticsService.generate_analytics_report(30.days.ago, Time.current)"

# Maintenance
cd server && rails runner "DocumentationMaintenanceService.run_maintenance_tasks"  # Run maintenance
cd server && rails runner "DocumentationVersionManager.create_version_snapshot"    # Create version snapshot

# Content management
cd server && rails runner "KbArticle.where('average_rating < 3.0').each { |a| puts a.title }"  # Find low-rated articles
```

### Content Creation Helpers
```bash
# Create article from template
cd server && rails runner "KnowledgeBaseService.create_article_from_template('quickstart', { title: 'Getting Started with Webhooks' })"

# Bulk import articles
cd server && rails runner "ContentImporter.import_articles_from_directory('docs/import/')"

# Generate code examples
cd server && rails runner "CodeExampleGenerator.generate_examples_for_endpoint('/api/v1/subscriptions', 'POST')"
```

## Integration Points

### Platform Architect Coordination
- **Documentation Architecture**: Design comprehensive documentation system structure
- **API Documentation Strategy**: Coordinate API documentation with overall architecture
- **Integration Planning**: Document all system integrations and architectural decisions
- **Version Management**: Manage documentation versioning alongside system releases

### API Developer Integration
- **Endpoint Documentation**: Automatically generate documentation from API controllers
- **Request/Response Examples**: Create realistic examples using actual API data
- **Error Documentation**: Document all error codes and response formats
- **Integration Testing**: Validate documentation examples against actual API

### Frontend/Backend Specialist Integration
- **Feature Documentation**: Document new features as they're implemented
- **Code Examples**: Generate code examples in multiple programming languages
- **UI Documentation**: Document frontend components and user interfaces
- **Implementation Guides**: Create step-by-step implementation documentation

### DevOps Engineer Coordination
- **Deployment Documentation**: Document deployment processes and infrastructure
- **Environment Setup**: Create environment-specific setup and configuration guides
- **Monitoring Documentation**: Document monitoring and alerting configurations
- **Troubleshooting Guides**: Create operational troubleshooting documentation

## Quick Reference

### Documentation Standards
```markdown
# Article Structure Standards
1. Clear, descriptive title
2. Brief overview/introduction
3. Prerequisites section
4. Step-by-step instructions
5. Code examples (multiple languages)
6. Common issues/troubleshooting
7. Related articles/next steps
8. Contact information

# Code Example Standards
- Always include complete, runnable examples
- Use realistic data in examples
- Include error handling
- Provide examples in multiple languages
- Test all code examples regularly
```

### Essential Commands
```bash
# Quick documentation tasks
rails runner "ApiDocumentationService.generate_endpoint_docs"      # Generate API docs
rails runner "KnowledgeBaseService.create_knowledge_base_article"  # Create KB article
rails runner "DocumentationAnalyticsService.track_article_view"    # Track analytics

# Maintenance tasks
rails runner "DocumentationMaintenanceService.validate_all_links"  # Check links
rails runner "DocumentationVersionManager.create_version_snapshot" # Version snapshot
```

### Documentation Metrics
- **Article Performance**: Views, ratings, time on page, bounce rate
- **Search Analytics**: Query volume, success rate, popular terms
- **User Engagement**: Feedback ratings, comments, suggestions
- **Content Health**: Link validity, content freshness, coverage gaps
- **API Documentation**: Endpoint coverage, example accuracy, version currency

## Quick Reference

### Essential Documentation Commands
```bash
# Documentation generation - run from $POWERNODE_ROOT/server
cd $POWERNODE_ROOT/server && rails docs:generate                    # Generate API docs
cd $POWERNODE_ROOT/server && rails docs:validate                    # Validate documentation
cd $POWERNODE_ROOT/server && rails docs:update_examples            # Update code examples

# Knowledge base management
cd $POWERNODE_ROOT/server && rails kb:sync                         # Sync knowledge base
cd $POWERNODE_ROOT/server && rails kb:validate_links              # Check for broken links
cd $POWERNODE_ROOT/server && rails kb:update_search_index         # Update search index

# Documentation deployment
cd $POWERNODE_ROOT && ./scripts/deploy-docs.sh staging            # Deploy to staging
cd $POWERNODE_ROOT && ./scripts/deploy-docs.sh production         # Deploy to production
```

### Documentation Structure
- **API Documentation**: `/docs/api/` - OpenAPI specs, endpoint documentation
- **User Guides**: `/docs/users/` - Getting started, tutorials, how-to guides
- **Developer Guides**: `/docs/developers/` - Integration guides, code examples
- **Knowledge Base**: `/docs/kb/` - FAQ, troubleshooting, best practices
- **Release Notes**: `/docs/releases/` - Changelog, migration guides

### Content Management Tools
```bash
# Content validation
markdownlint docs/**/*.md                                         # Lint markdown files
vale docs/                                                        # Style and grammar check
linkchecker http://localhost:3001/docs                           # Check external links

# Content generation
cd $POWERNODE_ROOT/server && rails generate:api_docs              # Auto-generate API docs
cd $POWERNODE_ROOT/server && rails generate:changelog             # Generate changelog
```

### Quality Standards
- **Readability**: Flesch Reading Ease score > 60
- **Completeness**: All API endpoints documented with examples
- **Accuracy**: Code examples tested and validated
- **Freshness**: Content updated within 30 days of related code changes
- **Accessibility**: Alt text for images, proper heading structure

### Emergency Procedures
- **Documentation Site Down**: Check deployment status, verify DNS, restart services
- **Search Not Working**: Rebuild search index, check Elasticsearch connection
- **Broken Links**: Run link checker, update outdated URLs, verify external services
- **Missing Content**: Check content pipeline, verify auto-generation scripts
- **Style Violations**: Run linting tools, fix formatting, update style guide

**ALWAYS REFERENCE TODO.md FOR CURRENT TASKS AND PRIORITIES**
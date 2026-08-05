# frozen_string_literal: true

module Ai
  module Tools
    class KbArticleManagementTool < BaseTool
      REQUIRED_PERMISSION = "kb.manage"

      # Crossing the `published` boundary is a separate act from editing, and
      # carries its own permission on the human path — see #publication_allowed?.
      PUBLISH_PERMISSION = "kb.publish"

      def self.definition
        {
          name: "kb_article_management",
          description: "List, get, create, or update Knowledge Base articles",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_kb_articles, get_kb_article, create_kb_article, update_kb_article" },
            article_id: { type: "string", required: false, description: "Article ID (for get/update)" },
            slug: { type: "string", required: false, description: "Article slug (alternative to ID for get)" },
            category_slug: { type: "string", required: false, description: "Category slug (for list/create)" },
            status: { type: "string", required: false, description: "Filter by status or set status (draft/review/published/archived)" },
            title: { type: "string", required: false, description: "Article title (for create/update)" },
            content: { type: "string", required: false, description: "Article content in markdown (for create/update)" },
            excerpt: { type: "string", required: false, description: "Article excerpt (for create/update)" },
            is_featured: { type: "boolean", required: false, description: "Featured flag (for create/update)" },
            tags: { type: "array", required: false, description: "Tag names (for create/update)" }
          }
        }
      end

      def self.action_definitions
        {
          "list_kb_articles" => {
            description: "List Knowledge Base articles with optional category and status filters",
            parameters: {
              category_slug: { type: "string", required: false, description: "Filter by category slug" },
              status: { type: "string", required: false, description: "Filter by status (draft/review/published/archived)" }
            }
          },
          "get_kb_article" => {
            description: "Get a Knowledge Base article by ID or slug",
            parameters: {
              article_id: { type: "string", required: false, description: "Article ID" },
              slug: { type: "string", required: false, description: "Article slug (alternative to ID)" }
            }
          },
          "create_kb_article" => {
            description: "Create a new Knowledge Base article in a category",
            parameters: {
              title: { type: "string", required: true, description: "Article title" },
              content: { type: "string", required: true, description: "Article content in markdown" },
              category_slug: { type: "string", required: true, description: "Category slug" },
              status: { type: "string", required: false, description: "Status (default: draft)" },
              excerpt: { type: "string", required: false, description: "Article excerpt" },
              is_featured: { type: "boolean", required: false, description: "Featured flag" },
              tags: { type: "array", required: false, description: "Tag names" }
            }
          },
          "update_kb_article" => {
            description: "Update an existing Knowledge Base article",
            parameters: {
              article_id: { type: "string", required: true, description: "Article ID" },
              title: { type: "string", required: false, description: "New article title" },
              content: { type: "string", required: false, description: "New article content" },
              excerpt: { type: "string", required: false, description: "New article excerpt" },
              status: { type: "string", required: false, description: "New status" },
              is_featured: { type: "boolean", required: false, description: "Featured flag" },
              tags: { type: "array", required: false, description: "Tag names" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "list_kb_articles" then list_articles(params)
        when "get_kb_article" then get_article(params)
        when "create_kb_article" then create_article(params)
        when "update_kb_article" then update_article(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def list_articles(params)
        # Override-aware: GLOBAL (platform-provided) articles plus the account's
        # own — never another tenant's private articles.
        scope = ::KnowledgeBase::Article.for_account(account.id)
        scope = scope.where(category: find_category(params[:category_slug])) if params[:category_slug].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        articles = scope.order(updated_at: :desc).limit(50)
        {
          success: true,
          articles: articles.map { |a| serialize_article_summary(a) }
        }
      end

      def get_article(params)
        article = find_article(params)
        return { success: false, error: "Article not found" } unless article

        { success: true, article: serialize_article_full(article) }
      end

      def create_article(params)
        category = find_category(params[:category_slug])
        return { success: false, error: "Category not found: #{params[:category_slug]}" } unless category

        status = params[:status] || "draft"
        # Refuse BEFORE the transaction opens: nothing is written, so there is no
        # half-created article and no workflow row for a transition that did not
        # happen.
        unless publication_transition_allowed?(nil, status)
          return publication_denied_result(nil, status)
        end

        article = nil

        ActiveRecord::Base.transaction do
          article = ::KnowledgeBase::Article.create!(
            title: params[:title],
            content: params[:content],
            category: category,
            author: resolved_author,
            status: status,
            excerpt: params[:excerpt],
            is_featured: params[:is_featured] || false,
            is_public: true,
            views_count: 0,
            likes_count: 0,
            sort_order: 0
          )

          if params[:tags].present?
            article.tag_names = Array(params[:tags])
          end

          # A create that lands straight in `published` stays a `create` row —
          # one event happened, not two. "Who published this" is answered across
          # both shapes by the to_status index, not by the action.
          record_article_workflow!(
            article,
            action: "create",
            from_status: nil,
            to_status: article.status
          )
        end

        { success: true, article_id: article.id, slug: article.slug, title: article.title }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def update_article(params)
        article = find_article(params)
        return { success: false, error: "Article not found" } unless article

        attrs = {}
        attrs[:title] = params[:title] if params[:title].present?
        attrs[:content] = params[:content] if params[:content].present?
        attrs[:excerpt] = params[:excerpt] if params[:excerpt].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:is_featured] = params[:is_featured] unless params[:is_featured].nil?

        from_status = article.status
        to_status = attrs[:status] || from_status

        # Refuse the whole call, not just the status: a publish that rides along
        # with a title change must not land the title either, or the caller gets
        # a partial success it never asked for. Placed before the transaction so
        # no article change and no workflow row is written.
        unless publication_transition_allowed?(from_status, to_status)
          return publication_denied_result(from_status, to_status)
        end

        ActiveRecord::Base.transaction do
          article.update!(attrs)

          # Read the summary before tag assignment resets saved_changes.
          summary = ::KnowledgeBase::Workflow.change_summary(article)
          article.tag_names = Array(params[:tags]) if params[:tags].present?

          record_article_workflow!(
            article,
            action: ::KnowledgeBase::Workflow.action_for(from_status, article.status),
            from_status: from_status,
            to_status: article.status,
            comment: summary
          )
        end

        { success: true, article_id: article.id, slug: article.slug }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      # === Publication gating ===
      #
      # Publishing is not an ordinary attribute write. On the human path
      # Api::V1::Kb::ArticlesController gates #publish and #unpublish behind
      # kb.publish (articles_controller.rb:10) — a deliberate distinction from
      # editing, which only needs kb.update. This tool used to pass `status`
      # straight through to create!/update!, so any principal that could reach
      # it could publish without holding kb.publish and without traversing the
      # gated endpoints.
      #
      # It matters beyond permission tidiness because publishing is what makes
      # content visible to OTHER agents: Mcp::NativeResourceProvider serves
      # `.published` articles as MCP resources by slug
      # (native_resource_provider.rb:88, :105, :176). Ungated, an agent could
      # promote its own writing into the corpus the rest of the fleet reads as
      # context.
      #
      # Gated in BOTH directions, following the controller's own pairing of
      # publish with unpublish: entering `published` grants that visibility and
      # leaving it (to draft, review, or archived) revokes it, and an agent that
      # can pull an article the fleet reads is the same authority in reverse.
      # Transitions that never touch `published` (draft -> review, draft ->
      # archived, and back) stay open — they change no one's visibility, the
      # human path lets kb.update make them, and `review` is precisely the safe
      # parking state an agent should be able to reach on its own.
      def publication_transition_allowed?(from_status, to_status)
        return true unless crosses_publication_boundary?(from_status, to_status)

        publication_allowed?
      end

      # A move is only interesting here if it enters or leaves `published`.
      # A no-op restatement of the current status is not a transition at all.
      def crosses_publication_boundary?(from_status, to_status)
        return false if from_status.to_s == to_status.to_s

        from_status.to_s == "published" || to_status.to_s == "published"
      end

      # Two bypasses, both EXPLICIT, mirroring the ladder the tools hardened in
      # this campaign use (SystemFleetTool IMP-9030413bc292 carries the full
      # note; SystemAcmeTool / SystemStorageOwnerTool repeat it):
      #
      #   internal?            in-process system callers (seeds, reconcilers,
      #                        skill executors running without a user) that
      #                        opted in with `internal: true`.
      #   instance_authorized? an MCP instance principal (mTLS node cert, no
      #                        User) whose specific tool name already cleared
      #                        Mcp::Principal#may_invoke?. NAME-scoped only:
      #                        the grant is on `create_kb_article` /
      #                        `update_kb_article`, which cannot express "drafts
      #                        only", so it is provenance rather than a fence.
      #
      # A nil user with NEITHER flag fails CLOSED — that is the agent principal
      # this fix is about. Inferring "trusted" from `user.nil?` is exactly the
      # mistake IMP-9030413bc292 removed elsewhere; an agent must not satisfy a
      # permission check by having no user to check.
      #
      # kb.manage is deliberately NOT accepted here, though the controller's
      # can_publish_kb? accepts it: kb.manage is this tool's own
      # REQUIRED_PERMISSION, so honouring it would make the check vacuous for
      # every caller able to reach this code. Its catalog definition is
      # "Manage knowledge base categories and settings" (config/permissions.rb:63),
      # not a publish superset, and every shipped role granting kb.manage also
      # grants kb.publish explicitly (config/permissions.rb:758, :859, :878), so
      # requiring the specific permission costs no shipped role its access.
      def publication_allowed?
        return true if internal?
        return true if instance_authorized?
        return false if user.nil?
        return true unless user.respond_to?(:has_permission?)

        user.has_permission?(PUBLISH_PERMISSION)
      end

      def publication_denied_result(from_status, to_status)
        transition = from_status.present? ? "#{from_status} -> #{to_status}" : to_status.to_s

        {
          success: false,
          error: "Not authorized: changing article status (#{transition}) crosses the " \
                 "published boundary and requires the #{PUBLISH_PERMISSION} permission"
        }
      end

      # Records an article state transition, blocking like the controller does:
      # a bare create! inside the caller's transaction, so a transition that
      # cannot be recorded is rolled back. The surrounding
      # `rescue ActiveRecord::RecordInvalid` then reports it to the agent as a
      # failed call rather than a silent partial success.
      def record_article_workflow!(article, action:, from_status:, to_status:, comment: nil, metadata: {})
        principal, attribution = workflow_principal(article)

        # No principal resolved inside the account, so there is nobody this row
        # could name without naming someone else's user. Refuse the transition
        # rather than write a false one: raised as RecordInvalid so it travels
        # the path every unwritable row already takes here — the transaction
        # rolls back and the caller is told the call failed, never a silent
        # partial success.
        if principal.nil?
          unattributable = ::KnowledgeBase::Workflow.new(
            article: article, action: action, from_status: from_status, to_status: to_status
          )
          unattributable.errors.add(
            :user,
            "cannot be resolved within this account, so the transition has no actor to record"
          )
          raise ActiveRecord::RecordInvalid, unattributable
        end

        ::KnowledgeBase::Workflow.create!(
          article: article,
          user: principal,
          action: action,
          from_status: from_status,
          to_status: to_status,
          comment: comment,
          metadata: metadata.merge(
            source: "ai_tool",
            tool: self.class.tool_name,
            agent_id: agent&.id,
            agent_name: agent&.name,
            attribution: attribution
          ).compact
        )
      end

      # knowledge_base_workflows.user_id is NOT NULL, so every row needs a
      # principal — but an agent-driven call frequently has no acting user
      # (BaseTool#user is nil for both agent and instance principals) and the
      # seeded GLOBAL articles are deliberately authorless (db/seeds/kb/*.rb set
      # author_id = nil on 53 of them). The chain returns which link was used so
      # `metadata.attribution` records it: the row never claims a fallback user
      # performed the action, and `metadata.agent_id` carries the actor the
      # column cannot express.
      #
      # EVERY link is scoped to `account`, including `article.author`. That link
      # is not safe by construction: #find_article is override-aware, so a
      # GLOBAL article (account_id nil) is reachable from every tenant, and its
      # author is routinely a user of some other one. Since IMP-78ae82f1deda
      # this row IS the article-transition audit trail, and user_id is the
      # column a reader trusts to answer "who moved this article" — a row
      # asserting that account A's user acted in account B is worse than a
      # missing row, because it is a false statement in the record whose whole
      # purpose is attribution. A foreign candidate is therefore skipped, not
      # accepted, and the chain ends at nil rather than reaching outside.
      def workflow_principal(article)
        acting = in_account(user)
        return [ acting, "acting_user" ] if acting

        author = in_account(article.author)
        return [ author, "article_author" ] if author

        fallback = account_principal
        return [ fallback, "fallback_account_principal" ] if fallback

        [ nil, nil ]
      end

      # The author of an article this tool creates: the acting user when there
      # is one, mirroring the human path (Api::V1::Kb::ArticlesController#create
      # sets `article.author = current_user`), and otherwise the account's own
      # principal. Never an identity from outside the account — an author is a
      # claim about who wrote the article, and naming another tenant's user is
      # simply untrue.
      def resolved_author
        in_account(user) || account_principal
      end

      # The account's own responsible identity, for a call that legitimately has
      # no acting user. Its OWNER — the party accountable for what agents in the
      # account do — falling back to the account's earliest user for an account
      # whose owner role was never assigned. Deliberately NOT an address in
      # source: the platform is DB-driven and multi-tenant, a self-hosted
      # core-mode install has no reference admin account at all, and a literal
      # cannot be scoped to the caller. Nil when the account has no users, which
      # #record_article_workflow! turns into a refusal.
      def account_principal
        return nil if account.nil?

        @account_principal ||= account.owner || account.users.order(:created_at, :id).first
      end

      # A candidate identity, but only when it belongs to THIS account.
      def in_account(candidate)
        return nil if candidate.nil? || account.nil?

        candidate.account_id == account.id ? candidate : nil
      end

      def find_article(params)
        scope = ::KnowledgeBase::Article.for_account(account.id)
        if params[:article_id].present?
          scope.find_by(id: params[:article_id])
        elsif params[:slug].present?
          scope.find_by(slug: params[:slug])
        end
      end

      def find_category(slug)
        return nil unless slug.present?
        ::KnowledgeBase::Category.find_by(slug: slug)
      end

      def serialize_article_summary(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          category: article.category&.name,
          is_featured: article.is_featured,
          updated_at: article.updated_at&.iso8601
        }
      end

      def serialize_article_full(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          content: article.content,
          excerpt: article.excerpt,
          category: article.category&.name,
          category_slug: article.category&.slug,
          author: article.author&.email,
          is_featured: article.is_featured,
          is_public: article.is_public,
          tags: article.tag_names,
          views_count: article.views_count,
          published_at: article.published_at&.iso8601,
          created_at: article.created_at&.iso8601,
          updated_at: article.updated_at&.iso8601
        }
      end
    end
  end
end

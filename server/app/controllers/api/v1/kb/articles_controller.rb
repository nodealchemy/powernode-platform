# frozen_string_literal: true

class Api::V1::Kb::ArticlesController < ApplicationController
  include Paginatable
  skip_before_action :authenticate_request, only: [ :index, :show, :search ]
  # Try to authenticate if token provided (allows viewing drafts for editors)
  before_action :authenticate_optional, only: [ :index, :show, :search ]
  before_action :set_article, only: [ :show, :update, :destroy, :publish, :unpublish ]
  before_action :authorize_kb_edit, only: [ :create, :update, :destroy, :bulk_update, :bulk_delete ]
  before_action :authorize_kb_publish, only: [ :publish, :unpublish ]
  before_action :authorize_kb_manage, only: [ :analytics ]

  # GET /api/v1/kb/articles
  def index
    # Check if admin view was explicitly requested
    admin_requested = params[:admin] == "true" || params[:edit] == "true" || request.path.include?("/admin")

    if admin_requested
      # Admin view was explicitly requested - check permission
      return render_error("Access denied", status: :forbidden) unless can_edit_kb?

      # Admin view with all articles for editing — tenancy-scoped so an account
      # sees only global rows + its own private rows, never another tenant's.
      articles = tenant_scoped_articles.includes(:author, :category, :tags)
      articles = apply_admin_filters(articles)
      articles = articles.page(params[:page]).per(params[:per_page] || 20)

      render_success({
        articles: articles.map { |article| serialize_article_admin(article) },
        pagination: pagination_meta(articles),
        stats: calculate_article_stats
      })
    else
      # Public view with only published articles — tenancy-scoped: authenticated
      # users see global + their own; unauthenticated requests see globals only.
      articles = tenant_scoped_articles.published.public_articles
      articles = apply_filters(articles)
      articles = articles.includes(:author, :category, :tags).page(params[:page]).per(params[:per_page] || 20)

      render_success({
        articles: articles.map { |article| serialize_article_summary(article) },
        pagination: pagination_meta(articles)
      })
    end
  end

  # GET /api/v1/kb/articles/:id
  def show
    return render_error("Article not found", status: :not_found) unless @article

    # Check access permissions
    if editing_mode?
      # Admin view - can see any article if has edit permissions
      return render_error("Access denied", status: :forbidden) unless can_edit_kb?

      render_success({
        article: serialize_article_detailed(@article)
      })
    else
      # Public view - check if article is viewable
      return render_error("Access denied", status: :forbidden) unless @article.viewable_by?(current_user)

      # Record view with tracking (no session in API-only mode)
      @article.record_view!(
        user: current_user,
        session_id: SecureRandom.hex(16), # Generate unique session identifier for tracking
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      render_success({
        article: serialize_article_full(@article),
        related_articles: @article.related_articles.map { |article| serialize_article_summary(article) }
      })
    end
  end

  # POST /api/v1/kb/articles
  def create
    article = KnowledgeBase::Article.new(article_params)
    article.author = current_user
    # Tenant-private by default: stamp the creating account so the article is
    # owned by + visible only within it (globals are seed/platform-managed only).
    article.account = current_account

    created = ActiveRecord::Base.transaction do
      next false unless article.save

      handle_tag_assignment(article) if params[:article][:tag_names].present?
      record_article_workflow!(
        article,
        action: "create",
        from_status: nil,
        to_status: article.status
      )
      true
    end

    if created
      render_success(
        article: serialize_article_admin(article.reload)
      )
    else
      render_validation_error(article)
    end
  end

  # PATCH /api/v1/kb/articles/:id
  def update
    return render_error("Article not found", status: :not_found) unless @article
    return render_error("Access denied", status: :forbidden) unless @article.editable_by?(current_user)

    from_status = @article.status

    # Refuse BEFORE the transaction opens, so a denied publish leaves no
    # article change and no audit row. (IMP-e32f500cdd88)
    unless publication_change_allowed?(from_status, article_params[:status])
      return render_error(publication_denied_message(from_status, article_params[:status]),
                          status: :forbidden)
    end

    updated = ActiveRecord::Base.transaction do
      next false unless @article.update(article_params)

      # Read the change summary before tag assignment: its save resets
      # saved_changes on the same instance.
      summary = KnowledgeBase::Workflow.change_summary(@article)
      handle_tag_assignment(@article) if params[:article][:tag_names].present?
      record_article_workflow!(
        @article,
        action: KnowledgeBase::Workflow.action_for(from_status, @article.status),
        from_status: from_status,
        to_status: @article.status,
        comment: summary
      )
      true
    end

    if updated
      render_success(
        article: serialize_article_admin(@article.reload)
      )
    else
      render_validation_error(@article)
    end
  end

  # DELETE /api/v1/kb/articles/:id
  def destroy
    return render_error("Article not found", status: :not_found) unless @article
    return render_error("Access denied", status: :forbidden) unless @article.editable_by?(current_user)

    snapshot = article_deletion_snapshot(@article)
    destroyed = @article.destroy
    record_article_deletion!(snapshot) if destroyed

    render_success(message: "Article deleted successfully")
  end

  # POST /api/v1/kb/articles/:id/publish
  def publish
    return render_error("Article not found", status: :not_found) unless @article

    from_status = @article.status

    published = ActiveRecord::Base.transaction do
      next false unless @article.update(status: "published", published_at: Time.current)

      record_article_workflow!(
        @article,
        action: "publish",
        from_status: from_status,
        to_status: @article.status,
        metadata: { published_at: @article.published_at&.iso8601 }
      )
      true
    end

    if published
      render_success(
        article: serialize_article_admin(@article)
      )
    else
      render_validation_error(@article)
    end
  end

  # POST /api/v1/kb/articles/:id/unpublish
  def unpublish
    return render_error("Article not found", status: :not_found) unless @article

    from_status = @article.status
    # published_at is about to be cleared, so the only record of when this
    # article was live is the one written here.
    was_published_at = @article.published_at

    unpublished = ActiveRecord::Base.transaction do
      next false unless @article.update(status: "draft", published_at: nil)

      record_article_workflow!(
        @article,
        action: "unpublish",
        from_status: from_status,
        to_status: @article.status,
        metadata: { was_published_at: was_published_at&.iso8601 }
      )
      true
    end

    if unpublished
      render_success(
        article: serialize_article_admin(@article)
      )
    else
      render_validation_error(@article)
    end
  end

  # GET /api/v1/kb/articles/search
  def search
    query = params[:q]
    return render_error("Search query is required", status: :bad_request) if query.blank?

    articles = tenant_scoped_articles.published.public_articles
    articles = articles.search_by_text(query) if query.present?
    articles = apply_filters(articles)
    articles = articles.includes(:author, :category, :tags).page(params[:page]).per(params[:per_page] || 20)

    render_success({
      query: query,
      articles: articles.map { |article| serialize_article_summary(article) },
      pagination: pagination_meta(articles)
    })
  end

  # GET /api/v1/kb/articles/analytics
  def analytics
    # Tenancy-scoped: counts reflect GLOBAL + this account's articles, matching
    # the admin index — never another tenant's rows.
    articles = tenant_scoped_articles.includes(:article_views)
    period = params[:period]&.to_i&.days || 30.days

    analytics_data = {
      total_articles: articles.count,
      published_articles: articles.published.count,
      draft_articles: articles.where(status: "draft").count,
      total_views: KnowledgeBase::ArticleView.for_period(period.ago, Time.current).count,
      top_articles: KnowledgeBase::ArticleView.top_articles(limit: 10, period: period),
      views_by_day: daily_views_breakdown(period)
    }

    render_success(analytics_data)
  end

  # PATCH /api/v1/kb/articles/bulk
  def bulk_update
    article_ids = params[:article_ids]
    return render_error("No article IDs provided", status: :bad_request) if article_ids.blank?

    articles = tenant_scoped_articles.where(id: article_ids)
    return render_error("No articles found", status: :not_found) if articles.empty?

    # Check permissions for all articles
    unauthorized_articles = articles.reject { |article| article.editable_by?(current_user) }
    if unauthorized_articles.any?
      return render_error("Access denied for some articles", status: :forbidden)
    end

    updated_count = 0
    update_params = bulk_update_params

    # Same publication gate as #update. All-or-nothing, matching the
    # "Access denied for some articles" check above: one article whose move
    # would cross the published boundary refuses the whole batch rather than
    # publishing the rest. Each article is checked against its OWN current
    # status, because a batch can hold articles in different states.
    # (IMP-e32f500cdd88)
    crossing = articles.reject { |a| publication_change_allowed?(a.status, update_params[:status]) }
    if crossing.any?
      return render_error(publication_denied_message(crossing.first.status, update_params[:status]),
                          status: :forbidden)
    end

    articles.each do |article|
      from_status = article.status

      # Record the transition, exactly as #update does and through the same
      # helper — one row per article, each carrying its own from_status. A
      # batch is not one transition, and before this a bulk status move left no
      # row at all in the table that IS the answer to "who moved this article"
      # (IMP-78ae82f1deda). Per-article transaction so an unrecordable
      # transition rolls back that article rather than being committed
      # untracked, while the rest of the batch still counts.
      # (IMP-e32f500cdd88)
      recorded = ActiveRecord::Base.transaction do
        next false unless article.update(update_params)

        summary = KnowledgeBase::Workflow.change_summary(article)
        record_article_workflow!(
          article,
          action: KnowledgeBase::Workflow.action_for(from_status, article.status),
          from_status: from_status,
          to_status: article.status,
          comment: summary
        )
        true
      end

      updated_count += 1 if recorded
    end

    render_success(
      updated_count: updated_count
    )
  rescue StandardError => e
    render_internal_error("Bulk update failed", exception: e)
  end

  # DELETE /api/v1/kb/articles/bulk
  def bulk_delete
    article_ids = params[:article_ids]
    return render_error("No article IDs provided", status: :bad_request) if article_ids.blank?

    articles = tenant_scoped_articles.where(id: article_ids)
    return render_error("No articles found", status: :not_found) if articles.empty?

    # Check permissions for all articles
    unauthorized_articles = articles.reject { |article| article.editable_by?(current_user) }
    if unauthorized_articles.any?
      return render_error("Access denied for some articles", status: :forbidden)
    end

    deleted_count = 0
    articles.each do |article|
      snapshot = article_deletion_snapshot(article)
      next unless article.destroy

      record_article_deletion!(snapshot)
      deleted_count += 1
    end

    render_success(
      deleted_count: deleted_count
    )
  rescue StandardError => e
    render_internal_error("Bulk delete failed", exception: e)
  end

  private

  # Records an article state transition in knowledge_base_workflows.
  #
  # Deliberately blocking: a bare create! inside the caller's transaction, so a
  # transition that cannot be recorded is rolled back rather than committed
  # untracked. This follows the domain-event precedent in this codebase —
  # Ai::KillSwitchEvent (kill_switch_service.rb:306), Ai::TeamRestructureEvent
  # (self_organizing_team_service.rb:50) and Ai::A2aTaskEvent (a2a_task.rb:374)
  # all use a bare create!, and kill_switch_service rescues its broadcast and
  # trust-tier side effects in the same file while leaving the event write
  # unrescued. The one domain-event writer that swallows failures,
  # Ai::Introspection::ExecutionEventRecorder, records cost/duration telemetry
  # rather than a domain fact. Generic Auditable is best-effort for the same
  # reason; this table is not, because a trail with silent holes cannot answer
  # the question it exists for.
  #
  # current_user is always present here: every calling action sits behind
  # authenticate_request plus an authorize_kb_* filter.
  def record_article_workflow!(article, action:, from_status:, to_status:, comment: nil, metadata: {})
    KnowledgeBase::Workflow.create!(
      article: article,
      user: current_user,
      action: action,
      from_status: from_status,
      to_status: to_status,
      comment: comment,
      metadata: metadata.merge(source: "api").compact
    )
  end

  # Records an article DELETION — in audit_logs, not knowledge_base_workflows.
  #
  # Workflow structurally cannot hold this event. Article declares
  # `has_many :workflows, dependent: :destroy` (article.rb:22) and Workflow's
  # `belongs_to :article` is required, so the row recording a deletion is
  # cascaded away by the act it records, and cannot outlive its subject even in
  # principle. That is why `delete` sits in Workflow::VALID_ACTIONS unwritten;
  # making it writable there would need a schema change, not a call site.
  #
  # audit_logs is the sink that survives: `resource_id` is a plain string with
  # NO foreign key (schema.rb:4808), so nothing cascades, and the row carries a
  # user. The article's identity therefore goes into metadata — once the row is
  # gone, resource_id points at something nobody can look up, and a deletion
  # record that cannot say WHAT was deleted answers half the question.
  #
  # `account` is the ACTOR's, deliberately, not the article's: a GLOBAL article
  # owns no account, audit_logs.account_id is NOT NULL, and Article is in the
  # audit optional-account set — so an article-scoped row would be unwritable
  # for exactly the globals the KB ships 53 of. The actor's account is also the
  # tenant that can read the row back.
  #
  # `user: current_user` matches #record_article_workflow! above rather than
  # introducing a second, looser attribution: both delete paths sit behind
  # authenticate_request + authorize_kb_edit + editable_by?(current_user), so
  # the acting user is always present here. The account-scoped fallback chain
  # the KB tool needs exists only because an agent/instance principal has no
  # user at all; no agent path can delete an article (the tool exposes only
  # list/get/create/update).
  def record_article_deletion!(snapshot)
    AuditLog.create!(
      account: current_account,
      user: current_user,
      action: "delete",
      resource_type: "KnowledgeBase::Article",
      resource_id: snapshot[:id],
      source: "api",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: snapshot
    )
  end

  # Captured BEFORE the row goes away — this is the only place the deleted
  # article's identity still exists.
  def article_deletion_snapshot(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      status: article.status,
      account_id: article.account_id,
      category_id: article.category_id,
      author_id: article.author_id
    }
  end

  def authenticate_optional
    # Authenticate if Authorization header is present
    return unless request.headers["Authorization"].present?
    authenticate_request
  end

  def set_article
    # Resolve only within the caller's tenancy scope (global + own for an
    # authenticated user; globals only for the public path), so another
    # account's private article 404s here rather than being disclosed/edited.
    scope = tenant_scoped_articles
    @article = scope.find_by(id: params[:id]) || scope.find_by(slug: params[:id])
  end

  # Base relation honoring article tenancy: an authenticated user sees global
  # rows + their own account's rows; an unauthenticated request sees globals
  # only. The model's viewable_by?/editable_by? gates remain the per-record
  # backstop; this keeps foreign-account rows out of indexes and lookups.
  def tenant_scoped_articles
    if current_user
      KnowledgeBase::Article.for_account(current_account.id)
    else
      KnowledgeBase::Article.global
    end
  end

  def editing_mode?
    # Only return editing mode if user explicitly requests it AND has permission
    (params[:admin] == "true" || params[:edit] == "true" || request.path.include?("/admin")) && can_edit_kb?
  end

  def can_edit_kb?
    current_user&.has_permission?("kb.update") ||
    current_user&.has_permission?("kb.manage")
  end

  def can_publish_kb?
    current_user&.has_permission?("kb.publish") ||
    current_user&.has_permission?("kb.manage")
  end

  def can_manage_kb?
    current_user&.has_permission?("kb.manage")
  end

  def authorize_kb_edit
    render_error("Access denied", status: :forbidden) unless can_edit_kb?
  end

  def authorize_kb_publish
    render_error("Access denied", status: :forbidden) unless can_publish_kb?
  end

  def authorize_kb_manage
    render_error("Access denied", status: :forbidden) unless can_manage_kb?
  end

  # SECURITY (IMP-e32f500cdd88): crossing the `published` boundary is a
  # distinct act from editing, and this controller already prices it that way —
  # #publish and #unpublish sit behind authorize_kb_publish. But article_params
  # and bulk_update_params BOTH permit :status while #update and #bulk_update
  # are gated only by authorize_kb_edit, so a principal holding just kb.update
  # could publish by writing the attribute directly and never touch the gated
  # endpoints. Same bypass as the agent path's, which IMP-3682545ccbe9 closed
  # by requiring kb.publish before KbArticleManagementTool would move an
  # article across that boundary.
  #
  # The gated SET mirrors that fix exactly (its
  # #crosses_publication_boundary?): both directions across `published`, and
  # nothing else. Entering grants fleet-wide visibility, leaving revokes it,
  # and archive-from-published is an unpublish by another name. draft ->
  # review, review -> draft and draft -> archived change nobody's visibility
  # and stay open — gating them would make the human path stricter than the
  # agent path it is mirroring.
  #
  # Authorization reuses can_publish_kb?, the helper #publish/#unpublish
  # already use, rather than introducing a second definition of who may
  # publish. That means kb.manage is accepted here. The agent path excludes
  # kb.manage only because it is that TOOL's own REQUIRED_PERMISSION, so
  # honouring it there would make the check vacuous for every caller able to
  # reach the code; that reasoning does not carry to this controller, where
  # the edit gate is kb.update and kb.manage already grants #publish directly.
  def publication_change_allowed?(from_status, to_status)
    return true unless crosses_publication_boundary?(from_status, to_status)

    can_publish_kb?
  end

  # A blank to_status means the request is not asking for a status change at
  # all, and an unchanged status crosses nothing.
  def crosses_publication_boundary?(from_status, to_status)
    return false if to_status.blank?
    return false if from_status.to_s == to_status.to_s

    from_status.to_s == "published" || to_status.to_s == "published"
  end

  def publication_denied_message(from_status, to_status)
    "Access denied: changing article status (#{from_status} -> #{to_status}) crosses the " \
      "published boundary and requires the kb.publish permission"
  end

  def apply_filters(articles)
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.featured if params[:featured] == "true"
    articles = articles.recent if params[:sort] == "recent"
    articles = articles.popular if params[:sort] == "popular"

    if params[:tags].present?
      tag_names = params[:tags].split(",")
      articles = articles.joins(:tags).where(knowledge_base_tags: { name: tag_names })
    end

    articles
  end

  def apply_admin_filters(articles)
    articles = articles.where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?
    articles = articles.where(status: params[:status]) if params[:status].present?
    articles = articles.in_category(params[:category_id]) if params[:category_id].present?
    articles = articles.by_author(params[:author_id]) if params[:author_id].present?
    articles = articles.where(is_public: params[:is_public] == "true") if params[:is_public].present?
    articles = articles.where(is_featured: params[:is_featured] == "true") if params[:is_featured].present?

    case params[:sort]
    when "recent"
      articles.recent
    when "popular"
      articles.popular
    when "title"
      articles.order(:title)
    else
      articles.order(updated_at: :desc)
    end
  end

  def handle_tag_assignment(article)
    tag_names = params[:article][:tag_names]
    article.tag_names = tag_names.is_a?(Array) ? tag_names : tag_names.split(",").map(&:strip)
    article.save
  end

  def article_params
    params.require(:article).permit(
      :title, :slug, :content, :excerpt, :category_id, :status, :is_public, :is_featured,
      :sort_order, :meta_title, :meta_description, metadata: {}
    )
  end

  def bulk_update_params
    params.permit(:status, :category_id, :is_featured, :is_public)
  end

  def serialize_article_summary(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      excerpt: article.excerpt,
      author_name: article.author.full_name,
      category: {
        id: article.category.id,
        name: article.category.name,
        slug: article.category.slug
      },
      published_at: article.published_at,
      reading_time: article.reading_time,
      views_count: article.views_count,
      likes_count: article.likes_count,
      is_featured: article.is_featured,
      tags: article.tags.map(&:name)
    }
  end

  def serialize_article_full(article)
    serialize_article_summary(article).merge(
      content: article.content,
      metadata: article.metadata,
      attachments: article.attachments.map { |attachment| serialize_attachment(attachment) },
      comments_enabled: true,
      can_edit: article.editable_by?(current_user)
    )
  end

  def serialize_article_admin(article)
    {
      id: article.id,
      title: article.title,
      slug: article.slug,
      status: article.status,
      is_public: article.is_public,
      is_featured: article.is_featured,
      author_name: article.author.full_name,
      category: {
        id: article.category.id,
        name: article.category.name
      },
      views_count: article.views_count,
      likes_count: article.likes_count,
      comments_count: article.comments.approved.count,
      created_at: article.created_at,
      updated_at: article.updated_at,
      published_at: article.published_at,
      tags: article.tags.map(&:name)
    }
  end

  def serialize_article_detailed(article)
    serialize_article_admin(article).merge(
      content: article.content,
      excerpt: article.excerpt,
      sort_order: article.sort_order,
      reading_time: article.reading_time,
      meta_title: article.meta_title,
      meta_description: article.meta_description,
      metadata: article.metadata,
      attachments: article.attachments.map { |attachment| serialize_attachment(attachment) }
    )
  end

  def serialize_attachment(attachment)
    {
      id: attachment.id,
      filename: attachment.filename,
      content_type: attachment.content_type,
      file_size: attachment.human_file_size,
      download_count: attachment.download_count
    }
  end

  def calculate_article_stats
    scope = tenant_scoped_articles
    {
      total: scope.count,
      published: scope.published.count,
      draft: scope.where(status: "draft").count,
      review: scope.where(status: "review").count,
      archived: scope.where(status: "archived").count
    }
  end

  def daily_views_breakdown(period)
    KnowledgeBase::ArticleView.for_period(period.ago, Time.current)
      .group_by_day(:created_at)
      .count
      .transform_keys { |date| date.strftime("%Y-%m-%d") }
  end

end

# frozen_string_literal: true

# Controller mixin for foundational-content endpoints whose model includes
# GloballyScopable (global platform content vs account-owned copies). Provides
# the scope filter, clone-to-customize, and 3-way update-from-source actions, plus
# a read-only guard for global rows. Each controller must define `content_model`
# (the AR class) and may override `content_json` for richer serialization.
module GloballyScopedContent
  extend ActiveSupport::Concern

  # POST .../:id/clone — fork a visible (global or account) record into the
  # current account as an editable copy with provenance.
  def clone
    record = find_visible_content(params[:id])
    return unless record

    copy = record.clone_to_account(current_account)
    render_success({ data: content_json(copy) }, status: :created)
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message, status: :unprocessable_content)
  end

  # GET .../:id/update_from_source/preview — 3-way diff of an account copy vs its
  # origin (no save): which fields would auto-pull and which conflict.
  def update_from_source_preview
    record = find_owned_content(params[:id])
    return unless record

    render_success(record.update_from_source(dry_run: true))
  end

  # POST .../:id/update_from_source — apply the 3-way merge; optional
  # `resolutions` => { field => chosen_value } resolves conflicts.
  def update_from_source
    record = find_owned_content(params[:id])
    return unless record

    result = record.update_from_source(resolutions: params[:resolutions]&.to_unsafe_h || {})
    render_success(result.merge(data: content_json(record)))
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message, status: :unprocessable_content)
  end

  private

  # Global (platform-managed) rows + the current account's own rows.
  def find_visible_content(id)
    record = content_model.for_account(current_account.id).find_by(id: id)
    render_not_found(content_model.name.demodulize) unless record
    record
  end

  # Only the current account's own rows (clones are editable; globals are not).
  def find_owned_content(id)
    record = content_model.owned_by_account(current_account.id).find_by(id: id)
    render_not_found(content_model.name.demodulize) unless record
    record
  end

  # Guard mutations: global content is platform-managed/read-only — clone to edit.
  def require_editable_content!(record)
    return true unless record.global?

    render_forbidden("#{content_model.name.demodulize} is global (platform-managed) and read-only — clone it to customize")
    false
  end

  # Apply ?scope=global|custom|all (default: for_account = global + own) to a relation.
  def apply_content_scope(relation)
    case params[:scope].to_s
    when "global" then relation.global
    when "custom" then relation.owned_by_account(current_account.id)
    when "all"    then relation
    else relation.for_account(current_account.id)
    end
  end

  def content_json(record)
    record.as_json
  end
end

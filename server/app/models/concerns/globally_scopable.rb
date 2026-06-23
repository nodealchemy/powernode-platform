# frozen_string_literal: true

# Shared scoping for foundational content that is either GLOBAL (platform-
# provided: account_id nil — read-only to accounts, seed-managed/upserted by
# source_key) or ACCOUNT-owned (account_id set — fully customizable). Mirrors the
# global/account Role model. Includers must have these columns: account_id
# (nullable), source_key, cloned_from_id, source_version, source_snapshot.
module GloballyScopable
  extend ActiveSupport::Concern

  included do
    # Each includer keeps its own `belongs_to :account` (now optional, since
    # account_id is nullable = global). The concern adds the clone self-reference.
    belongs_to :cloned_from, class_name: name, optional: true

    scope :global,           -> { where(account_id: nil) }
    scope :account_scoped,   -> { where.not(account_id: nil) }
    scope :owned_by_account, ->(account_id) { where(account_id: account_id) }
    # Visible to an account: global rows + that account's own rows.
    scope :for_account,      ->(account_id) { where(account_id: [ nil, account_id ]) }
  end

  # Platform-provided (read-only to accounts, seed-managed) when true.
  def global?
    account_id.nil?
  end

  # An account-owned copy cloned from another row when true.
  def clone?
    cloned_from_id.present?
  end

  # Scope/provenance fields for API serialization so the UI can show global vs
  # account, read-only state, and clone/rebase availability. Merge into each
  # content serializer's hash.
  def scope_attributes
    {
      account_id:     account_id,
      global:         global?,
      cloned_from_id: cloned_from_id,
      source_key:     source_key,
      source_version: source_version
    }
  end

  # Identity/provenance/scoping columns — excluded from cloning + the snapshot.
  CLONE_INFRA = %w[id created_at updated_at account_id cloned_from_id
                   source_key source_version source_snapshot].freeze
  # Per-copy metadata — cloned, but never merged in update_from_source.
  MERGE_SKIP = %w[slug version is_system].freeze

  # The content attributes (everything that isn't infra). Used for cloning, the
  # clone-time snapshot, and the 3-way merge.
  def content_attributes
    attributes.except(*CLONE_INFRA)
  end

  # Clone this (typically global, read-only) record into `account` as a fully
  # editable account-owned copy, recording provenance for update_from_source.
  def clone_to_account(account, overrides = {})
    acct_id = account.respond_to?(:id) ? account.id : account
    copy = self.class.new(content_attributes)
    copy.account_id      = acct_id
    copy.cloned_from_id  = id
    copy.source_key      = source_key.presence || id.to_s
    copy.source_version  = respond_to?(:version) ? version : nil
    copy.source_snapshot = content_attributes
    copy.is_system       = false if copy.respond_to?(:is_system=)
    copy.assign_attributes(overrides)
    copy.slug = unique_clone_slug(copy.slug, acct_id) if copy.respond_to?(:slug) && copy.slug.present?
    copy.name = unique_clone_name(copy.name, acct_id) if copy.respond_to?(:name) && copy.name.present?
    copy.save!
    copy
  end

  # 3-way merge of this clone against its origin: base = source_snapshot
  # (origin @ clone), now = origin's current content, mine = this clone's content.
  # Auto-pulls fields the origin changed but the user didn't; keeps the user's
  # where only they changed; surfaces conflicts (both changed) for resolution.
  # `resolutions` = { "field" => chosen_value }; dry_run computes without saving.
  # => { pulled: [...], conflicts: { field => { base:, yours: } }, synced: bool }.
  def update_from_source(resolutions: {}, dry_run: false)
    origin = cloned_from
    return { error: "no_origin" } unless origin

    base = (source_snapshot || {})
    now  = origin.content_attributes
    mine = content_attributes
    resolutions = (resolutions || {}).stringify_keys

    pulled = []
    conflicts = {}
    now.each do |field, now_val|
      next if MERGE_SKIP.include?(field)
      next if base[field] == now_val            # origin unchanged for this field
      user_changed = base[field] != mine[field]
      if !user_changed
        self[field] = now_val unless dry_run    # auto-pull
        pulled << field
      elsif mine[field] == now_val
        next                                    # converged independently
      elsif resolutions.key?(field)
        self[field] = resolutions[field] unless dry_run
        pulled << field
      else
        conflicts[field] = { base: now_val, yours: mine[field] }
      end
    end

    synced = conflicts.empty?
    unless dry_run
      if synced
        self.source_snapshot = now
        self.source_version  = (origin.respond_to?(:version) ? origin.version : source_version)
      end
      save! if changed?
    end
    { pulled: pulled, conflicts: conflicts, synced: synced }
  end

  private

  # An account-unique slug for a clone (global slugs are unique; suffix to avoid
  # colliding with the origin or another row visible to the account).
  def unique_clone_slug(base_slug, acct_id)
    candidate = "#{base_slug}-copy"
    n = 1
    while self.class.where(slug: candidate)
                    .where("account_id = :a OR account_id IS NULL", a: acct_id).exists?
      n += 1
      candidate = "#{base_slug}-copy-#{n}"
    end
    candidate
  end

  # An account-unique name for a clone (models validate name uniqueness per
  # account); suffix "(Copy)" so it's distinct from the origin + any sibling.
  def unique_clone_name(base_name, acct_id)
    candidate = "#{base_name} (Copy)"
    n = 1
    while self.class.where(name: candidate)
                    .where("account_id = :a OR account_id IS NULL", a: acct_id).exists?
      n += 1
      candidate = "#{base_name} (Copy #{n})"
    end
    candidate
  end
end

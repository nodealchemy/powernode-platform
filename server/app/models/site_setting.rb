# frozen_string_literal: true

class SiteSetting < ApplicationRecord
  # Keys whose value may be deliberately blank: optional social/analytics links
  # and the contact email (community contact is via GitHub — the seed sets it
  # to ""). Single source for the presence validation and can_be_blank?.
  BLANK_ALLOWED_KEYS = %w[
    social_facebook
    social_twitter
    social_linkedin
    social_instagram
    social_youtube
    analytics_tracking_id
    contact_email
  ].freeze

  # Validations
  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :setting_type, presence: true, inclusion: { in: %w[string text boolean integer json] }
  validates :value, presence: true, unless: ->(setting) { setting.setting_type == "boolean" || setting.key.in?(BLANK_ALLOWED_KEYS) }
  validate :value_passes_registered_check

  # Callbacks
  after_save :clear_footer_cache_if_needed
  after_destroy :clear_footer_cache_if_needed

  # E8: nothing under these prefixes is ever public. The column defaults to
  # TRUE in the database, so any writer that forgets the flag — a seed calling
  # create!, the generic settings door, a console session — would otherwise
  # publish operator internals such as where alert email goes. Coerced rather
  # than rejected: rejecting would raise inside the seed file's shared rescue
  # and silently skip every setting seeded after it.
  #
  # `ai.improvement_discovery` joined with D1's review fixes: its tier and
  # offer caps are operator configuration, not anything a public page needs.
  #
  # `dev_merge.` joined with IMP-e82f619dde7a: it holds the names of private
  # extensions, which must never reach a public page.
  PRIVATE_KEY_PREFIXES = %w[platform.status. ai.improvement_discovery dev_merge.].freeze
  before_validation :keep_private_namespace_private

  # Scopes
  scope :public_settings, -> { where(is_public: true) }
  scope :by_type, ->(type) { where(setting_type: type) }
  scope :footer_settings, -> { where(key: footer_keys) }

  # Class methods
  def self.footer_keys
    %w[
      site_name
      copyright_text
      copyright_year
      social_facebook
      social_twitter
      social_linkedin
      social_instagram
      social_youtube
      footer_description
      company_address
      contact_email
      contact_phone
    ]
  end

  # Per-key value checks, registered by whoever owns the key (an extension
  # included) and run on every write through this model: SiteSetting.set, the
  # settings door, a seed. A check returns nil for an acceptable value, else
  # the reason, which becomes the validation error. Core names no key here.
  def self.register_value_check(key, &check)
    value_checks[key.to_s] = check
  end

  def self.value_checks
    @value_checks ||= {}
  end

  # A presenter renders a key's raw value for a HUMAN, next to the raw value and
  # never in place of it (the protected-setting approval card, IMP-78bc3b20ee94).
  # Registered by whoever owns the key, an extension included; core names no key.
  #
  # The block takes the raw stored value and the viewer, and returns
  #   { items: [ { raw:, fields: { name: text }, flags: [ :flag ] } ], omitted: n }
  # `raw` is the entry an item describes. `fields` are text ABOUT it, keyed by a
  # fixed identifier (the client owns the visible labels, so no label is ever
  # tenant text); a field's text is untrusted and stays in its own slot. `flags`
  # are facts the presenter's own code computed (no longer exists, another
  # account's), also fixed identifiers: the client turns them into fixed text,
  # so they never share a slot with tenant text. `omitted` counts entries the
  # presenter left out (it must bound its own work to PRESENTED_ROW_LIMIT).
  #
  # Core runs the block in a transaction that is ALWAYS rolled back, read-only,
  # under a statement_timeout: the database cancels a slow lookup and a write is
  # refused. (Never a wall-clock Timeout around the block: interrupting a thread
  # mid-query can leave a pooled connection broken.) Anything wrong at all, an
  # exception, a cancelled query, a malformed return, yields nil and the caller
  # shows the raw value alone. #present_value never raises.
  PRESENTED_FIELD_LIMIT = 160
  PRESENTED_RAW_LIMIT = 200
  PRESENTED_ROW_LIMIT = 100
  PRESENTER_STATEMENT_TIMEOUT_MS = 2000
  PRESENTED_IDENTIFIER = /\A[a-z][a-z0-9_]{0,31}\z/

  def self.register_value_presenter(key, &presenter)
    value_presenters[key.to_s] = presenter
  end

  def self.value_presenters
    @value_presenters ||= {}
  end

  # { "items" => [ { "raw", "fields", "flags" } ], "omitted" => Integer } for
  # `raw`, or nil when the key has no presenter or its presentation cannot be
  # trusted.
  def self.present_value(key, raw, viewer: nil)
    presenter = value_presenters[key.to_s]
    return nil unless presenter

    result = nil
    transaction(requires_new: true) do
      connection.execute("SET LOCAL statement_timeout = #{PRESENTER_STATEMENT_TIMEOUT_MS.to_i}")
      connection.execute("SET LOCAL transaction_read_only = on")
      result = presenter.call(raw, viewer)
      raise ActiveRecord::Rollback
    end
    presented_value(result)
  rescue StandardError => e
    Rails.logger.warn("[SiteSetting] value presenter for #{key} failed: #{e.class}")
    nil
  end

  def self.presented_value(result)
    return nil unless result.is_a?(Hash)

    result = result.with_indifferent_access
    items = result[:items]
    omitted = result.fetch(:omitted, 0)
    return nil unless items.is_a?(Array) && omitted.is_a?(Integer) && omitted >= 0

    presented = items.first(PRESENTED_ROW_LIMIT).map { |item| presented_item(item) }
    return nil if presented.any?(&:nil?)

    { "items" => presented, "omitted" => omitted + [ items.size - PRESENTED_ROW_LIMIT, 0 ].max }
  end
  private_class_method :presented_value

  def self.presented_item(item)
    return nil unless item.is_a?(Hash)

    item = item.with_indifferent_access
    fields = item.fetch(:fields, {})
    flags = item.fetch(:flags, [])
    return nil if item[:raw].nil? || !fields.is_a?(Hash) || !flags.is_a?(Array)
    return nil unless (fields.keys + flags).all? { |name| name.to_s.match?(PRESENTED_IDENTIFIER) }

    { "raw" => presented_text(item[:raw], PRESENTED_RAW_LIMIT),
      "fields" => fields.to_h { |name, text| [ name.to_s, presented_text(text, PRESENTED_FIELD_LIMIT) ] },
      "flags" => flags.map(&:to_s).uniq }
  end
  private_class_method :presented_item

  # Every control, format and separator character (newlines, U+2028/2029, bidi
  # overrides, zero-width, no-break space) becomes a plain space or is dropped;
  # only an ASCII space survives, so text cannot break its line or its slot.
  def self.presented_text(text, limit)
    return nil if text.nil?

    clean = text.to_s.gsub(/[\p{Cc}\p{Z}]/, " ").gsub(/\p{C}/, "").squeeze(" ").strip
    clean.length > limit ? "#{clean[0, limit - 1]}…" : clean
  end
  private_class_method :presented_text

  def self.get(key)
    setting = find_by(key: key.to_s)
    return nil unless setting

    case setting.setting_type
    when "boolean"
      setting.value.to_s.downcase.in?([ "true", "1", "yes" ])
    when "integer"
      setting.value.to_i
    when "json"
      JSON.parse(setting.value) rescue {}
    else
      setting.value
    end
  end

  def self.set(key, value, description: nil, setting_type: "string", is_public: false)
    setting = find_or_initialize_by(key: key.to_s)

    setting.value = case setting_type
    when "json"
                      value.is_a?(String) ? value : value.to_json
    when "boolean"
                      value.to_s
    else
                      value.to_s
    end

    setting.description = description if description
    setting.setting_type = setting_type
    setting.is_public = is_public
    setting.save!
    setting
  end

  def self.footer_settings
    settings = where(key: footer_keys)
    settings.each_with_object({}) do |setting, hash|
      hash[setting.key] = get(setting.key)
    end
  end

  def self.public_footer_settings
    cache_enabled = get("footer_cache_enabled")
    cache_key = "site_settings:footer:public"

    if cache_enabled
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        fetch_footer_settings_data
      end
    else
      fetch_footer_settings_data
    end
  end

  # Clear footer cache when footer settings are updated
  def self.clear_footer_cache!
    Rails.cache.delete("site_settings:footer:public")
  end

  private_class_method def self.fetch_footer_settings_data
    public_settings.where(key: footer_keys).each_with_object({}) do |setting, hash|
      hash[setting.key] = get(setting.key)
    end
  end

  # Instance methods
  def parsed_value
    self.class.get(key)
  end

  private

  def boolean_type?
    setting_type == "boolean"
  end

  def can_be_blank?
    # Allow these fields to be blank
    key.in?(BLANK_ALLOWED_KEYS)
  end

  def value_passes_registered_check
    check = self.class.value_checks[key.to_s]
    return if check.nil?

    reason = check.call(value)
    errors.add(:value, reason) if reason.present?
  end

  def keep_private_namespace_private
    return unless PRIVATE_KEY_PREFIXES.any? { |prefix| key.to_s.start_with?(prefix) }

    self.is_public = false
  end

  def clear_footer_cache_if_needed
    # Clear cache if this is a footer setting or the cache toggle itself
    if self.class.footer_keys.include?(key) || key == "footer_cache_enabled"
      self.class.clear_footer_cache!
    end
  end
end

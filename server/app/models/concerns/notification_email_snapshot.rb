# frozen_string_literal: true

# The address a GDPR completion notice goes to, captured while the data subject
# still has one (IMP-b719328ddeb9).
#
# The erasure a deletion request performs anonymizes the user record, and an
# account termination anonymizes every account user before it is marked
# complete, so an address resolved at completion is an anonymized placeholder or
# nil. The request therefore carries a snapshot taken at creation. Snapshot at
# creation, deliberately not refreshed later: the address the data subject
# authenticated with when they asked is the one to confirm to, and a refresh
# would let an address changed after an account takeover redirect the notice.
#
# The snapshot is itself personal data, so it is:
#   * encrypted at rest (the house pattern for user emails);
#   * scrubbed in the SAME UPDATE that moves the row to a settled status, so it
#     never outlives the data it describes (callers that still need the address
#     for the notice read it BEFORE that write, see #capturing_notification_address);
#   * absent from generic serialization; the one deliberate reader is the
#     internal worker show endpoint, which reads the attribute explicitly.
#
# Includers define NOTIFICATION_SETTLED_STATUSES and #notification_email_source.
module NotificationEmailSnapshot
  extend ActiveSupport::Concern

  included do
    encrypts :notification_email

    before_create :snapshot_notification_email, unless: :notification_settled?
    before_update :scrub_notification_email, if: :entering_notification_settled_status?
  end

  # Not in as_json/to_json/serializable_hash unless a caller lists it in
  # `only:` on purpose.
  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) | [ :notification_email ] unless options[:only]
    super(options)
  end

  private

  def snapshot_notification_email
    self.notification_email = notification_email_source.presence
  end

  def scrub_notification_email
    self.notification_email = nil
  end

  def notification_settled?
    self.class::NOTIFICATION_SETTLED_STATUSES.include?(status)
  end

  def entering_notification_settled_status?
    status_changed? && notification_settled?
  end

  # The address held BEFORE the block's terminal write scrubs it, or nil (with
  # a warning, never a raise: a missing address must not fail the completion).
  def capturing_notification_address
    address = notification_email
    yield
    return address if address.present?

    Rails.logger.warn "[#{self.class.name}] #{id}: no notification address on file, " \
                      "skipping the completion notification"
    nil
  end
end

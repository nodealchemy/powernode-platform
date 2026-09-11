# frozen_string_literal: true

# A PERSON'S OWN SESSION (MCP identity plan R2).
#
# Some decisions belong to a person, and no tool door is a person's consent:
# an MCP client's token and an agent's creator are AUTHORITY, never someone
# confirming (Ai::Tools::CallOrigin). The one place a person decides is
# their own REST/UI session. This is the single predicate for "is this that
# session":
#
#   * a user, and no worker token;
#   * not an impersonation session: an administrator acting as the user it
#     names, so a decision would name the wrong person;
#   * a JWT of type "access": the user's own login, not a service token;
#   * no account-switch delegation: that session carries another account's
#     permissions (Authentication#delegated_permission?).
#
# Included where such a decision is made. It answers, and it words the one
# refusal every REST decision door gives for it (#human_session_refusal), so
# the approval queue and the governance door say the same thing.
module HumanSession
  extend ActiveSupport::Concern

  private

  # MCP identity plan R2 and D1: a request that needs a person's own session
  # (Ai::ApprovalRequest#requires_human_session?), and a tool-door request
  # decided by the person who asked for it (guard a), are decided only from
  # that person's own session. An impersonation, account-switch or service
  # session is refused by name. nil when this session may decide it.
  def human_session_refusal(request, verb)
    return nil if own_human_session?

    if request.requires_human_session?
      return "Cannot #{verb} this request from this session: it needs a person deciding it in their own session, " \
             "not an impersonation, account-switch or service session."
    end
    return nil unless request.requester_excluded?(approver: current_user, origin: human_decision_origin)

    "Cannot #{verb} this request from this session: you asked for it through a tool, so you decide it only " \
      "in your own session, not an impersonation, account-switch or service session."
  end

  def own_human_session?
    return false if current_user.nil? || current_worker.present?
    return false if impersonating?

    payload = current_jwt_payload
    return false unless payload.respond_to?(:dig) && payload.dig(:type).to_s == "access"

    payload.dig(:delegation_id).blank?
  end

  # The door a decision made here came through (Ai::ApprovalDecision ORIGINS):
  # a person's own session, or any other REST session.
  def human_decision_origin
    own_human_session? ? ::Ai::ApprovalDecision::REST_SESSION : ::Ai::ApprovalDecision::REST_OTHER
  end
end

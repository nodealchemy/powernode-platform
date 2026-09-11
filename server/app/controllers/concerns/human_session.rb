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
# Included where such a decision is made. It answers; the including
# controller decides what a refusal says.
module HumanSession
  extend ActiveSupport::Concern

  private

  def own_human_session?
    return false if current_user.nil? || current_worker.present?
    return false if impersonating?

    payload = current_jwt_payload
    return false unless payload.respond_to?(:dig) && payload.dig(:type).to_s == "access"

    payload.dig(:delegation_id).blank?
  end
end

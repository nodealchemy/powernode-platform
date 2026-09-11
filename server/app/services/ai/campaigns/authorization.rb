# frozen_string_literal: true

module Ai
  module Campaigns
    # The one answer to "may this user read or change campaigns and campaign proposals in
    # THIS account?". Both REST doors gate every action on it, and the services behind the
    # mutating ones (CampaignDriver, Ai::CampaignProposal) ask it again, so every door
    # inherits the check.
    #
    # The permission is answered for the account whose campaign or proposal the call
    # touches, from the user's OWN roles there. An account-switch session carries
    # permissions DELEGATED from another account (Authentication#has_permission? answers
    # from that delegation), while the campaign doors resolve records in the user's own
    # account; a door that asked has_permission? therefore acted on the own account under
    # another account's grant. A delegation is never consulted here, and a record in any
    # account other than the user's is refused.
    module Authorization
      MANAGE_PERMISSION = "ai.campaigns.manage"
      READ_PERMISSION = "ai.campaigns.read"

      class Refused < StandardError; end

      module_function

      def permitted?(user:, account:, permission: MANAGE_PERMISSION)
        return false if user.nil? || account.nil?
        return false unless user.account_id == account.id

        user.has_permission?(permission)
      end

      def authorize!(user:, account:, permission: MANAGE_PERMISSION)
        return if permitted?(user: user, account: account, permission: permission)

        who = user ? "user #{user.id}" : "a caller with no user"
        raise Refused, "#{who} does not hold '#{permission}' in account #{account&.id}"
      end

      # For services an agent or instance principal also reaches: a call with no user
      # comes from a principal its own door already bound to the account. A call that
      # names a user is always asked.
      def authorize_actor!(user:, account:, permission: MANAGE_PERMISSION)
        return if user.nil?

        authorize!(user: user, account: account, permission: permission)
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Approvals
    # The viewer a change card is built for on a request: the signed-in user,
    # but answering has_permission? through the SESSION's permission check (the
    # controller's delegation-aware Authentication#has_permission?, the one its
    # before_actions use), never the user's own roles. An account-switch
    # session's authority is its delegation's scope, so asking the User would
    # let the card show a narrower delegation what it is refused everywhere
    # else (IMP-08ebabb04b42). The check is handed in, not re-derived here, so
    # the card and the request's guards consult one source.
    class SessionViewer
      # A value presenter reads the viewer's account_id for its viewer-relative
      # flags (SiteSetting.present_value); that stays the user's, as before.
      delegate :account_id, to: :@user

      def initialize(user:, permission_check:)
        @user = user
        @permission_check = permission_check
      end

      def has_permission?(permission_name)
        @permission_check.call(permission_name) == true
      end
    end
  end
end

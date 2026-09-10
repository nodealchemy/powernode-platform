# frozen_string_literal: true

module Platform
  module Status
    # CORE ESCALATION (design §5.4, §8 row A7). The step that makes the status
    # plane reach a PERSON.
    #
    # Everything before this increment is a screen: a verdict nobody is looking
    # at is a verdict nobody acts on. This turns two situations into a
    # notification an operator receives whether or not the page is open:
    #
    #   1. a component transitioning to `down` — immediately, `critical`;
    #   2. a component that has been `degraded` longer than a configured dwell
    #      — `warning`, on the sweep that notices.
    #
    # ── TWO ENTRY POINTS, BECAUSE THEY ANSWER DIFFERENT QUESTIONS ───────────
    # `run!` is an EMITTER: it sees one transition, at the moment it happens,
    # and can only answer "did something just break". Dwell is invisible to it
    # — nothing transitions when a component stays degraded, so an
    # emitter-only design would notify about a five-second blip and stay
    # silent through an hour-long one. `sweep!` is the periodic pass that
    # answers "has anything been broken for too long". Both are needed; either
    # alone has a blind spot.
    #
    # ── RATE LIMITING IS ON THE ROW, NOT IN MEMORY ──────────────────────────
    # `platform_component_statuses.last_notified_at` is the claim. A process-
    # local cache would re-notify after every deploy and would notify N times
    # from N web processes; the column is the one place every writer agrees
    # on. One notification per row per `notify_interval_minutes`.
    #
    # ── A RECOVERY RESETS THE CLAIM ─────────────────────────────────────────
    # Reaching `ok` sets `last_notified_at` back to nil. DECIDED THIS WAY on
    # purpose: the interval exists to stop a flapping component from paging
    # somebody every minute, not to suppress a NEW outage because an old one
    # happened forty minutes ago. Without the reset, a component that broke,
    # recovered and broke again inside one interval would fail silently the
    # second time — the exact case an operator most needs to hear about. The
    # cost is that a component flapping ok→down→ok→down notifies on each
    # `down`; that is a real alert about a real instability, not noise.
    #
    # ── A REAPED ROW NOTIFIES NOBODY ────────────────────────────────────────
    # A removal arrives as a transition with `to: nil` (the component's record
    # is gone, or the sweep reaped it). There is no verdict, nothing broke,
    # and the row it referred to no longer exists. Notifying there would page
    # an operator every time somebody deletes a docker host.
    #
    # ── WHO IS NOTIFIED ─────────────────────────────────────────────────────
    # Users holding `platform.status.read` — A4's permission — resolved through
    # the existing `User.with_permission` scope, which always includes
    # `system.admin` holders. STATED PLAINLY: that permission is not defined
    # yet, so TODAY this resolves to the account's admins and nobody else. That
    # is the correct behaviour for an undefined permission on this platform,
    # it is never an empty set, and it widens by itself the moment A4 defines
    # the permission and an operator grants it. No second recipient rule to
    # keep in step.
    #
    # ── WHAT IS NOT ESCALATED, AND WHY IT IS A GAP ──────────────────────────
    # Shared (NULL-account) rows — the `provider_circuit_breaker` kind — are
    # skipped. They belong to no tenant, so there is no account whose operators
    # could be notified, and picking one would fabricate the tenancy A3
    # deliberately refused to invent. The consequence is real and is flagged in
    # the report rather than hidden here: nobody is notified when a shared
    # component goes down. Closing it needs a platform-operator recipient
    # concept that does not exist yet.
    class Escalation
      # Minutes between notifications for the SAME row.
      NOTIFY_INTERVAL_SETTING = "platform.status.notify_interval_minutes"
      DEFAULT_NOTIFY_INTERVAL_MINUTES = 60

      # How long `degraded` must persist before it is worth a person's
      # attention. Short enough to catch a real problem, long enough that a
      # single failed sync does not page anyone.
      DEGRADED_AFTER_SETTING = "platform.status.degraded_notify_after_minutes"
      DEFAULT_DEGRADED_AFTER_MINUTES = 15

      # A4's permission. Undefined today ⇒ admins only. See "WHO IS NOTIFIED".
      STATUS_PERMISSION = "platform.status.read"

      NOTIFICATION_TYPE = "system_alert"
      NOTIFICATION_CATEGORY = "system"

      SEVERITY_DOWN = "critical"
      SEVERITY_DEGRADED = "warning"

      class << self
        # EMITTER ENTRY POINT. Registered as
        # `Platform::Status::Emitters.register(:escalation)`, so the keywords
        # match that seam exactly (`transition:`, `events:`) — a method that
        # does not match the seam is a method that never runs.
        #
        # `events` is unused today. It is in the signature because the seam
        # passes it and a later increment may want the event ids in the
        # notification metadata; taking it and ignoring it is cheaper than a
        # signature change that breaks every emitter.
        #
        # @return [Array<Notification>] created notifications, possibly empty
        def run!(transition:, events: [], now: Time.current)
          new(now: now).handle_transition(transition)
        end

        # PERIODIC ENTRY POINT. Call after a sweep, once per account.
        #
        # CALL SITE FOR LANE 1 (not edited here — `SweepRunner` is theirs):
        # in `Platform::Status::SweepRunner#run!`, after `publish` has fanned
        # out every transition and before the summary is returned:
        #
        #   Escalation.sweep!(@account, now: @now)
        #
        # It must run AFTER the transitions, so a component that just went
        # degraded has its row written before dwell is measured against it.
        #
        # @return [Array<Notification>] created notifications, possibly empty
        def sweep!(account, now: Time.current)
          new(now: now).sweep_degraded(account)
        end

        def notify_interval_minutes
          positive_setting(NOTIFY_INTERVAL_SETTING, DEFAULT_NOTIFY_INTERVAL_MINUTES)
        end

        def degraded_after_minutes
          positive_setting(DEGRADED_AFTER_SETTING, DEFAULT_DEGRADED_AFTER_MINUTES)
        end

        private

        # A blank or non-positive setting is the default, never zero: a
        # zero-minute interval would turn the rate limit off silently and
        # notify on every sweep.
        def positive_setting(key, fallback)
          configured = ::SiteSetting.get(key)
          configured.present? && configured.to_i.positive? ? configured.to_i : fallback
        end
      end

      def initialize(now: Time.current)
        @now = now
      end

      # One transition. Returns the notifications created (usually 0 or many,
      # one per recipient).
      def handle_transition(transition)
        return [] unless transition.is_a?(Hash)

        to = transition[:to] || transition["to"]
        row = component_status_for(transition)
        return [] if row.nil?

        case to.to_s
        when ComponentStatus::DOWN then escalate_down(row)
        when ComponentStatus::OK   then clear_claim(row)
        else [] # degraded is dwell-based; held/progressing/not_measured are not paged
        end
      end

      # Every row of this account that has been `degraded` longer than the
      # configured dwell and is outside its notification interval.
      def sweep_degraded(account)
        return [] if account.blank?

        threshold = self.class.degraded_after_minutes.minutes

        degraded_rows(account).flat_map do |row|
          since = degraded_since(row)
          next [] if since.nil?
          next [] if (@now - since) < threshold

          notify(row, severity: SEVERITY_DEGRADED,
                      title: "#{row.display_name.presence || row.component_ref} is degraded",
                      message: degraded_message(row, since))
        end
      end

      private

      # A removal (`to: nil`) has no row and no verdict — nothing to escalate.
      # Looked up rather than trusted from the transition because the row is
      # also where the rate-limit claim lives.
      def component_status_for(transition)
        id = transition[:component_status_id] || transition["component_status_id"]
        return nil if id.blank?

        ComponentStatus.find_by(id: id)
      end

      def escalate_down(row)
        notify(row, severity: SEVERITY_DOWN,
                    title: "#{row.display_name.presence || row.component_ref} is down",
                    message: down_message(row))
      end

      # Recovery. No notification — an operator who was told about the outage
      # does not need a second interruption to be told it stopped, and the
      # page shows the verdict either way. The CLAIM is cleared so the next
      # outage is not swallowed by the interval. See the class comment.
      def clear_claim(row)
        row.update_column(:last_notified_at, nil) if row.last_notified_at.present?
        []
      end

      def notify(row, severity:, title:, message:)
        # BEFORE the rate-limit check, and therefore before any claim: a kind
        # that does not escalate here must leave `last_notified_at` untouched,
        # or A7 would silently suppress the owning lane's own notification the
        # next time it looked at the row.
        return [] unless escalates?(row.component_kind)
        return [] unless notifiable?(row)

        recipients = recipients_for(row)
        return [] if recipients.empty?

        notifications = recipients.filter_map do |user|
          create_notification(user, row, severity: severity, title: title, message: message)
        end

        # The claim is staked even if every create failed: a notification
        # subsystem that is broken must not turn into a loop that retries on
        # every sweep forever.
        row.update_column(:last_notified_at, @now)
        notifications
      end

      # Design §5.4 — fleet kinds keep their own lane's escalation. The
      # decision belongs to the contributor that owns the kind, never to a list
      # of kind names in core: see Platform::Status::Contributor#escalates?.
      #
      # FAILS OPEN, deliberately. An unregistered kind, a contributor that
      # predates the predicate, and a contributor whose predicate raises all
      # escalate. The opposite default turns any of those three into a
      # component that breaks and pages nobody, which nothing else in the
      # system would reveal.
      def escalates?(component_kind)
        contributor = Registry.fetch(component_kind)
        return true if contributor.nil?
        return true unless contributor.respond_to?(:escalates?)

        contributor.escalates? != false
      rescue StandardError => e
        Rails.logger.error("[Platform::Status::Escalation] escalates? failed for " \
                           "#{component_kind}: #{e.class}: #{e.message}")
        true
      end

      def notifiable?(row)
        return true if row.last_notified_at.blank?

        (@now - row.last_notified_at) >= self.class.notify_interval_minutes.minutes
      end

      # Shared rows carry no account — see "WHAT IS NOT ESCALATED".
      def recipients_for(row)
        return [] if row.account_id.blank?

        ::User.where(account_id: row.account_id).active.with_permission(STATUS_PERMISSION).to_a
      rescue StandardError => e
        Rails.logger.error("[Platform::Status::Escalation] recipient lookup failed: #{e.class}: #{e.message}")
        []
      end

      def create_notification(user, row, severity:, title:, message:)
        ::Notification.create_for_user(
          user,
          type: NOTIFICATION_TYPE,
          title: title,
          message: message,
          severity: severity,
          category: NOTIFICATION_CATEGORY,
          metadata: {
            "component_kind" => row.component_kind,
            "component_ref" => row.component_ref,
            "component_status_id" => row.id,
            "verdict" => row.verdict
          }
        )
      rescue StandardError => e
        Rails.logger.error("[Platform::Status::Escalation] notification failed: #{e.class}: #{e.message}")
        nil
      end

      def degraded_rows(account)
        ComponentStatus.where(account_id: account.id, verdict: ComponentStatus::DEGRADED)
      end

      # WHEN did this component enter its current verdict.
      #
      # Two sources, and the LATER of the two wins.
      #
      # 1. The row's own conditions: the earliest transition among the
      #    conditions that ARGUE FOR the current verdict. No query, and no
      #    dependence on how long `Platform::StatusEvent` rows are retained.
      #
      # 2. The most recent status event that recorded entry INTO this verdict.
      #
      # Source 1 alone OVERSTATES after an improvement. `Condition.build`
      # inherits `last_transition_at` whenever a condition's STATUS is
      # unchanged, and it does not look at severity — so a condition that was
      # `false` at severity `down` for three hours and softened to severity
      # `degraded` a minute ago keeps its three-hour-old timestamp. The
      # component has genuinely been unhealthy that long, but it has been
      # DEGRADED for one minute, and a message reading "has been degraded for
      # 180 minutes" is simply false. Taking the later of the two corrects it
      # whenever the event exists.
      #
      # Source 2 alone is not usable on its own: events are pruned on a
      # retention window, so an outage older than the window would report no
      # entry at all and a long-degraded component would go unnoticed. Hence
      # `max` over whichever of the two are available, and the condition-derived
      # time as the fallback when the event has aged out — the documented,
      # slightly pessimistic answer rather than silence.
      #
      # Nil when neither source can say, which should not happen; the caller
      # then does NOT notify. A dwell we cannot establish is not a dwell we may
      # assume has elapsed.
      def degraded_since(row)
        [ condition_derived_since(row), entered_verdict_at(row) ].compact.max
      end

      def condition_derived_since(row)
        Array(row.conditions).filter_map do |condition|
          next unless Condition.verdict_for(condition) == row.verdict

          parse_time(condition["last_transition_at"] || condition[:last_transition_at])
        end.min
      end

      # The last time an event recorded this row ARRIVING at its current
      # verdict. Nil when no such event survives retention.
      def entered_verdict_at(row)
        StatusEvent.where(component_status_id: row.id, to_verdict: row.verdict)
                   .order(occurred_at: :desc)
                   .limit(1)
                   .pick(:occurred_at)
      rescue StandardError => e
        Rails.logger.error("[Platform::Status::Escalation] verdict-entry lookup failed: #{e.class}: #{e.message}")
        nil
      end

      def down_message(row)
        "**#{row.component_kind.humanize}** `#{row.display_name.presence || row.component_ref}` " \
          "is **down**.\n\n#{reason_summary(row)}"
      end

      def degraded_message(row, since)
        minutes = ((@now - since) / 60).floor
        "**#{row.component_kind.humanize}** `#{row.display_name.presence || row.component_ref}` " \
          "has been **degraded** for #{minutes} minutes.\n\n#{reason_summary(row)}"
      end

      # The reason TOKENS, not prose: they are the stable, greppable half of a
      # condition and the thing a runbook keys on.
      def reason_summary(row)
        reasons = Array(row.conditions).filter_map do |condition|
          next unless Condition.verdict_for(condition) == row.verdict

          condition["reason"] || condition[:reason]
        end.uniq

        return "No condition explains the verdict." if reasons.empty?

        "Reasons: #{reasons.join(', ')}"
      end

      def parse_time(value)
        case value
        when nil then nil
        when Time, ActiveSupport::TimeWithZone then value
        when DateTime then value.to_time
        else Time.zone.parse(value.to_s)
        end
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end

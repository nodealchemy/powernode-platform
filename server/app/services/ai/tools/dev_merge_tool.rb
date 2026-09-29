# frozen_string_literal: true

module Ai
  module Tools
    # dev_merge_increment — the governed way to land a reviewed dev-loop
    # increment (IMP-e82f619dde7a). Before it, landing one on develop and
    # bumping the parent's submodule pointer was raw git plumbing run by hand
    # (a push of <sha>:refs/heads/develop, then a commit-tree built through a
    # temporary index), pushed to each remote separately. Nothing recorded who
    # approved it or what gate results it rested on.
    #
    # The call PARKS. It opens an Ai::DeferredOperation under dev.merge that
    # replays through Ai::Executors::DeferredToolCall. Only the approved replay
    # does anything, and all it does is hand the merge to the WORKER
    # (Git::DevMergeIncrementJob) over the HTTP boundary. The Rails process runs
    # no git, and no job class lives in the server.
    #
    #   develop            require_approval. The replay refuses without an
    #                      approved request, so an auto_approve row cannot
    #                      turn this into an unattended merge. Because the
    #                      verb is declared destructive,
    #                      Ai::Approvals::HumanSessionPolicy also asks for a
    #                      person's session by default; an account lifts that
    #                      for develop only with a dev.merge policy row whose
    #                      conditions carry requires_human_session: false.
    #   release/*, master  requires_human_session, flagged on the call. It
    #                      parks for a person's own session and runs as that
    #                      person; no policy row lifts the flag.
    #
    # The worker verifies that the source ref still resolves to
    # expected_source_sha, fast-forwards the target only (never forces),
    # optionally moves ONE gitlink in a parent repository, and pushes to every
    # configured remote (the repository plus the mirrors named in its
    # metadata). It reports back to Api::V1::Internal::Ai::DevMergesController,
    # which writes the audit row. A push that reached only some remotes is
    # FAILED.
    #
    # Running the verification gate is the caller's job, not this verb's. The
    # caller attests to its results in `gate_attestation`, and they are carried
    # verbatim onto the approval card and into the audit rows.
    class DevMergeTool < BaseTool
      REQUIRED_PERMISSION = "devops.repositories.write"

      ACTION = "dev_merge_increment"
      ACTION_CATEGORY = "dev.merge"
      EXECUTOR_CLASS = "Ai::Executors::DeferredToolCall"
      JOB_CLASS = "Git::DevMergeIncrementJob"
      JOB_QUEUE = "services"

      # The worker repeats SHA, REF, TARGET_BRANCH and SUBMODULE_PATH literally
      # (Devops::IncrementMergeService); dev_merge_tool_spec pins each pair.
      SHA = %r{\A\h{40}\z}
      # A branch name git accepts that also cannot be read as an option: no
      # leading "-", no "..", "//", "@{", whitespace, and no trailing "/", "."
      # or ".lock".
      REF = %r{\A(?!.*\.\.)(?!.*//)(?!.*@\{)(?!.*\.lock\z)[A-Za-z0-9][A-Za-z0-9._/-]*(?<![/.])\z}
      RELEASE_BRANCH = %r{\Arelease/[A-Za-z0-9][A-Za-z0-9._-]*\z}
      # Every target a merge may land on. The worker re-checks the SAME literal
      # (Devops::IncrementMergeService::TARGET_BRANCH) before any git runs;
      # dev_merge_tool_spec pins the two equal.
      TARGET_BRANCH = %r{\A(?:develop|master|release/[A-Za-z0-9][A-Za-z0-9._-]*)\z}
      SUBMODULE_PATH = %r{\A(?!-)(?!.*(?:\A|/)\.{1,2}(?:/|\z))[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*\z}
      SUMMARY_MAX = 200

      # gate_attestation is copied verbatim into the parked operation, the
      # approval card and two audit rows, so it is bounded: the shape is
      # dev_complete_task's evidence block (an object of scalars, whose values
      # may be one more object of scalars or a list of them), with caps on
      # keys, strings, lists and the whole document.
      ATTESTATION_MAX_KEYS = 16
      ATTESTATION_MAX_KEY = 64
      ATTESTATION_MAX_STRING = 500
      ATTESTATION_MAX_LIST = 10
      ATTESTATION_MAX_BYTES = 8192
      ATTESTATION_MAX_DEPTH = 2

      # A committer for the pointer-bump commit when the replay runs as no
      # person (an agent or an in-process caller). The .invalid TLD is reserved
      # and never resolves.
      FALLBACK_COMMITTER = { "name" => "Powernode Dev Loop", "email" => "dev-loop@powernode.invalid" }.freeze

      declare_action ACTION, mutating: true, destructive: true, gated_in_call: true,
                             returns: "pending: true with the approval request; the approved replay returns " \
                                      "dispatched: true and the remotes the worker will push to",
                             refuses: [
                               "target_branch is not develop, master or release/*",
                               "expected_source_sha is not a full 40-character SHA",
                               "the repository or a configured mirror is not active in this account",
                               "a pointer_bump summary carries AI attribution or names a private extension",
                               "gate_attestation is missing, or outside its bounds (at most 16 keys per object, " \
                               "objects two levels deep, lists of 10, strings of 500 characters, 8 KB in all)",
                               "the caller (person, or an agent through its creator) lacks devops.repositories.write",
                               "a remote's clone URL is not https with a host and no userinfo",
                               "this host cannot tell which private extensions exist (declare them in the " \
                               "protected site setting dev_merge.private_extension_names; [] declares none)",
                               "on the approved replay, the remote set differs from the one pinned at park"
                             ]

      def self.definition
        {
          name: ACTION,
          description: "Land a reviewed dev-loop increment: fast-forward target_branch to expected_source_sha " \
                       "and push to every configured remote, optionally bumping a parent's submodule pointer. " \
                       "Parks for approval; nothing merges until it is approved.",
          parameters: action_definitions[ACTION][:parameters]
        }
      end

      def self.action_definitions
        {
          ACTION => {
            description: "Land a reviewed dev-loop increment on develop, release/* or master. PARKS under " \
                         "dev.merge and does nothing until approved by a person in their own session: develop " \
                         "requires a human session by default, and an account can relax develop ONLY with a " \
                         "dev.merge intervention policy row whose conditions are " \
                         "{requires_human_session: false}; release/* and master always require one, and the merge " \
                         "then runs as the person who approved it. On approval the worker checks that source_ref still resolves to " \
                         "expected_source_sha and refuses if it moved. It fast-forwards target_branch only and " \
                         "never forces: each remote's head is re-read immediately before its push, and a remote " \
                         "that moved to a non-ancestor is refused. It pushes to the repository and to every " \
                         "mirror configured on it, and reports each remote; a push that reached only some remotes " \
                         "is recorded as failed. With pointer_bump it also moves ONE gitlink (submodule_path) in " \
                         "parent_repository to the merged SHA, commits with a generated message, and pushes that " \
                         "the same way. A message that would carry AI attribution or name a private extension is " \
                         "refused, never rewritten. The caller runs the verification gate and attests to it in gate_attestation.",
            parameters: {
              repository: { type: "string", required: true,
                            description: "Devops git repository id or full_name (owner/name) in this account" },
              source_ref: { type: "string", required: true,
                            description: "Branch holding the reviewed increment" },
              target_branch: { type: "string", required: true,
                               description: "develop, master, or release/<version>" },
              expected_source_sha: { type: "string", required: true,
                                     description: "The full 40-character SHA that was reviewed. Refused if " \
                                                  "source_ref no longer resolves to it." },
              pointer_bump: { type: "object", required: false,
                              description: "Optional: { parent_repository, submodule_path, summary? }. Moves " \
                                           "the gitlink at submodule_path in parent_repository's target_branch " \
                                           "to the merged SHA. summary replaces the submodule's commit subject " \
                                           "in the generated message; it may carry no AI attribution and name " \
                                           "no private extension." },
              gate_attestation: { type: "object", required: true,
                                  description: "The verification gate results you ran, e.g. { \"framework\": " \
                                               "\"rspec\", \"passed\": 173, \"failed\": 0, \"command\": \"...\" }. " \
                                               "Recorded verbatim on the approval card and in the audit rows." }
            }
          }
        }
      end

      # A caller's request, validated. Built on the call AND again on the
      # replay: an approval made hours ago does not re-validate a repository
      # that has since been archived or a mirror that has since been removed.
      Plan = Struct.new(:repository, :remotes, :source_ref, :target_branch, :expected_source_sha,
                        :pointer_bump, :gate_attestation, :forbidden_names, keyword_init: true) do
        def protected_target?
          DevMergeTool.protected_target?(target_branch)
        end

        # The exact remotes this plan pushes to, ids and names (never a URL or
        # a credential): pinned into the parked call and shown to the approver.
        def pinned_remotes
          pin = ->(repos) { repos.map { |r| { "id" => r.id.to_s, "full_name" => r.full_name } } }
          { "repository" => pin.call(remotes), "parent" => pointer_bump && pin.call(pointer_bump[:remotes]) }.compact
        end
      end

      # Written by the tool into the parked call; never taken from a caller
      # (#park overwrites whatever a caller put there).
      PINNED_KEY = "_pinned_remotes"

      def self.protected_target?(branch)
        branch == "master" || branch.to_s.match?(RELEASE_BRANCH)
      end

      def call(params)
        return error_result("permission denied: #{REQUIRED_PERMISSION} required") unless caller_permitted?
        return halted_result if account.ai_suspended?

        plan, refusal = build_plan(params)
        return error_result(refusal) if refusal

        return dispatch(plan, params) if approved_replay?

        park(plan, params)
      end

      private

      # The same permission for every principal type, checked before
      # anything parks: a person holds it; an agent (with no person) is held
      # to it through its creator's role, the platform's agent seam
      # (BaseTool.permitted?). An instance principal never reaches here (the
      # *dev_merge* deny overlay refuses it first) and is refused if it does;
      # an in-process caller is trusted by construction; anything else is
      # refused.
      def caller_permitted?
        return true if internal?
        return false if instance_authorized?
        return user.has_permission?(REQUIRED_PERMISSION) == true if user
        return self.class.permitted?(agent: agent) if agent

        false
      end

      def halted_result
        error_result("AI is suspended for this account (kill switch); nothing was merged.")
      end

      # ---- validation -------------------------------------------------------

      def build_plan(params)
        p = params.to_h.with_indifferent_access

        source_ref = p[:source_ref].to_s
        target = p[:target_branch].to_s
        sha = p[:expected_source_sha].to_s.downcase
        return [ nil, "source_ref is not a valid branch name" ] unless source_ref.match?(REF)
        return [ nil, "target_branch must be develop, master or release/<version>" ] unless allowed_target?(target)
        return [ nil, "expected_source_sha must be a full 40-character SHA" ] unless sha.match?(SHA)

        attestation = p[:gate_attestation]
        attestation = attestation.to_unsafe_h if attestation.respond_to?(:to_unsafe_h)
        unless attestation.is_a?(Hash) && attestation.present?
          return [ nil, "gate_attestation is required: attest to the verification gate you ran" ]
        end
        if (problem = attestation_problem(attestation))
          return [ nil, "gate_attestation #{problem}" ]
        end

        names = ::Ai::DevMerge::ForbiddenNames.resolve
        return [ nil, names.reason ] unless names.determinate?

        repository, remotes, refusal = resolve_repository(p[:repository], label: "repository")
        return [ nil, refusal ] if refusal

        pointer_bump = nil
        if p[:pointer_bump].present?
          pointer_bump, refusal = build_pointer_bump(p[:pointer_bump], forbidden_names: names.names)
          return [ nil, refusal ] if refusal
        end

        [ Plan.new(repository: repository, remotes: remotes, source_ref: source_ref, target_branch: target,
                   expected_source_sha: sha, pointer_bump: pointer_bump,
                   gate_attestation: attestation.deep_stringify_keys, forbidden_names: names.names), nil ]
      end

      # nil when the attestation fits its bounds, else what is wrong with it.
      def attestation_problem(attestation)
        problem = attestation_shape_problem(attestation, 0)
        return problem if problem
        return nil if attestation.to_json.bytesize <= ATTESTATION_MAX_BYTES

        "is over #{ATTESTATION_MAX_BYTES} bytes"
      end

      def attestation_shape_problem(value, depth)
        case value
        when Hash
          return "nests objects deeper than #{ATTESTATION_MAX_DEPTH} levels" if depth >= ATTESTATION_MAX_DEPTH
          return "has an object with more than #{ATTESTATION_MAX_KEYS} keys" if value.size > ATTESTATION_MAX_KEYS

          value.each do |key, inner|
            return "has a key longer than #{ATTESTATION_MAX_KEY} characters" if key.to_s.length > ATTESTATION_MAX_KEY

            problem = attestation_shape_problem(inner, depth + 1)
            return problem if problem
          end
          nil
        when Array
          return "has a list inside a list" if value.any?(Array)
          return "has a list longer than #{ATTESTATION_MAX_LIST} items" if value.size > ATTESTATION_MAX_LIST

          value.each do |item|
            # A list's items sit at the list's own level: a list of suite
            # objects is the same depth as a single suite object.
            problem = attestation_shape_problem(item, depth)
            return problem if problem
          end
          nil
        when String
          value.length > ATTESTATION_MAX_STRING ? "has a string longer than #{ATTESTATION_MAX_STRING} characters" : nil
        when Integer, Float, true, false, nil
          nil
        else
          "has a value that is not a JSON string, number, boolean or null"
        end
      end

      def allowed_target?(target)
        target.match?(TARGET_BRANCH)
      end

      def build_pointer_bump(raw, forbidden_names:)
        bump = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        return [ nil, "pointer_bump must be an object" ] unless bump.is_a?(Hash)

        bump = bump.with_indifferent_access
        path = bump[:submodule_path].to_s
        return [ nil, "pointer_bump.submodule_path is not a valid relative path" ] unless path.match?(SUBMODULE_PATH)

        summary = bump[:summary].to_s.strip.presence
        if summary
          return [ nil, "pointer_bump.summary must be one line" ] if summary.include?("\n") || summary.include?("\r")
          return [ nil, "pointer_bump.summary is over #{SUMMARY_MAX} characters" ] if summary.length > SUMMARY_MAX

          violation = ::Ai::DevMerge::CommitMessagePolicy.violation(summary, forbidden_names: forbidden_names)
          return [ nil, "pointer_bump.summary is refused: #{violation}" ] if violation
        end

        parent, remotes, refusal = resolve_repository(bump[:parent_repository], label: "pointer_bump.parent_repository")
        return [ nil, refusal ] if refusal

        [ { parent: parent, remotes: remotes, submodule_path: path, summary: summary }, nil ]
      end

      # The repository and every mirror configured on it, all active and all in
      # THIS account. A configured mirror that does not resolve is a refusal,
      # never a skip: pushing to fewer remotes than configured is the partial
      # push this verb exists to rule out.
      def resolve_repository(ref, label:)
        key = ref.to_s.strip
        return [ nil, nil, "#{label} is required" ] if key.empty?

        scope = ::Devops::GitRepository.where(account_id: account.id)
        repository = (key.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) && scope.find_by(id: key)) ||
                     scope.find_by(full_name: key)
        return [ nil, nil, "#{label} '#{key}' is not a repository in this account" ] if repository.nil?
        return [ nil, nil, "#{label} '#{key}' is not active" ] unless pushable?(repository)

        mirror_ids = repository.push_mirror_repository_ids
        mirrors = scope.where(id: mirror_ids).to_a
        missing = mirror_ids - mirrors.map { |m| m.id.to_s }
        inactive = mirrors.reject { |m| pushable?(m) }
        if missing.any? || inactive.any?
          return [ nil, nil, "#{label} '#{key}' names a mirror that is not an active repository in this account " \
                             "(#{(missing + inactive.map(&:id)).join(', ')}); refusing to push to fewer remotes " \
                             "than configured" ]
        end

        remotes = [ repository, *mirrors.sort_by { |m| mirror_ids.index(m.id.to_s) } ]
        bad_url = remotes.find { |r| !https_clone_url?(r.clone_url) }
        if bad_url
          return [ nil, nil, "#{label} remote #{bad_url.full_name} has a clone URL that is not https with a host " \
                             "and no userinfo; refusing to send a credential to it" ]
        end

        [ repository, remotes, nil ]
      end

      def pushable?(repository)
        repository.is_active && !repository.is_archived
      end

      # The worker sends the credential as a header on every request git makes
      # to this URL, so only https with a host and no userinfo is accepted.
      # The worker applies the same rule (Git::DevMergeIncrementJob), and its
      # git allows the https transport only.
      def https_clone_url?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
      rescue URI::InvalidURIError
        false
      end

      # ---- park --------------------------------------------------------------

      def park(plan, params)
        protected_target = plan.protected_target?
        descriptor = caller_principal_descriptor(ACTION)
        if descriptor["kind"] == "unattributed" && !protected_target
          return error_result("#{ACTION} cannot be parked for an unattributed caller " \
                              "(#{descriptor['detail']}): an approval granted for it could never be replayed")
        end

        gate = ::Ai::AutonomyGate.evaluate(
          action_category: ACTION_CATEGORY,
          executor_class: EXECUTOR_CLASS,
          params: ::Ai::Executors::DeferredToolCall.pack(
            tool_class: self.class.name, action: ACTION,
            tool_params: params.to_h.deep_stringify_keys.merge(PINNED_KEY => plan.pinned_remotes),
            principal: descriptor, human_only: protected_target
          ),
          account: account,
          agent: agent,
          requested_by: user,
          description: approval_description(plan),
          **(protected_target ? { requires_human_session: true } : {}),
          **(call_origin ? { call_origin: call_origin } : {}),
          **(machine_call? ? { agent_initiated: true } : {})
        )

        case gate.decision
        when :pending
          # What the parked request really needs, not only what this call
          # flagged: Ai::Approvals::HumanSessionPolicy also answers from the
          # destructive declaration and the account's own policy rows, so a
          # develop merge can need a person's session too.
          needs_person = protected_target || gate.approval_request&.requires_human_session? == true
          success_result(
            self.class.pending_payload(
              action_category: ACTION_CATEGORY,
              deferred_operation: gate.deferred_operation,
              approval_request: gate.approval_request,
              message: (HUMAN_CONFIRMATION_MESSAGE if needs_person),
              requires_human_session: needs_person
            )
          )
        when :proceed
          # An auto_approve row ran the replay inline. The replay refused,
          # because no approval exists; hand back that refusal, never a success.
          gate.result.is_a?(::Hash) ? gate.result : error_result("#{ACTION} needs an approved request; refusing.")
        else
          error_result(gate.error || "Action #{ACTION_CATEGORY} is blocked by policy")
        end
      end

      # What the approver reads. Refs and SHAs are not secret, and the approver
      # needs exactly these to decide.
      def approval_description(plan)
        text = "#{ACTION}: #{plan.repository.full_name} #{plan.source_ref}@#{plan.expected_source_sha[0, 12]} " \
               "-> #{plan.target_branch}; pushes to #{plan.remotes.map(&:full_name).join(', ')}"
        return text unless plan.pointer_bump

        "#{text}; bump #{plan.pointer_bump[:parent].full_name}:#{plan.pointer_bump[:submodule_path]} " \
          "on #{plan.pointer_bump[:remotes].map(&:full_name).join(', ')}"
      end

      # ---- approved replay ---------------------------------------------------

      def dispatch(plan, params)
        operation = @replaying_operation
        request = operation.try(:approval_request)
        unless request.respond_to?(:approved?) && request.approved?
          return error_result("#{ACTION} runs only after its request is approved, and there is no approved " \
                              "request; nothing was merged.")
        end
        if plan.protected_target? && !human_confirmed_replay?
          return error_result("#{ACTION} onto #{plan.target_branch} runs only as the person who approved it in " \
                              "their own session; nothing was merged.")
        end

        # What was approved is what runs: the remotes resolved now must be the
        # remotes pinned when the call parked.
        pinned = params.to_h.deep_stringify_keys[PINNED_KEY]
        unless pinned == plan.pinned_remotes
          return error_result("#{ACTION}: the remote set changed since approval was asked for; nothing was " \
                              "merged. Park it again so the new remotes are approved.")
        end

        payload = job_payload(plan, operation)
        # Written BEFORE the enqueue: this row is also the dispatch marker the
        # worker's report is checked against (Api::V1::Internal::Ai::
        # DevMergesController), so it exists before the worker can report.
        audit!("dev_merge.dispatched", operation, dispatch_metadata(plan, payload))

        response = ::WorkerJobService.enqueue_job(JOB_CLASS, args: [ payload ], queue: JOB_QUEUE)
        success_result(
          dispatched: true,
          deferred_operation_id: operation.id,
          job_id: response.is_a?(::Hash) ? response.dig("data", "job_id") : nil,
          remotes: payload["remotes"],
          pointer_remotes: payload.dig("pointer_bump", "remotes")
        )
      rescue ::WorkerJobService::WorkerNotSentError, ::WorkerJobService::WorkerRejectedError => e
        Rails.logger.error("[DevMergeTool] dispatch not sent for #{operation&.id}: #{e.class}")
        error_result("#{ACTION} was approved but the worker did not accept it; nothing was merged. " \
                     "Park it again to retry.")
      rescue ::WorkerJobService::WorkerOutcomeUnknownError, ::WorkerJobService::WorkerResponseUnparseableError => e
        Rails.logger.error("[DevMergeTool] dispatch outcome unknown for #{operation&.id}: #{e.class}")
        error_result("#{ACTION} was approved but whether the worker accepted it is unknown; do NOT re-park " \
                     "before checking the target branch and the dev_merge audit rows.")
      end

      def job_payload(plan, operation)
        payload = {
          "deferred_operation_id" => operation.id,
          "account_id" => account.id,
          "source_ref" => plan.source_ref,
          "target_branch" => plan.target_branch,
          "expected_source_sha" => plan.expected_source_sha,
          "remotes" => plan.remotes.map { |r| remote_descriptor(r) },
          "committer" => committer,
          # Private-extension names (Ai::DevMerge::ForbiddenNames), so the
          # worker can refuse a landed commit or a generated message naming
          # one. Never written to an audit row.
          "forbidden_names" => plan.forbidden_names
        }
        return payload unless plan.pointer_bump

        payload.merge(
          "pointer_bump" => {
            "parent_repository_id" => plan.pointer_bump[:parent].id,
            "submodule_path" => plan.pointer_bump[:submodule_path],
            "summary" => plan.pointer_bump[:summary],
            "remotes" => plan.pointer_bump[:remotes].map { |r| remote_descriptor(r) }
          }.compact
        )
      end

      def remote_descriptor(repository)
        {
          "repository_id" => repository.id,
          "full_name" => repository.full_name,
          "provider_type" => repository.provider_type
        }
      end

      def committer
        return FALLBACK_COMMITTER.dup if user.nil? || user.email.blank?

        name = user.respond_to?(:full_name) ? user.full_name.presence : nil
        { "name" => name || user.email, "email" => user.email }
      end

      def dispatch_metadata(plan, payload)
        {
          "repository" => { "id" => plan.repository.id, "full_name" => plan.repository.full_name },
          "source_ref" => plan.source_ref,
          "target_branch" => plan.target_branch,
          "expected_source_sha" => plan.expected_source_sha,
          "remotes" => payload["remotes"],
          "pointer_bump" => payload["pointer_bump"]&.except("summary"),
          "gate_attestation" => plan.gate_attestation,
          "requires_human_session" => plan.protected_target?
        }.compact
      end

      # Fail CLOSED: a merge whose dispatch cannot be recorded is not dispatched.
      def audit!(action, operation, metadata)
        ::AuditLog.log_action(action: action, resource: operation, account: account, user: user,
                              source: "automation", severity: "high", risk_level: "high",
                              metadata: metadata)
      end
    end
  end
end

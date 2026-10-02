# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:driver) { described_class.new(account: account, user: user) }

  describe "#start" do
    it "creates an active campaign with a dedicated campaign-scoped Ralph loop + first snapshot" do
      result = driver.start(name: "Improve billing", decision_authority: "trusted",
                            configuration: { "scope" => { "trees" => ["server/app"] } })
      campaign = result[:campaign]
      loop = result[:loop]

      expect(campaign).to be_persisted
      expect(campaign.status).to eq("active")
      expect(campaign.decision_authority).to eq("trusted")
      expect(campaign.created_by_id).to eq(user.id)
      expect(loop.campaign_id).to eq(campaign.id)
      expect(loop.branch).to eq("campaign/#{campaign.id}")
      expect(loop.configuration["workload"]).to eq("improvement-campaign")
      expect(campaign.progress_entries.count).to eq(1)
    end

    it "seeds a default acceptance-rate floor (G2) when the caller sets none" do
      campaign = driver.start(name: "Defaults")[:campaign]
      expect(campaign.stop_conditions["min_acceptance_pct"]).to eq(50)
    end

    it "lets a caller-supplied stop condition override the default floor" do
      campaign = driver.start(name: "Override", stop_conditions: { "min_acceptance_pct" => 80, "max_failed" => 3 })[:campaign]
      expect(campaign.stop_conditions["min_acceptance_pct"]).to eq(80)
      expect(campaign.stop_conditions["max_failed"]).to eq(3)
    end

    context "plan_increments seeding" do
      it "seeds one pending task per planned increment so total_tasks reflects the plan" do
        result = driver.start(
          name: "Planned",
          configuration: { "plan_increments" => ["First thing", { "title" => "Second thing", "description" => "do B" }] }
        )
        campaign = result[:campaign]
        loop = result[:loop]

        expect(loop.ralph_tasks.where(status: "pending").count).to eq(2)
        expect(loop.ralph_tasks.pluck(:task_key)).to contain_exactly("increment-first-thing", "increment-second-thing")
        expect(loop.ralph_tasks.find_by(task_key: "increment-second-thing").description).to eq("do B")
        expect(campaign.reload.total_tasks).to eq(2)
        expect(campaign.completion_pct).to eq(0.0)
      end

      it "honors an explicit task_key and disambiguates duplicate keys within the plan" do
        loop = driver.start(
          name: "Keys",
          configuration: { "plan_increments" => [{ "title" => "Custom", "task_key" => "kx" }, "Dup", "Dup"] }
        )[:loop]
        expect(loop.ralph_tasks.pluck(:task_key)).to contain_exactly("kx", "increment-dup", "increment-dup-2")
      end

      it "seeds no tasks when plan_increments is absent (unchanged behavior)" do
        loop = driver.start(name: "Bare")[:loop]
        expect(loop.ralph_tasks.count).to eq(0)
      end

      it "a passed first increment on a 15-plan campaign reads ~6.7%, not 100%, and does not finalize while active" do
        increments = (1..15).map { |n| "Increment #{n}" }
        campaign = driver.start(
          name: "Fifteen",
          configuration: { "plan_increments" => increments },
          stop_conditions: { "completion_pct" => 100 }
        )[:campaign]

        driver.record_increment!(campaign, title: "Increment 1")

        campaign.reload
        expect(campaign.total_tasks).to eq(15)
        expect(campaign.completed_tasks).to eq(1)
        expect(campaign.completion_pct).to be_within(0.01).of(6.67)
        expect(campaign.status).to eq("active")
      end

      # IMP-edf58df219cf: seed_plan_increments! previously created each RalphTask
      # with only task_key/description/status/position, dropping any files /
      # acceptance_criteria / dependencies the increment Hash supplied. "files"
      # is not a guessed key — it is the exact metadata sub-key
      # Ai::Tools::DevLoopTool#task_files already reads for the parallel-claim
      # collision guard; acceptance_criteria/dependencies are RalphTask's own
      # column names.
      # Entries that are not strings (nil, 42) are no longer normalised away here: a plan
      # carrying one is refused when the campaign is created (IMP-fd7e7082b431,
      # Ai::Campaigns::PlanIncrements), so what reaches the driver is strings.
      it "carries increment files into metadata.files, normalized (strings, unique, blanks dropped)" do
        loop = driver.start(
          name: "Files",
          configuration: {
            "plan_increments" => [
              { "title" => "First", "files" => [ "b.rb", "a.rb", "a.rb", "", " c.rb " ] }
            ]
          }
        )[:loop]

        task = loop.ralph_tasks.find_by(task_key: "increment-first")
        expect(task.metadata["files"]).to eq(%w[b.rb a.rb c.rb])
      end

      it "seeds an empty files list (not a missing key) when the increment declares none" do
        loop = driver.start(
          name: "NoFiles",
          configuration: { "plan_increments" => [ "Untracked increment" ] }
        )[:loop]

        task = loop.ralph_tasks.find_by(task_key: "increment-untracked-increment")
        expect(task.metadata["files"]).to eq([])
      end

      it "carries acceptance_criteria and dependencies onto the seeded RalphTask's own columns" do
        loop = driver.start(
          name: "Criteria",
          configuration: {
            "plan_increments" => [
              { "title" => "First", "task_key" => "first" },
              { "title" => "Second", "task_key" => "second",
                "acceptance_criteria" => "Do the thing", "dependencies" => [ "first" ] }
            ]
          }
        )[:loop]

        second = loop.ralph_tasks.find_by(task_key: "second")
        expect(second.acceptance_criteria).to eq("Do the thing")
        expect(second.dependencies).to eq([ "first" ])
      end
    end
  end

  describe "#status" do
    it "returns the campaign summary, open questions, recent decisions, and loops" do
      campaign = driver.start(name: "X")[:campaign]
      campaign.park_question!(question: "Free-tier pricing policy?")
      campaign.record_decision!(decision_type: "remove", title: "drop dead code")

      st = driver.status(campaign)
      expect(st[:campaign][:name]).to eq("X")
      expect(st[:open_questions].size).to eq(1)
      expect(st[:recent_decisions].size).to eq(1)
      expect(st[:loops].size).to eq(1)
    end
  end

  describe "#claim / #release (single-driver lease)" do
    it "claims a free campaign, blocks a second driver, and frees it on release" do
      campaign = driver.start(name: "X")[:campaign]
      # A competing driver that may drive (claim now asks ai.campaigns.manage): the lease,
      # not the permission, is what blocks it here.
      other = described_class.new(account: account,
                                  user: create(:user, account: account, permissions: %w[ai.campaigns.manage]))

      first = driver.claim(campaign, holder: "sess-a")
      expect(first[:ok]).to be true
      expect(first[:lease]).to include(holder: "sess-a")

      blocked = other.claim(campaign, holder: "sess-b")
      expect(blocked[:ok]).to be false
      expect(blocked[:held_by]).to eq("sess-a")

      expect(driver.release(campaign, holder: "sess-a")).to eq({ ok: true })
      expect(other.claim(campaign, holder: "sess-b")[:ok]).to be true
    end

    it "defaults the holder to the driver's user id" do
      campaign = driver.start(name: "X")[:campaign]
      res = driver.claim(campaign)
      expect(res[:ok]).to be true
      expect(campaign.reload.driver_lease_holder).to eq(user.id.to_s)
    end
  end

  describe "#answer_question" do
    it "answers a parked question and clears the open count" do
      campaign = driver.start(name: "X")[:campaign]
      q = campaign.park_question!(question: "Stripe or PayPal for payouts?")

      res = driver.answer_question(campaign, question_id: q.id, answer: "Stripe Connect")
      expect(res[:status]).to eq("answered")
      expect(res[:answer]).to eq("Stripe Connect")
      expect(campaign.reload.open_questions).to eq(0)
    end
  end

  describe "#stop" do
    it "pauses the campaign's loops and marks it completed" do
      campaign = driver.start(name: "X")[:campaign]
      driver.stop(campaign, summary: "shipped")

      expect(campaign.reload.status).to eq("completed")
      expect(campaign.completion_summary).to eq("shipped")
      expect(campaign.ralph_loops.first.reload.schedule_paused).to be true
    end

    # IMP-3e36e30d5c72: #stop never transitioned the LOOP — only the campaign. Loops
    # stayed status="running" forever, since only the iteration-drain path ever called
    # RalphLoop#complete! and the API only ever exposed #cancel.
    it "closes a loop whose tasks are all passed or skipped as completed" do
      campaign = driver.start(name: "AllDone")[:campaign]
      loop = campaign.ralph_loops.first
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t2", status: "skipped")
      loop.start!

      driver.stop(campaign, summary: "shipped")

      expect(loop.reload.status).to eq("completed")
    end

    it "cancels a loop with leftover work instead, keeping its tasks untouched and visible" do
      campaign = driver.start(name: "Leftover")[:campaign]
      loop = campaign.ralph_loops.first
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t2", status: "pending")
      loop.start!

      driver.stop(campaign, summary: "cutting it short")

      loop.reload
      expect(loop.status).to eq("cancelled")
      expect(loop.configuration["cancellation_reason"]).to eq("campaign stopped: cutting it short")
      expect(loop.ralph_tasks.pluck(:task_key, :status)).to contain_exactly(%w[t1 passed], %w[t2 pending])
    end

    it "cancels a pending (never-started) loop rather than raising, even though zero tasks trivially satisfy 'all terminal'" do
      campaign = driver.start(name: "NeverStarted")[:campaign]
      loop = campaign.ralph_loops.first
      expect(loop.status).to eq("pending")

      expect { driver.stop(campaign, summary: "shipped") }.not_to raise_error

      expect(loop.reload.status).to eq("cancelled")
    end

    it "a second stop is a no-op at the loop level (idempotent)" do
      campaign = driver.start(name: "Twice")[:campaign]
      loop = campaign.ralph_loops.first
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
      loop.start!

      driver.stop(campaign, summary: "first")
      completed_at = loop.reload.completed_at

      expect { driver.stop(campaign, summary: "second") }.not_to raise_error
      loop.reload
      expect(loop.status).to eq("completed")
      expect(loop.completed_at).to eq(completed_at)
    end

    # IMP-3e36e30d5c72 (review round, item 1): RalphLoop#complete! does NOT raise on a
    # loop with a repeating task — it logs a warning and returns early, leaving the loop
    # exactly as non-terminal as before the call. An "all tasks passed or skipped" loop
    # with one repeating task would otherwise slip through complete! and stay "running"
    # forever — the exact bug this whole task fixes, reappearing one guard downstream.
    it "cancels (rather than leaves running) a clean loop that complete! declines because it has a repeating task" do
      campaign = driver.start(name: "Repeating")[:campaign]
      loop = campaign.ralph_loops.first
      create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed", repeating: true)
      loop.start!

      driver.stop(campaign, summary: "shipped")

      expect(loop.reload.status).to eq("cancelled")
    end
  end

  # IMP-edf58df219cf: drives the REAL dev_next_task path (Ai::Tools::DevLoopTool),
  # not a stub, per the operator's acceptance criteria — via seed_plan_increments!
  # itself (the exact producer under test), on a plain (non-campaign) RalphLoop.
  #
  # RE-VERIFICATION FINDING (findings rot — this one did, partially): a
  # claude_code-driven campaign loop cannot exhibit this "two holders claim two
  # seeded tasks" scenario via dev_next_task, campaign lease or no.
  # Ai::Tools::DevLoopTool#next_task gates every campaign-scoped loop with
  # #delegation_block_reason, which — for the claude_code/external_cli branch —
  # asks Campaign#acquire_driver_lease!(holder:) BEFORE claim_under_lock ever
  # runs, and that lease is keyed on the literal `holder` string: a second call
  # under a DIFFERENT holder than the one currently leasing the campaign is
  # refused with "leased_to:<holder>" regardless of file collision, and a
  # second call under the SAME holder just idempotently reclaims the first task
  # instead of claiming a second. This is NOT universal, though: a
  # PLATFORM-DRIVEN campaign loop takes a different branch of
  # #delegation_block_reason (dev_loop_tool.rb:316, `if
  # loop_record.platform_driven?`) that returns nil — no lease check at all —
  # once the caller is the loop's delegated platform agent, so a
  # platform-driven campaign with two holders and max_concurrent_claims > 1 CAN
  # reach the collision guard. The evidence for part (2) of the brief is
  # therefore narrower than "always inert": raising the DEFAULT cap for
  # claude_code-driven campaign loops would still be dead configuration
  # (unreachable behind the lease), so that default is left alone; whether to
  # raise it for platform-driven loops is a live, separate question this task
  # was not asked to decide (see the report). These specs exercise
  # seed_plan_increments! against a plain RalphLoop (no campaign_id, so no
  # lease gate either way) to prove the GUARD MECHANISM itself now
  # discriminates correctly on the metadata the fix populates — the part of
  # the finding this task can actually verify and fix, independent of which
  # driver_kind a real campaign eventually uses it under.
  describe "seed_plan_increments!'s metadata.files driving the REAL collision guard (IMP-edf58df219cf)" do
    let(:loop) { create(:ai_ralph_loop, account: account) }

    it "lets two holders claim two seeded increments with disjoint declared files, once cap > 1" do
      loop.update!(configuration: { "max_concurrent_claims" => 2 })
      driver.send(:seed_plan_increments!, loop, [
                    { "title" => "First", "task_key" => "first", "files" => [ "a.rb" ] },
                    { "title" => "Second", "task_key" => "second", "files" => [ "b.rb" ] }
                  ])
      tool = Ai::Tools::DevLoopTool.new(account: account, user: user)

      first = tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-a" })
      second = tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-b" })

      expect(first[:task][:task_key]).to eq("first")
      expect(second[:task][:task_key]).to eq("second")
      expect(loop.ralph_tasks.in_progress.count).to eq(2)
    end

    it "still refuses a second holder a seeded increment whose declared files overlap an in-progress one" do
      loop.update!(configuration: { "max_concurrent_claims" => 2 })
      driver.send(:seed_plan_increments!, loop, [
                    { "title" => "First", "task_key" => "first", "files" => [ "a.rb" ] },
                    { "title" => "Second", "task_key" => "second", "files" => [ "a.rb" ] }
                  ])
      tool = Ai::Tools::DevLoopTool.new(account: account, user: user)

      tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-a" })
      second = tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-b" })

      expect(second[:task]).to be_nil
      expect(second[:no_eligible_task]).to be true
      expect(second[:reason]).to eq("file_collision")
      expect(loop.ralph_tasks.in_progress.count).to eq(1)
    end

    # Regression guard: the two specs above both hold before AND after a broken fix
    # (e.g. one that populates metadata.files with the WRONG value, or a files-vs-
    # dependencies mixup) could slip past, since "disjoint succeeds" only proves SOME
    # files landed, and "overlap refused" passes even with metadata.files unpopulated
    # (see the file-level comment). Mixing one increment WITH declared files and one
    # WITHOUT pins the actual guard rule under test: missing files is unconditionally
    # unsafe, so it must refuse even though it isn't "overlapping" the other task's
    # single declared file in any literal sense.
    it "refuses a second holder a seeded increment with NO declared files, next to one that has some" do
      loop.update!(configuration: { "max_concurrent_claims" => 2 })
      driver.send(:seed_plan_increments!, loop, [
                    { "title" => "First", "task_key" => "first", "files" => [ "a.rb" ] },
                    { "title" => "Second", "task_key" => "second" }
                  ])
      tool = Ai::Tools::DevLoopTool.new(account: account, user: user)

      tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-a" })
      second = tool.execute(params: { action: "dev_next_task", loop_id: loop.id, holder: "lane-b" })

      expect(second[:reason]).to eq("file_collision")
    end
  end

  # IMP-edf58df219cf (review round, item 3): dependencies are matched against task_key,
  # which is always parameterized ("Foo Bar" -> "foo-bar") — an unparameterized
  # dependency would never match a row, dependencies_satisfied? reads that as "nothing
  # to wait on", and the declared ordering would be silently lost.
  describe "seed_plan_increments! parameterizes declared dependencies to match task_key (IMP-edf58df219cf)" do
    it "normalizes a title-shaped dependency to the parameterized key it must match" do
      loop = driver.start(
        name: "DepsParam",
        configuration: {
          "plan_increments" => [
            { "title" => "First Thing" },
            { "title" => "Second", "task_key" => "second", "dependencies" => [ "Increment-First Thing" ] }
          ]
        }
      )[:loop]

      second = loop.ralph_tasks.find_by(task_key: "second")
      expect(second.dependencies).to eq([ "increment-first-thing" ])
      expect(second.dependencies_satisfied?).to be false
      expect(second.blocking_dependencies).to eq([ "increment-first-thing" ])
    end
  end
end

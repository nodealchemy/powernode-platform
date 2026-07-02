# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the legacy admin scheduled-task write path
# (Api::V1::Admin::Maintenance::MaintenanceController -> ScheduledTaskService).
#
# That path used to reference phantom columns/associations that do NOT exist on
# ScheduledTask (`:user`/`:executions` associations; `description`,
# `cron_schedule`, `enabled`, `command` attributes), so every admin
# scheduled-task CRUD call raised ActiveModel::UnknownAttributeError /
# ActiveRecord::AssociationNotFoundError -> HTTP 500. The pre-existing controller
# spec stubbed ScheduledTaskService entirely, so the break stayed latent.
#
# These specs exercise the REAL service against the REAL model (no stubbing) and
# pin the mapping onto the real schema: is_active / cron_expression / next_run_at
# and the `parameters` jsonb, with the command living at parameters["command"]
# (the shape the worker-facing controller and Sidekiq executor already expect).
RSpec.describe "Api::V1::Admin::Maintenance scheduled tasks (real service)", type: :request do
  let(:account) { create(:account) }
  let(:admin_user) do
    create(:user, account: account, permissions: [ "admin.maintenance.tasks", "system.admin" ])
  end
  let(:headers) { auth_headers_for(admin_user) }

  describe "GET /api/v1/admin/maintenance/tasks" do
    it "lists tasks without touching the phantom :user/:executions associations" do
      create(:scheduled_task, :data_cleanup, name: "Nightly Cleanup", cron_expression: "0 2 * * *")

      get "/api/v1/admin/maintenance/tasks", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      row = data.find { |t| t["name"] == "Nightly Cleanup" }
      expect(row).to be_present
      expect(row["cron_schedule"]).to eq("0 2 * * *")
      expect(row["enabled"]).to be(true)
    end
  end

  describe "POST /api/v1/admin/maintenance/tasks" do
    it "creates a task mapped onto real columns and computes next_run_at" do
      post "/api/v1/admin/maintenance/tasks",
           params: {
             task: {
               name: "Weekly Report",
               description: "Generate the weekly report",
               cron_schedule: "0 3 * * 0",
               enabled: true,
               type: "report_generation"
             }
           },
           headers: headers, as: :json

      expect_success_response
      task = ScheduledTask.find_by(name: "Weekly Report")
      expect(task).to be_present
      expect(task.task_type).to eq("report_generation")
      expect(task.cron_expression).to eq("0 3 * * 0")
      expect(task.is_active).to be(true)
      expect(task.parameters["description"]).to eq("Generate the weekly report")
      expect(task.next_run_at).to be_present
    end

    it "round-trips a custom_command through parameters[command]" do
      post "/api/v1/admin/maintenance/tasks",
           params: {
             task: {
               name: "Custom Job",
               cron_schedule: "0 4 * * *",
               enabled: true,
               command: "rake cleanup:run",
               type: "custom_command"
             }
           },
           headers: headers, as: :json

      expect_success_response
      task = ScheduledTask.find_by(name: "Custom Job")
      expect(task).to be_present
      expect(task.parameters["command"]).to eq("rake cleanup:run")
      expect(json_response_data["command"]).to eq("rake cleanup:run")
    end
  end

  describe "PATCH /api/v1/admin/maintenance/tasks/:id" do
    it "updates real columns and merges parameters without phantom attrs" do
      task = create(:scheduled_task, :data_cleanup,
        name: "Old Name", is_active: true, cron_expression: "0 1 * * *")

      patch "/api/v1/admin/maintenance/tasks/#{task.id}",
            params: { task: { name: "New Name", enabled: false, cron_schedule: "0 5 * * *" } },
            headers: headers, as: :json

      expect_success_response
      task.reload
      expect(task.name).to eq("New Name")
      expect(task.is_active).to be(false)
      expect(task.cron_expression).to eq("0 5 * * *")
      # existing jsonb config keys are preserved across the update
      expect(task.parameters["days_to_keep"]).to eq(30)
      # disabled tasks are unscheduled (next_run_at cleared)
      expect(task.next_run_at).to be_nil
    end
  end

  describe "custom_command authorization on PATCH /api/v1/admin/maintenance/tasks/:id" do
    # A user who can manage tasks but is NOT a system administrator.
    let(:tasks_only_user) do
      create(:user, account: account, permissions: [ "admin.maintenance.tasks" ])
    end

    it "forbids a non-system.admin user from promoting a task to custom_command" do
      task = create(:scheduled_task, :data_cleanup, name: "Benign", is_active: true)

      patch "/api/v1/admin/maintenance/tasks/#{task.id}",
            params: { task: { type: "custom_command", command: "rm -rf /tmp", enabled: true } },
            headers: auth_headers_for(tasks_only_user), as: :json

      expect_error_response("Custom command tasks require system administrator privileges", 422)
      task.reload
      expect(task.task_type).to eq("data_cleanup")
      expect(task.parameters["command"]).to be_nil
    end

    it "rejects an unsafe command on an existing custom_command task even for system.admin" do
      task = create(:scheduled_task, :custom_command, name: "Cmd Task")

      patch "/api/v1/admin/maintenance/tasks/#{task.id}",
            params: { task: { command: "rm -rf /tmp" } },
            headers: headers, as: :json

      expect_error_response("Invalid command", 422)
      expect(task.reload.parameters["command"]).to eq("echo 'test'")
    end
  end

  describe "enabled coercion on POST /api/v1/admin/maintenance/tasks" do
    it "defaults is_active to true when enabled is sent blank (never a nil that fails validation)" do
      post "/api/v1/admin/maintenance/tasks",
           params: { task: { name: "Blank Enabled", cron_schedule: "0 6 * * *", enabled: "", type: "data_cleanup" } },
           headers: headers, as: :json

      expect_success_response
      expect(ScheduledTask.find_by(name: "Blank Enabled").is_active).to be(true)
    end
  end
end

# frozen_string_literal: true

module AiWorkflowNodeExecution::StatusChecks
  extend ActiveSupport::Concern

  def pending?
    status == "pending"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def skipped?
    status == "skipped"
  end

  def waiting_for_approval?
    status == "waiting_approval"
  end

  def active?
    %w[pending running waiting_approval].include?(status)
  end

  def finished?
    %w[completed failed cancelled skipped].include?(status)
  end

  def successful?
    %w[completed skipped].include?(status)
  end
end

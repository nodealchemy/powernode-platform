# frozen_string_literal: true

class AiBudgetReconciliationJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[BudgetReconciliation] Starting budget reconciliation")

    response = with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/autonomy/budgets/reconcile")
    end

    unless response['success']
      log_error("[BudgetReconciliation] Reconciliation endpoint returned error", error: response['error'])
      return
    end

    data = response['data'] || {}
    discrepancies = data['discrepancies'] || []

    if discrepancies.any?
      log_warn("[BudgetReconciliation] Found #{discrepancies.size} discrepancies", discrepancies: discrepancies)
    else
      log_info("[BudgetReconciliation] No discrepancies found (checked #{data['checked']} budgets)")
    end

    log_info("[BudgetReconciliation] Budget reconciliation completed")
  end
end

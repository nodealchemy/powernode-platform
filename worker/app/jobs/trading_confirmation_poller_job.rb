# frozen_string_literal: true

class TradingConfirmationPollerJob < BaseJob
  sidekiq_options queue: "trading", retry: 1

  def execute
    log_info("Polling for pending transfer confirmations")

    response = api_client.get("/api/v1/internal/trading/pending_transfers")
    transactions = response.dig("data", "transactions") || []

    return log_info("No pending transfers") if transactions.empty?

    log_info("Found #{transactions.size} pending transfers to check")

    # Group by chain to minimize RPC connections
    by_chain = transactions.group_by { |t| t["chain_config"]["rpc_url"] }

    by_chain.each do |_rpc_url, chain_txs|
      chain_config = chain_txs.first["chain_config"]
      signer = Trading::ChainSigner.new(chain_config)
      target_confirmations = chain_config["confirmation_blocks"] || 12

      chain_txs.each do |tx_data|
        check_transaction(tx_data, signer, target_confirmations)
      rescue StandardError => e
        log_warn("Failed to check transaction #{tx_data['id']}", error: e.message)
      end
    end
  end

  private

  def check_transaction(tx_data, signer, target_confirmations)
    tx_hash = tx_data["tx_hash"]
    transaction_id = tx_data["id"]

    return unless tx_hash.present?

    receipt = signer.get_receipt(tx_hash)
    return unless receipt # Not yet mined

    current_block = signer.block_number
    tx_block = receipt["blockNumber"].to_i(16)
    confirmations = current_block - tx_block
    gas_used = receipt["gasUsed"].to_i(16)
    gas_price = (receipt["effectiveGasPrice"] || "0x0").to_i(16)

    if receipt["status"] != "0x1"
      # Transaction reverted
      api_client.post("/api/v1/internal/trading/fail_transfer", {
        transaction_id: transaction_id,
        error_message: "Transaction reverted on-chain"
      })
      log_info("Transfer reverted", transaction_id: transaction_id, tx_hash: tx_hash)
      return
    end

    if confirmations >= target_confirmations
      api_client.post("/api/v1/internal/trading/confirm_transfer", {
        transaction_id: transaction_id,
        tx_hash: tx_hash,
        block_number: tx_block,
        gas_used: gas_used,
        gas_price: gas_price,
        confirmations: confirmations
      })
      log_info("Transfer confirmed by poller", transaction_id: transaction_id, confirmations: confirmations)
    else
      log_info("Transfer pending",
        transaction_id: transaction_id,
        confirmations: "#{confirmations}/#{target_confirmations}"
      )
    end
  end
end

# frozen_string_literal: true

class TradingOnChainTransferJob < BaseJob
  sidekiq_options queue: "trading", retry: 2

  CONFIRMATION_TIMEOUT = 300 # 5 minutes
  POLL_INTERVAL = 3 # seconds

  def execute(transaction_id)
    log_info("Starting on-chain transfer", transaction_id: transaction_id)

    # Fetch transaction context from server
    context = fetch_transfer_context(transaction_id)
    return fail_transfer(transaction_id, "Transfer context not found") unless context

    chain_config = context["chain_config"]
    token_meta = context["token_metadata"]
    from_address = context["from_address"]
    to_address = context["to_address"]
    amount = BigDecimal(context["amount"].to_s)
    is_erc20 = token_meta["is_erc20"]
    token_contract = token_meta["contract_address"]
    decimals = token_meta["decimals"] || 18

    # Fetch private key from server (audit-logged)
    private_key = fetch_private_key(context["wallet_id"])
    return fail_transfer(transaction_id, "Failed to fetch private key") unless private_key

    begin
      signer = Trading::ChainSigner.new(chain_config)

      # Get nonce and gas
      nonce = signer.get_nonce(from_address)
      gas_price_wei = signer.gas_price

      # Build and submit transaction
      tx_hash = if is_erc20
        raw_amount = (amount * (10**decimals)).to_i
        gas_limit = signer.estimate_gas({
          from: from_address,
          to: token_contract,
          data: "0xa9059cbb#{to_address.delete_prefix('0x').downcase.rjust(64, '0')}#{raw_amount.to_s(16).rjust(64, '0')}"
        })
        # Add 20% gas buffer
        gas_limit = (gas_limit * 1.2).to_i

        signer.send_erc20_transfer(
          token_contract: token_contract,
          to: to_address,
          amount_raw: raw_amount,
          private_key: private_key,
          nonce: nonce,
          gas_limit: gas_limit,
          gas_price: gas_price_wei
        )
      else
        amount_wei = (amount * 1e18).to_i
        gas_limit = signer.estimate_gas({
          from: from_address,
          to: to_address,
          value: "0x#{amount_wei.to_s(16)}"
        })
        gas_limit = (gas_limit * 1.2).to_i

        signer.send_native_transfer(
          to: to_address,
          amount_wei: amount_wei,
          private_key: private_key,
          nonce: nonce,
          gas_limit: gas_limit,
          gas_price: gas_price_wei
        )
      end

      log_info("Transaction submitted", transaction_id: transaction_id, tx_hash: tx_hash)

      # Report submission to server
      report_submitted(transaction_id, tx_hash: tx_hash, nonce: nonce)

      # Poll for confirmation
      poll_for_confirmation(transaction_id, tx_hash, signer, chain_config)
    ensure
      # Clear private key from memory
      private_key = nil
    end
  end

  private

  def fetch_transfer_context(transaction_id)
    response = api_client.post("/api/v1/internal/trading/transfer_context", {
      transaction_id: transaction_id
    })
    response["data"]
  rescue StandardError => e
    log_error("Failed to fetch transfer context", e, transaction_id: transaction_id)
    nil
  end

  def fetch_private_key(wallet_id)
    response = api_client.post("/api/v1/internal/trading/fetch_wallet_key", {
      wallet_id: wallet_id
    })
    response.dig("data", "private_key")
  rescue StandardError => e
    log_error("Failed to fetch private key", e, wallet_id: wallet_id)
    nil
  end

  def report_submitted(transaction_id, tx_hash:, nonce:)
    api_client.post("/api/v1/internal/trading/transfer_submitted", {
      transaction_id: transaction_id,
      tx_hash: tx_hash,
      nonce: nonce
    })
  rescue StandardError => e
    log_warn("Failed to report submission", transaction_id: transaction_id, error: e.message)
  end

  def poll_for_confirmation(transaction_id, tx_hash, signer, chain_config)
    target_confirmations = chain_config["confirmation_blocks"] || 12
    poll_interval = chain_config["block_time_seconds"]&.to_i || POLL_INTERVAL
    started_at = Time.now

    loop do
      if Time.now - started_at > CONFIRMATION_TIMEOUT
        log_warn("Confirmation timeout", transaction_id: transaction_id, tx_hash: tx_hash)
        # Don't fail — the poller job will pick it up
        return
      end

      receipt = signer.get_receipt(tx_hash)

      if receipt
        current_block = signer.block_number
        tx_block = receipt["blockNumber"].to_i(16)
        confirmations = current_block - tx_block
        gas_used = receipt["gasUsed"].to_i(16)
        gas_price = (receipt["effectiveGasPrice"] || "0x0").to_i(16)

        if receipt["status"] == "0x1" && confirmations >= target_confirmations
          confirm_transfer(transaction_id,
            tx_hash: tx_hash,
            block_number: tx_block,
            gas_used: gas_used,
            gas_price: gas_price,
            confirmations: confirmations
          )
          log_info("Transfer confirmed", transaction_id: transaction_id, confirmations: confirmations)
          return
        elsif receipt["status"] != "0x1"
          fail_transfer(transaction_id, "Transaction reverted on-chain")
          return
        end
      end

      sleep(poll_interval)
    end
  end

  def confirm_transfer(transaction_id, tx_hash:, block_number:, gas_used:, gas_price:, confirmations:)
    api_client.post("/api/v1/internal/trading/confirm_transfer", {
      transaction_id: transaction_id,
      tx_hash: tx_hash,
      block_number: block_number,
      gas_used: gas_used,
      gas_price: gas_price,
      confirmations: confirmations
    })
  rescue StandardError => e
    log_error("Failed to confirm transfer", e, transaction_id: transaction_id)
  end

  def fail_transfer(transaction_id, error_message)
    log_error_msg("Transfer failed: #{error_message}", transaction_id: transaction_id)
    api_client.post("/api/v1/internal/trading/fail_transfer", {
      transaction_id: transaction_id,
      error_message: error_message
    })
  rescue StandardError => e
    log_error("Failed to report transfer failure", e, transaction_id: transaction_id)
  end

  def log_error_msg(msg, **context)
    logger.error("[TradingOnChainTransfer] #{msg} #{context}")
  end
end

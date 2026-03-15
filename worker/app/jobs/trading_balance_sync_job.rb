# frozen_string_literal: true

class TradingBalanceSyncJob < BaseJob
  sidekiq_options queue: "trading", retry: 1

  def execute(wallet_id = nil)
    if wallet_id
      sync_single_wallet(wallet_id)
    else
      sync_all_real_wallets
    end
  end

  private

  def sync_all_real_wallets
    log_info("Starting balance sync for all real wallets")

    response = api_client.get("/api/v1/internal/trading/real_wallets_for_sync")
    wallets = response.dig("data", "wallets") || []

    log_info("Found #{wallets.size} real wallets to sync")

    wallets.each do |wallet_data|
      sync_wallet_balances(wallet_data)
    rescue StandardError => e
      log_warn("Failed to sync wallet #{wallet_data['id']}", error: e.message)
    end
  end

  def sync_single_wallet(wallet_id)
    log_info("Syncing wallet", wallet_id: wallet_id)

    response = api_client.get("/api/v1/internal/trading/wallet_sync_context", {
      wallet_id: wallet_id
    })
    wallet_data = response["data"]
    return log_warn("Wallet not found", wallet_id: wallet_id) unless wallet_data

    sync_wallet_balances(wallet_data)
  end

  def sync_wallet_balances(wallet_data)
    chain_config = wallet_data["chain_config"]
    address = wallet_data["address"]
    tokens = wallet_data["tokens"] || []

    signer = Trading::ChainSigner.new(chain_config)
    balances = {}

    tokens.each do |token|
      balance = if token["contract_address"].present?
        raw = signer_balance_of(signer, chain_config, address, token["contract_address"])
        raw.to_f / (10**token["decimals"].to_i)
      else
        raw = signer_native_balance(signer, chain_config, address)
        raw.to_f / 1e18
      end

      balances[token["id"]] = balance
    end

    # Report balances to server
    api_client.post("/api/v1/internal/trading/sync_wallet_balances", {
      wallet_id: wallet_data["id"],
      balances: balances
    })

    log_info("Synced #{balances.size} token balances for wallet #{wallet_data['id']}")
  end

  def signer_balance_of(signer, _chain_config, address, contract_address)
    padded = address.delete_prefix("0x").downcase.rjust(64, "0")
    data = "0x70a08231#{padded}"

    result = signer.send(:rpc_call, "eth_call", [{ to: contract_address, data: data }, "latest"])
    result.to_i(16)
  end

  def signer_native_balance(signer, _chain_config, address)
    result = signer.send(:rpc_call, "eth_getBalance", [address, "latest"])
    result.to_i(16)
  end
end

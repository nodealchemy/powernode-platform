# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    class WhaleAlertClient < Base
      # Etherscan-compatible API endpoints per chain
      CHAIN_APIS = {
        "ethereum" => "https://api.etherscan.io/api",
        "polygon"  => "https://api.polygonscan.com/api",
        "base"     => "https://api.basescan.org/api"
      }.freeze

      CRYPTO_KEYWORDS = %w[
        btc eth bitcoin ethereum polygon matic usdc usdt
        crypto token wallet defi swap whale trader
        polymarket prediction bet wager
      ].freeze

      # Well-known stablecoin contracts (for filtering ERC-20 transfers)
      USDC_CONTRACTS = {
        "polygon"  => "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
        "ethereum" => "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "base"     => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
      }.freeze

      def applicable?(question)
        q = question.to_s.downcase
        CRYPTO_KEYWORDS.any? { |kw| q.include?(kw) }
      end

      def cache_ttl
        300 # 5 minutes
      end

      def fetch_for_market(market_question, metadata = {})
        chain = metadata[:chain] || metadata["chain"] || "polygon"
        api_key = resolve_api_key(metadata)
        return nil unless api_key

        watched = metadata[:watched_wallets] || metadata["watched_wallets"] || []
        return nil if watched.empty?

        min_usd = (metadata[:min_whale_tx_usd] || metadata["min_whale_tx_usd"] || 100_000).to_f

        cache_key = "whale:#{chain}:#{watched.sort.join(',')[0, 100]}"
        cached_fetch(cache_key) do
          fetch_whale_transfers(chain, api_key, watched, min_usd)
        end
      end

      private

      def resolve_api_key(metadata)
        metadata[:etherscan_api_key] || metadata["etherscan_api_key"] || ENV["ETHERSCAN_API_KEY"]
      end

      def fetch_whale_transfers(chain, api_key, wallets, min_usd)
        base_url = CHAIN_APIS[chain]
        return nil unless base_url

        usdc_contract = USDC_CONTRACTS[chain]
        activities = []

        wallets.each do |wallet|
          transfers = fetch_token_transfers(base_url, api_key, wallet, usdc_contract)
          next unless transfers.is_a?(Array)

          transfers.each do |tx|
            value_raw = tx["value"].to_f
            decimals = tx["tokenDecimal"].to_i
            decimals = 6 if decimals.zero? # USDC default
            value_usd = value_raw / (10**decimals)

            next if value_usd < min_usd

            # Determine direction relative to the watched wallet
            direction = if tx["from"]&.downcase == wallet.downcase
                          "sell"
                        else
                          "buy"
                        end

            activities << {
              wallet: wallet,
              tx_hash: tx["hash"],
              from: tx["from"],
              to: tx["to"],
              token: tx["tokenSymbol"] || "USDC",
              amount_usd: value_usd,
              direction: direction,
              timestamp: Time.at(tx["timeStamp"].to_i).utc.iso8601,
              block: tx["blockNumber"]
            }
          end
        rescue StandardError => e
          log("Whale transfer fetch failed for #{wallet[0, 10]}...: #{e.message}", level: :warn)
        end

        return nil if activities.empty?

        # Sort by most recent first
        activities.sort_by! { |a| a[:timestamp] }.reverse!

        {
          activities: activities,
          source: "etherscan",
          chain: chain,
          fetched_at: Time.now.utc.iso8601,
          wallet_count: wallets.size,
          activity_count: activities.size
        }
      end

      def fetch_token_transfers(base_url, api_key, wallet, contract_address)
        params = {
          module: "account",
          action: "tokentx",
          address: wallet,
          sort: "desc",
          page: 1,
          offset: 50,
          apikey: api_key
        }
        params[:contractaddress] = contract_address if contract_address

        uri = URI(base_url)
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        response = http.request(request)

        if response.code.to_i == 200
          parsed = JSON.parse(response.body)
          if parsed["status"] == "1" && parsed["result"].is_a?(Array)
            parsed["result"]
          else
            log("Etherscan API returned status #{parsed['status']}: #{parsed['message']}", level: :warn)
            nil
          end
        else
          log("Etherscan API HTTP error: #{response.code}", level: :warn)
          nil
        end
      rescue => e
        log("Etherscan API request failed: #{e.message}", level: :error)
        nil
      end
    end
  end
end

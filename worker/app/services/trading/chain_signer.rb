# frozen_string_literal: true

require "net/http"
require "json"

module Trading
  class ChainSigner
    ERC20_TRANSFER_SELECTOR = "a9059cbb"

    attr_reader :chain_config

    def initialize(chain_config)
      @chain_config = chain_config
    end

    # Sign and submit a native token transfer
    def send_native_transfer(to:, amount_wei:, private_key:, nonce:, gas_limit:, gas_price:)
      tx_params = {
        nonce: nonce,
        gas_price: gas_price,
        gas_limit: gas_limit,
        to: to,
        value: amount_wei,
        data: "",
        chain_id: chain_config["chain_id"]
      }

      sign_and_submit(tx_params, private_key)
    end

    # Sign and submit an ERC-20 transfer
    def send_erc20_transfer(token_contract:, to:, amount_raw:, private_key:, nonce:, gas_limit:, gas_price:)
      padded_to = to.delete_prefix("0x").downcase.rjust(64, "0")
      padded_amount = amount_raw.to_i.to_s(16).rjust(64, "0")
      data = "0x#{ERC20_TRANSFER_SELECTOR}#{padded_to}#{padded_amount}"

      tx_params = {
        nonce: nonce,
        gas_price: gas_price,
        gas_limit: gas_limit,
        to: token_contract,
        value: 0,
        data: data,
        chain_id: chain_config["chain_id"]
      }

      sign_and_submit(tx_params, private_key)
    end

    # Query current nonce for an address
    def get_nonce(address)
      hex = rpc_call("eth_getTransactionCount", [address, "pending"])
      hex.to_i(16)
    end

    # Query current gas price
    def gas_price
      hex = rpc_call("eth_gasPrice", [])
      hex.to_i(16)
    end

    # Estimate gas for a transaction
    def estimate_gas(params)
      hex = rpc_call("eth_estimateGas", [params])
      hex.to_i(16)
    end

    # Get transaction receipt
    def get_receipt(tx_hash)
      rpc_call("eth_getTransactionReceipt", [tx_hash])
    end

    # Get current block number
    def block_number
      hex = rpc_call("eth_blockNumber", [])
      hex.to_i(16)
    end

    private

    def sign_and_submit(tx_params, private_key)
      key = Eth::Key.new(priv: private_key.delete_prefix("0x"))
      tx = Eth::Tx.new(tx_params)
      tx.sign(key)

      tx_hash = rpc_call("eth_sendRawTransaction", ["0x#{tx.hex}"])

      # Clear private key reference
      private_key = nil # rubocop:disable Lint/UselessAssignment

      tx_hash
    end

    def rpc_call(method, params = [])
      uri = URI(chain_config["rpc_url"])
      payload = { jsonrpc: "2.0", method: method, params: params, id: 1 }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri.path.presence || "/")
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = http.request(request)
      body = JSON.parse(response.body)

      if body["error"]
        err = body["error"]
        raise "RPC error: #{err['message'] || 'unknown'} (code: #{err['code'] || 'unknown'})"
      end

      body["result"]
    end
  end
end

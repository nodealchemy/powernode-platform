# frozen_string_literal: true

# Monkey-patches WebSocket::Client::Simple to honor a caller-supplied
# OpenSSL::SSL::SSLContext via `options[:ssl_context]`. Without this the
# library always builds its own context (no client-cert hooks), so mTLS
# client-cert presentation is impossible.
#
# Used by ActionCableClient to wire WorkerCertManager certs into the
# /cable WebSocket — same mTLS material the worker presents on its
# Faraday HTTP calls to the platform.
#
# The patch only diverges from upstream when `:ssl_context` is supplied;
# all other call sites get the library's original behavior unchanged.

require "websocket-client-simple"

module WebsocketClientSimpleMtls
  def connect(url, options = {})
    return super(url, options) unless options[:ssl_context]
    return if @socket

    @url = url
    uri = URI.parse(url)
    @socket = TCPSocket.new(uri.host, uri.port || (uri.scheme == "wss" ? 443 : 80))

    if %w[https wss].include?(uri.scheme)
      @socket = ::OpenSSL::SSL::SSLSocket.new(@socket, options[:ssl_context])
      @socket.sync_close = true
      @socket.hostname = uri.host
      @socket.connect
    end

    ::WebSocket.should_raise = true
    @handshake = ::WebSocket::Handshake::Client.new(url: url, headers: options[:headers])
    @handshaked = false
    @pipe_broken = false
    frame = ::WebSocket::Frame::Incoming::Client.new
    @closed = false

    once :__close do |err|
      close
      emit :close, err
    end

    @thread = Thread.new do
      while !@closed
        begin
          unless recv_data = @socket.getc
            sleep 1
            next
          end
          unless @handshaked
            @handshake << recv_data
            if @handshake.finished?
              @handshaked = true
              emit :open
            end
          else
            frame << recv_data
            while msg = frame.next
              emit :message, msg
            end
          end
        rescue => e
          emit :error, e
        end
      end
    end
  end
end

WebSocket::Client::Simple::Client.prepend(WebsocketClientSimpleMtls)

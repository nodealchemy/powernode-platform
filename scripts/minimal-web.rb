#!/usr/bin/env ruby

# Minimal web server test to isolate timeout issue
require 'webrick'

server = WEBrick::HTTPServer.new(
  :Port => ENV.fetch('SIDEKIQ_WEB_PORT', 4567).to_i,
  :BindAddress => ENV.fetch('SIDEKIQ_WEB_HOST', '0.0.0.0'),
  :Logger => WEBrick::Log.new(STDOUT, WEBrick::Log::ERROR),
  :AccessLog => []
)

server.mount_proc '/' do |req, res|
  res.body = '{"service": "Powernode Worker Test", "status": "running"}'
  res['Content-Type'] = 'application/json'
end

# Detach from terminal
Process.daemon(true, false)

trap 'INT' do server.shutdown end
server.start
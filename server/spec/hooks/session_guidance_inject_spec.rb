# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "securerandom"
require "socket"
require "tmpdir"
require "fileutils"

# IMP-fecf675bfc9f — the SessionStart digest advertises only the platform verbs
# the session's connector actually lists.
#
# The digest told every session to "ask platform.route_task when unsure". That
# line was static prose, while the dev-cell's instance grant did not carry
# route_task at the time. A session read advice it had no way to follow.
#
# OPERATOR DIRECTION: advertise only verbs the connector's tools/list returns,
# and list the missing ones as a grant gap instead of as advice.
#
# Shell-level fixture spec, no Rails: a throwaway HTTP listener stands in for
# the local MCP endpoint and answers tools/list with a chosen set of names.
RSpec.describe ".claude/hooks/session-guidance-inject.sh" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:hook) { File.join(repo_root, ".claude", "hooks", "session-guidance-inject.sh") }

  let(:project_dir) { Dir.mktmpdir("guidance-project") }
  let(:home_dir) { Dir.mktmpdir("guidance-home") }

  let(:all_verbs) { %w[platform.route_task platform.search_knowledge platform.create_knowledge] }

  before do
    conv = File.join(project_dir, "docs", "contributing", "conventions")
    FileUtils.mkdir_p(conv)
    File.write(File.join(conv, "testing-patterns.md"), "# Testing Patterns\n")
    agents = File.join(project_dir, ".claude", "agents", "powernode")
    FileUtils.mkdir_p(agents)
    File.write(File.join(agents, "capacity-manager.md"), "---\nname: capacity-manager\n---\n")
  end

  after do
    [ project_dir, home_dir ].each { |d| FileUtils.remove_entry(d) if File.exist?(d) }
    @servers&.each(&:close)
  end

  # Answers every request with a tools/list result naming `names`. `sse: true`
  # frames it the way a streamable-HTTP endpoint may.
  def start_listener(names, sse: false, description: "d", next_cursor: nil, hang: false, sse_trailer: false)
    server = TCPServer.new("127.0.0.1", 0)
    (@servers ||= []) << server
    requests = []
    result = { tools: names.map { |n| { name: n, description: description } } }
    result[:nextCursor] = next_cursor if next_cursor
    json = { jsonrpc: "2.0", id: 1, result: result }.to_json
    body = sse ? "event: message\ndata: #{json}\n\n" : json
    if sse_trailer
      body += "event: message\ndata: #{{ jsonrpc: '2.0', method: 'notifications/message', params: {} }.to_json}\n\n"
    end
    type = sse ? "text/event-stream" : "application/json"
    Thread.new do
      loop do
        client = server.accept
        client.gets
        headers = {}
        while (line = client.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.strip.downcase] = value.strip
        end
        requests << { headers: headers, body: client.read(headers["content-length"].to_i) }
        if hang
          sleep 10
          next
        end
        client.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
                     "Connection: close\r\n\r\n#{body}")
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
    [ "http://127.0.0.1:#{server.addr[1]}/mcp", requests ]
  end

  def closed_port_url
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    "http://127.0.0.1:#{port}/mcp"
  end

  def run_hook(url: nil)
    # nil UNSETS the variable, so a value exported by whoever runs the suite
    # cannot point the hook at a real endpoint.
    env = { "CLAUDE_PROJECT_DIR" => project_dir, "HOME" => home_dir, "POWERNODE_MCP_URL" => url }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, err, status = Open3.capture3(env, "bash", hook, stdin_data: "{}")
    [ out, err, status, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started ]
  end

  it "stays wired to SessionStart within a 5 s budget" do
    settings = JSON.parse(File.read(File.join(repo_root, ".claude", "settings.json")))
    entry = settings.dig("hooks", "SessionStart").to_a.flat_map { |g| g["hooks"].to_a }
                    .find { |h| h["command"].include?("session-guidance-inject.sh") }
    expect(entry).to be_truthy
    expect(entry["timeout"]).to be <= 5
  end

  it "asks the connector's tools/list, once" do
    url, requests = start_listener(all_verbs)
    run_hook(url: url)
    expect(requests.size).to eq(1)
    expect(JSON.parse(requests.first[:body])).to include("jsonrpc" => "2.0", "method" => "tools/list")
  end

  it "advertises every verb the connector lists, with no grant gap" do
    url, = start_listener(all_verbs + %w[platform.list_agents])
    out, _err, status, = run_hook(url: url)

    expect(status.exitstatus).to eq(0)
    expect(out).to include("ask platform.route_task when unsure")
    expect(out).to include("platform.search_knowledge tag:guidance-")
    expect(out).to include("(tag guidance-testing-patterns)")
    expect(out).to include("Author them via platform.create_knowledge")
    expect(out).not_to match(/grant gap/i)
  end

  it "looks up search_knowledge itself: a listing without it withholds its advice and its tag pointers" do
    url, = start_listener(%w[platform.route_task platform.create_knowledge])
    out, = run_hook(url: url)

    expect(out).not_to include("platform.search_knowledge tag:")
    expect(out).not_to include("(tag guidance-")
    expect(out).to include("ask platform.route_task when unsure", "Author them via platform.create_knowledge")
    expect(out.lines.find { |l| l =~ /grant gap/i }).to include("platform.search_knowledge")
  end

  it "matches names exactly, so a near-miss name is still a gap" do
    url, = start_listener(%w[platform.route_task_v2 xplatform.search_knowledge platform.create_knowledge])
    out, = run_hook(url: url)

    expect(out).not_to include("ask platform.route_task", "platform.search_knowledge tag:")
    expect(out.lines.find { |l| l =~ /grant gap/i }).to include("platform.route_task", "platform.search_knowledge")
  end

  it "reads an empty tool list as a full grant gap, not as an unreadable answer" do
    url, = start_listener([])
    out, = run_hook(url: url)

    expect(out).not_to match(/could not read/i)
    expect(out.lines.find { |l| l =~ /grant gap/i }).to include(*all_verbs)
  end

  it "treats a paginated tool list as unread rather than reporting false gaps" do
    url, = start_listener(%w[platform.search_knowledge], next_cursor: "page-2")
    out, = run_hook(url: url)

    expect(out).not_to match(/grant gap/i)
    expect(out).not_to include("platform.search_knowledge tag:")
    expect(out).to match(/could not read .*paginated/i)
  end

  it "picks the tools/list reply out of an SSE stream that also carries a notification" do
    url, = start_listener(all_verbs, sse: true, sse_trailer: true)
    out, = run_hook(url: url)
    expect(out).to include("ask platform.route_task when unsure")
    expect(out).not_to match(/could not read|grant gap/i)
  end

  it "gives up on an endpoint that accepts and never answers, inside the budget" do
    url, = start_listener(all_verbs, hang: true)
    out, _err, status, elapsed = run_hook(url: url)

    expect(status.exitstatus).to eq(0)
    expect(elapsed).to be < 5
    expect(out).not_to include("ask platform.route_task")
    expect(out).to match(/could not read .*no response/i)
  end

  it "withholds advice naming a verb the connector does not list, and names it as a grant gap" do
    url, = start_listener(%w[platform.search_knowledge])
    out, _err, status, = run_hook(url: url)

    expect(status.exitstatus).to eq(0)
    expect(out).not_to include("ask platform.route_task")
    expect(out).not_to include("Author them via platform.create_knowledge")
    expect(out).to include("platform.search_knowledge tag:guidance-")
    gap = out.lines.find { |l| l =~ /grant gap/i }
    expect(gap).to be_truthy, out
    expect(gap).to include("platform.route_task", "platform.create_knowledge")
    expect(gap).not_to include("platform.search_knowledge")
  end

  it "reads an SSE-framed tools/list the same way" do
    url, = start_listener(all_verbs, sse: true)
    out, = run_hook(url: url)
    expect(out).to include("ask platform.route_task when unsure")
    expect(out).not_to match(/grant gap/i)
  end

  # Found running the hook against the real connector: a description containing
  # "data:" made a plain JSON body read as SSE, and every verb was withheld.
  it "reads a plain JSON tools/list whose descriptions contain 'data:'" do
    url, = start_listener(all_verbs, description: "Returns data: rows and a cursor")
    out, = run_hook(url: url)
    expect(out).to include("ask platform.route_task when unsure")
    expect(out).not_to match(/could not read/i)
  end

  it "advertises no platform verb when the connector cannot be read, says so, and still exits 0 in budget" do
    out, _err, status, elapsed = run_hook(url: closed_port_url)

    expect(status.exitstatus).to eq(0)
    expect(elapsed).to be < 5
    expect(out).to include("=== POWERNODE GUIDANCE", "Testing Patterns")
    expect(out).not_to include("ask platform.route_task")
    expect(out).not_to include("platform.search_knowledge tag:")
    expect(out).not_to include("Author them via platform.create_knowledge")
    expect(out).to match(/could not read .*tools\/list/i)
  end

  it "uses the connector entry in ~/.claude.json, sending its Authorization header without printing it" do
    url, requests = start_listener(all_verbs)
    token = "Bearer spec-token-#{SecureRandom.hex(8)}"
    File.write(File.join(home_dir, ".claude.json"),
               { mcpServers: { powernode: { url: url, headers: { Authorization: token } } } }.to_json)

    out, err, = run_hook
    expect(requests.first[:headers]["authorization"]).to eq(token)
    expect(out + err).not_to include(token.split.last)
    expect(out).to include("ask platform.route_task when unsure")
  end
end

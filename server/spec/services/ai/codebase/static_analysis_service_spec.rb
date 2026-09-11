# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# D1 review H1 and M3: the analyzer's subprocess. It used to run a shell string
# that inherited the Rails process's environment, so `bundle exec rubocop`
# resolved against the SERVER's bundle even inside another checkout (and a
# production bundle has no rubocop), and its TIMEOUT was defined and never used.
RSpec.describe Ai::Codebase::StaticAnalysisService do
  let(:dir) { Dir.mktmpdir("static-analysis") }
  let(:service) { described_class.new(base_path: dir) }

  after { FileUtils.remove_entry(dir) if Dir.exist?(dir) }

  def run(argv, **opts) = service.send(:execute_command, argv, chdir: dir, **opts)

  describe "the subprocess" do
    it "runs with a clean environment: the Rails process's bundler variables do not reach it" do
      # Non-vacuity: under `bundle exec rspec` the parent really has these to leak.
      expect(ENV["BUNDLE_GEMFILE"]).to be_present

      result = run(%w[env])

      expect(result[:status]).to eq(:ran)
      vars = result[:output].lines.map { |line| line.split("=", 2).first }
      expect(vars).to include("PATH")
      expect(vars).not_to include("BUNDLE_GEMFILE", "RUBYOPT", "RAILS_ENV")
    end

    it "passes the linter's own variables through, such as the working copy's Gemfile" do
      gemfile = File.join(dir, "Gemfile")

      result = run(%w[env], env: { "BUNDLE_GEMFILE" => gemfile })

      expect(result[:output]).to include("BUNDLE_GEMFILE=#{gemfile}")
    end

    it "runs in the working copy's directory" do
      expect(run(%w[pwd])[:output].strip).to eq(File.realpath(dir))
    end

    it "kills the whole process group at the deadline and says it timed out" do
      allow(described_class).to receive(:timeout_seconds).and_return(1)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = run([ "sh", "-c", "sleep 30 & echo $! > grandchild.pid; wait" ])

      expect(result).to eq(status: :timeout)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
      grandchild = File.read(File.join(dir, "grandchild.pid")).to_i
      gone = 20.times.any? do
        Process.kill(0, grandchild)
        sleep 0.1
        false
      rescue Errno::ESRCH
        true
      end
      expect(gone).to be(true), "the backgrounded child outlived the timeout"
    end

    it "reports a program that is not installed as unavailable, not as empty output" do
      expect(run(%w[definitely-not-a-linter-d1])).to eq(status: :unavailable)
    end
  end

  describe "a linter that did not run is never clean" do
    it "carries a timeout through as the linter's status" do
      File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
      allow(service).to receive(:execute_command).and_return(status: :timeout)

      result = service.analyze(linters: [ "ruby" ])

      expect(result[:summary][:linters]["RuboCop"]).to eq(status: "timeout")
      expect(result[:diagnostics]).to eq([])
    end

    it "does not call a tsc that exited non-zero without printing anything clean" do
      File.write(File.join(dir, "tsconfig.json"), "{}")
      allow(service).to receive(:execute_command).and_return(status: :ran, output: "", exitstatus: 2)

      expect(service.analyze(linters: [ "typescript" ])[:summary][:linters]["TypeScript"]).to eq(status: "no_output")
    end

    it "does call a silent tsc with a zero exit clean" do
      File.write(File.join(dir, "tsconfig.json"), "{}")
      allow(service).to receive(:execute_command).and_return(status: :ran, output: "", exitstatus: 0)

      expect(service.analyze(linters: [ "typescript" ])[:summary][:linters]["TypeScript"])
        .to eq(status: "clean", errors: 0)
    end

    it "detects no linter at all in a directory with nothing to lint" do
      expect(service.analyze[:summary][:linters]).to eq({})
    end
  end

  # D1b: the parser, apart from the runner. Output a leased runner hands back is
  # parsed exactly like output from a local run, with paths relative to the
  # directory the linter ran in.
  describe ".parse_output" do
    let(:base) { "/runner/work/core" }

    def parse(key, output, exitstatus: 0)
      described_class.parse_output(key, output: output, exitstatus: exitstatus, base_path: base)
    end

    it "turns rubocop's JSON into diagnostics with paths relative to where it ran" do
      json = { "files" => [ { "path" => "app/models/thing.rb", "offenses" => [
                 { "severity" => "convention", "message" => "m", "cop_name" => "Style/StringLiterals",
                   "location" => { "start_line" => 3, "start_column" => 5 } }
               ] } ],
               "summary" => { "inspected_file_count" => 1, "offense_count" => 1 } }.to_json

      result = parse(:ruby, json)

      expect(result[:summary]).to include(status: "completed", offenses: 1)
      expect(result[:diagnostics]).to contain_exactly(
        hash_including(file: "app/models/thing.rb", line: 3, severity: "info", rule: "Style/StringLiterals")
      )
    end

    it "makes an absolute eslint path relative to where it ran" do
      json = [ { "filePath" => "#{base}/src/a.js",
                 "messages" => [ { "line" => 1, "column" => 1, "severity" => 1, "message" => "m", "ruleId" => "semi" } ] } ].to_json

      expect(parse(:javascript_lint, json)[:diagnostics].first).to include(file: "src/a.js", severity: "warning")
    end

    it "reads output that is not the linter's JSON as a parse error, never as clean" do
      expect(parse(:ruby, "Could not find gem 'rubocop'")[:summary][:status]).to eq("parse_error")
      expect(parse(:ruby, "[1, 2]")[:summary][:status]).to eq("parse_error")
      expect(parse(:javascript_lint, "{}")[:summary][:status]).to eq("parse_error")
    end

    it "calls a silent tsc clean only on a zero exit, and not when no exit status arrived" do
      expect(parse(:typescript, "", exitstatus: 0)[:summary][:status]).to eq("clean")
      expect(parse(:typescript, "", exitstatus: 2)[:summary][:status]).to eq("no_output")
      expect(parse(:typescript, "", exitstatus: nil)[:summary][:status]).to eq("no_output")
    end

    it "parses tsc's error lines" do
      output = "src/a.ts(4,7): error TS2322: Type 'x' is not assignable.\n"

      expect(parse(:typescript, output, exitstatus: 2)[:diagnostics]).to contain_exactly(
        hash_including(file: "src/a.ts", line: 4, rule: "TS2322", severity: "error")
      )
    end

    it "names an unknown linter rather than guessing" do
      expect(parse(:cobol, "anything")[:summary][:status]).to eq("unknown_linter")
    end
  end
end

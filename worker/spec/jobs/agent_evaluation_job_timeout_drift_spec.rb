# frozen_string_literal: true

require "rails_helper"

# Drift guard (review2 ruling on fcab8a06c). AgentEvaluationJob::JUDGE_TIMEOUT
# must outlast the server's own bound on the judge's model call,
# WorkerLlmClient::LLM_TIMEOUT: a worker that gives up first leaves a paid call
# whose answer is lost. The two constants live in separately deployed apps and
# the worker cannot load server code, so both are read here as SOURCE TEXT.
# A constant that cannot be found, or is not one integer literal, fails loudly
# rather than passing on a comparison it never made.
RSpec.describe "AgentEvaluationJob::JUDGE_TIMEOUT drift guard" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }

  def integer_constant(relative_path, name)
    path = File.join(repo_root, relative_path)
    expect(File.file?(path)).to be(true), "drift guard: #{relative_path} not found under #{repo_root}"

    values = File.read(path).scan(/^\s*#{name}\s*=\s*([\d_]+)(?![\w.])/).flatten
    expect(values.size).to eq(1),
                           "drift guard: expected one integer literal #{name} = N in #{relative_path}, found #{values.size}"
    Integer(values.first.delete("_"))
  end

  it "keeps the worker's judge timeout above the server's model-call timeout" do
    judge = integer_constant("worker/app/jobs/agent_evaluation_job.rb", "JUDGE_TIMEOUT")
    server = integer_constant("server/app/services/worker_llm_client.rb", "LLM_TIMEOUT")

    expect(judge).to be > server,
                     "JUDGE_TIMEOUT (#{judge}s) must exceed the server's WorkerLlmClient::LLM_TIMEOUT (#{server}s)"
  end
end

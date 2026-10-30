require "spec_helper"
require "yaml"
require "open3"

RSpec.describe "trusted publishing preparation" do
  let(:workflow) { YAML.load_file(File.expand_path("../.github/workflows/release.yml", __dir__)) }

  it "requires manual dispatch, gates publication, and isolates tag-write from OIDC" do
    events = workflow["on"] || workflow[true]
    expect(events.keys.sort).to eq(%w[workflow_dispatch])
    expect(workflow.fetch("permissions")).to eq({})
    expect(workflow.dig("concurrency", "cancel-in-progress")).to be(false)
    jobs = workflow.fetch("jobs")
    expect(jobs.dig("prepare", "if")).to include("github.event_name == 'workflow_dispatch'",
                                                 "github.ref == 'refs/heads/master'")
    %w[version commit].each do |input|
      expect(events.dig("workflow_dispatch", "inputs", input, "required")).to be(true)
    end
    expect(workflow.to_yaml).not_to include("FIVE_PM_RELEASE_APPROVED")
    expect(jobs.dig("verify", "strategy", "matrix", "ruby")).to eq(%w[3.2 3.3 3.4 4.0])
    expect(jobs.dig("tag", "environment")).to eq("release")
    expect(jobs.dig("tag", "permissions")).to eq("contents" => "write")
    %w[publish-core publish-mcp].each do |job|
      expect(jobs.dig(job, "environment")).to eq("release")
      expect(jobs.dig(job, "permissions")).to eq("contents" => "read", "id-token" => "write")
    end
    expect(jobs.dig("publish-mcp", "needs")).to include("publish-core")
    expect(jobs.dig("publish-mcp", "steps").last.dig("with", "working-directory")).to eq("mcp")
    expect(workflow.to_yaml).not_to include("secrets.")
    jobs.each_value do |job|
      job.fetch("steps", []).each do |step|
        expect(step.fetch("uses")).to match(/@[0-9a-f]{40}\z/) if step.key?("uses")
      end
    end
  end

  it "rejects automatic events and dispatch from other refs before any candidate operation" do
    candidate = workflow.dig("jobs", "prepare", "steps").find { |step| step["id"] == "candidate" }.fetch("run")
    # Execute the real shell guards only; candidate reads, Git writes and network
    # operations are outside this test.
    prefix = candidate.split("git fetch").first
    [["workflow_dispatch", "refs/heads/master", true],
     ["push", "refs/tags/v0.1.0", false],
     ["workflow_dispatch", "refs/tags/v0.1.0", false],
     ["workflow_dispatch", "refs/heads/feature", false]].each do |event, ref, accepted|
      environment = { "GITHUB_EVENT_NAME" => event, "GITHUB_REF" => ref,
                      "INPUT_VERSION" => "0.1.0", "INPUT_COMMIT" => "a" * 40 }
      _, errors, status = Open3.capture3(environment, "bash", "-c", prefix)
      expect(status.success?).to eq(accepted), errors
    end
  end

  it "exposes standard build tasks for both gems while disabling Bundler's git-push action" do
    %w[Rakefile mcp/Rakefile].each do |path|
      script = <<~RUBY
        require "rake"
        load ARGV.fetch(0)
        abort "missing build" unless Rake::Task.task_defined?("build")
        abort "git mutation still enabled" unless Rake::Task["release:source_control_push"].actions.empty?
        abort "unguarded push" unless Rake::Task["release:rubygem_push"].prerequisites.include?("release:guard_clean")
      RUBY
      root = File.expand_path("..", __dir__)
      _, errors, status = Open3.capture3(RbConfig.ruby, "-e", script, File.join(root, path),
                                         chdir: File.dirname(File.join(root, path)))
      expect(status).to be_success, errors
    end
  end

  it "refuses publication tasks outside the protected workflow before any publishing action" do
    script = <<~RUBY
      require "rake"
      load "Rakefile"
      Bundler::GemHelper.instance.define_singleton_method(:guard_clean) { true }
      Rake::Task["build"].clear
      Rake::Task["release:rubygem_push"].clear_actions
      Rake::Task["release:rubygem_push"].invoke
    RUBY
    environment = { "GITHUB_ACTIONS" => nil, "GITHUB_EVENT_NAME" => nil, "GITHUB_REF" => nil }
    _, errors, status = Open3.capture3(environment, RbConfig.ruby, "-e", script,
                                       chdir: File.expand_path("..", __dir__))
    expect(status).not_to be_success
    expect(errors).to include("publication requires the protected GitHub release workflow")
  end
end

# frozen_string_literal: true

require "rake/testtask"

require_relative "lib/zotero/mcp/version"

Rake::TestTask.new(:test) do |t|
    t.libs << "test"
    t.test_files = FileList["test/*_test.rb"]
    t.warning = false
end

task default: :test

# The tag is read from Zotero::MCP::VERSION, never typed. Refuses a dirty
# worktree and an existing tag; creates an annotated tag and pushes nothing.
desc "Tag HEAD as v<VERSION> (annotated, MESSAGE=file for the notes)"
task :tag do
    tag = "v#{Zotero::MCP::VERSION}"
    dirty = !`git status --porcelain`.empty?
    abort "rake tag: worktree is not clean" if dirty
    abort "rake tag: #{tag} already exists" unless `git tag -l #{tag}`.empty?

    notes = ENV.fetch("MESSAGE", nil)
    args = notes ? ["-F", notes] : ["-m", "zotero-mcp #{tag}"]
    sh "git", "tag", "-a", tag, *args
end

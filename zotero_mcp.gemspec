# frozen_string_literal: true

require_relative "lib/zotero_mcp/version"

Gem::Specification.new do |spec|
    spec.name = "zotero_mcp"
    spec.version = ZoteroMCP::VERSION
    spec.authors = ["Stephane D'Alu"]
    spec.email = ["stephane.dalu@gmail.com"]

    spec.summary = "MCP server for the Zotero Web API and the local Zotero app"
    spec.description = <<~DESC
        A Model Context Protocol server that lets Claude Code and other MCP
        clients search, read, cite and edit a Zotero library through the
        Zotero Web API v3, or read it from the Zotero desktop app.
    DESC
    spec.homepage = "https://github.com/sdalu/mcp-zotero"
    spec.license = "MIT"
    spec.required_ruby_version = ">= 3.2"

    spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "DESIGN.md",
        "LICENSE"]
    spec.bindir = "exe"
    spec.executables = ["zotero-mcp"]
    spec.require_paths = ["lib"]

    spec.add_dependency "mcp", "~> 0.22"
end

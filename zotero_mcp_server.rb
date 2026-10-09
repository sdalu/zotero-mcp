#!/usr/bin/env ruby
# frozen_string_literal: true

# Checkout launcher, kept so existing MCP registrations that name this path
# keep working; the gem installs exe/zotero-mcp for the same job.
require_relative "lib/zotero/mcp"

Zotero::MCP.run if $PROGRAM_NAME == __FILE__

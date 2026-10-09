# frozen_string_literal: true

# 1. Standard library
require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

# 2. Third-party gems
require "mcp"
require "mcp/server/transports/stdio_transport"

# 3. This library
require_relative "mcp/version"
require_relative "mcp/errors"
require_relative "mcp/config"
require_relative "mcp/helpers"
require_relative "mcp/read_api"
require_relative "mcp/write_api"
require_relative "mcp/response_handling"
require_relative "mcp/client"
require_relative "mcp/formatting"
require_relative "mcp/fulltext"
require_relative "mcp/tools/search_items"
require_relative "mcp/tools/get_item"
require_relative "mcp/tools/list_collections"
require_relative "mcp/tools/get_collection_items"
require_relative "mcp/tools/list_tags"
require_relative "mcp/tools/get_item_fulltext"
require_relative "mcp/tools/generate_bibliography"
require_relative "mcp/tools/get_item_template"
require_relative "mcp/tools/create_item"
require_relative "mcp/tools/create_note"
require_relative "mcp/tools/update_item"
require_relative "mcp/tools/delete_item"
require_relative "mcp/tools/add_to_collection"
require_relative "mcp/tools/create_collection"

# Zotero MCP server: exposes the Zotero Web API v3 (and, read-only, the Zotero
# desktop local API) as MCP tools for Claude Code and other MCP clients.
#
# Configuration comes from the environment:
#   ZOTERO_API_KEY       key from https://www.zotero.org/settings/keys
#   ZOTERO_LIBRARY_ID    numeric user/group id (auto-resolved from the key)
#   ZOTERO_LIBRARY_TYPE  "user" (default) or "group"
#   ZOTERO_LOCAL         "true" to read the local desktop app (read-only)
module Zotero
    module MCP
        TOOLS = [
            SearchItems, GetItem, ListCollections, GetCollectionItems,
            ListTags, GetItemFulltext, GenerateBibliography, GetItemTemplate,
            CreateItem, CreateNote, UpdateItem, DeleteItem, AddToCollection,
            CreateCollection
        ].freeze

        def self.build_server
            ::MCP::Server.new(name: "zotero-mcp", version: VERSION,
                              tools: TOOLS)
        end

        # Serve on stdin/stdout until the client closes the stream.
        def self.run
            ::MCP::Server::Transports::StdioTransport.new(build_server).open
        end
    end
end

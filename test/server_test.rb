# frozen_string_literal: true

require_relative "test_helper"

# The assembled server, driven through the JSON-RPC entry point the stdio
# transport uses: the tool list a client sees, the version it reports, and
# a tool call's isError flag on the wire.
class ServerTest < Minitest::Test
    def setup
        @server = ZoteroMCP.build_server
    end

    def rpc(method, params = {})
        request = { jsonrpc: "2.0", id: 1, method: method, params: params }
        JSON.parse(@server.handle_json(JSON.dump(request)))
    end

    def test_initialize_reports_the_version_constant
        result = rpc("initialize", protocolVersion: "2025-06-18",
            capabilities: {}, clientInfo: { name: "test", version: "0" })
        assert_equal ZoteroMCP::VERSION, result.dig("result", "serverInfo",
            "version")
    end

    def test_tools_list_names_every_tool_with_an_object_schema
        tools = rpc("tools/list").dig("result", "tools")
        names = tools.map { |tool| tool["name"] }
        assert_equal ZoteroMCP::TOOLS.map(&:name_value).sort, names.sort
        assert_equal 14, names.length
        tools.each do |tool|
            assert_equal "object", tool.dig("inputSchema", "type"), tool["name"]
            refute_empty tool["description"].to_s.strip, tool["name"]
        end
    end

    def test_tools_list_carries_the_declared_enums
        tools = rpc("tools/list").dig("result", "tools")
        search = tools.find { |tool| tool["name"] == "zotero_search_items" }
        assert_equal %w[asc desc],
            search.dig("inputSchema", "properties", "direction", "enum")
    end

    def test_tool_call_refusal_is_flagged_as_error_on_the_wire
        result = rpc("tools/call", name: "zotero_delete_item",
            arguments: { item_keys: [] })
        assert_equal true, result.dig("result", "isError")
        text = result.dig("result", "content", 0, "text")
        assert_match(/at least one item key/, JSON.parse(text)["error"])
    end
end

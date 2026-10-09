# frozen_string_literal: true

require_relative "test_helper"

# The read-only MCP tools (other than bibliography and full text, which get
# their own files): search, get, list.
class ReadToolsTest < Minitest::Test
    def test_search_items_returns_formatted_summary
        client = stub_client { |req| search_items_response(req) }
        response = with_client(client) do
            Zotero::MCP::SearchItems.call(query: "dune")
        end
        payload = text_of(response)
        assert_equal 1, payload["pagination"]["total"]
        assert_equal "Dune", payload["items"].first["title"]
    end

    def test_get_item_includes_children_when_requested
        client = stub_client { |req| item_or_children_response(req) }
        response = with_client(client) do
            Zotero::MCP::GetItem.call(item_key: "ITEM0001",
                                      include_children: true)
        end
        payload = text_of(response)
        assert_equal "ITEM0001", payload["item"]["key"]
        assert_equal "CHILD001", payload["children"].first["key"]
    end

    def test_get_item_surfaces_not_found_as_error_text
        client = stub_client { |_req| resp(code: "404") }
        response = with_client(client) do
            Zotero::MCP::GetItem.call(item_key: "MISSING1")
        end
        assert_match(/Not found/, text_of(response)["error"])
    end

    def test_get_item_template_lists_types_without_argument
        client = stub_client do |req|
            assert_equal "/itemTypes", req[:path]
            resp(body: [{ "itemType" => "book", "localized" => "Book" }])
        end
        response = with_client(client) { Zotero::MCP::GetItemTemplate.call }
        assert_equal "book", text_of(response)["itemTypes"].first["itemType"]
    end

    def test_list_collections_shapes_entries
        client = stub_client do |_req|
            resp(body: [collection_result_item],
                 headers: { "Total-Results" => "1" })
        end
        response = with_client(client) { Zotero::MCP::ListCollections.call }
        collection = text_of(response)["collections"].first
        assert_equal "COL1", collection["key"]
        assert_equal "Papers", collection["name"]
        assert_equal 4, collection["numItems"]
    end

    private

    def search_items_response(req)
        assert_equal "/users/42/items/top", req[:path]
        resp(body: [search_result_item], headers: { "Total-Results" => "1" })
    end

    def search_result_item
        { "key" => "K1", "data" => { "itemType" => "book", "title" => "Dune" } }
    end

    def collection_result_item
        { "key" => "COL1", "data" => { "name" => "Papers" },
          "meta" => { "numItems" => 4 } }
    end

    def item_or_children_response(req)
        if req[:path].end_with?("/children")
            resp(body: [{ "key" => "CHILD001" }])
        else
            resp(body: { "key" => "ITEM0001", "data" => {} })
        end
    end
end

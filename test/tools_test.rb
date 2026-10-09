# frozen_string_literal: true

require_relative "test_helper"

# The MCP tool classes: their `.call` methods build the right client calls,
# surface guard errors as text, and short-circuit on invalid arguments. The
# client is stubbed via ZoteroMCP's memoized instance.
class ToolsTest < Minitest::Test
    def test_search_items_returns_formatted_summary
        client = stub_client do |req|
            assert_equal "/users/42/items/top", req[:path]
            resp(body: [{ "key" => "K1", "data" => { "itemType" => "book",
                "title" => "Dune" } }], headers: { "Total-Results" => "1" })
        end
        response = with_client(client) do
            ZoteroMCP::SearchItems.call(query: "dune")
        end
        payload = text_of(response)
        assert_equal 1, payload["pagination"]["total"]
        assert_equal "Dune", payload["items"].first["title"]
    end

    def test_get_item_includes_children_when_requested
        client = stub_client do |req|
            if req[:path].end_with?("/children")
                resp(body: [{ "key" => "CHILD001" }])
            else
                resp(body: { "key" => "ITEM0001", "data" => {} })
            end
        end
        response = with_client(client) do
            ZoteroMCP::GetItem.call(item_key: "ITEM0001", include_children: true)
        end
        payload = text_of(response)
        assert_equal "ITEM0001", payload["item"]["key"]
        assert_equal "CHILD001", payload["children"].first["key"]
    end

    def test_get_item_surfaces_not_found_as_error_text
        client = stub_client { |_req| resp(code: "404") }
        response = with_client(client) do
            ZoteroMCP::GetItem.call(item_key: "MISSING1")
        end
        assert_match(/Not found/, text_of(response)["error"])
    end

    def test_create_item_applies_fields_creators_and_tags
        captured = nil
        client = stub_client do |req|
            if req[:method] == :get
                # item template fetch
                resp(body: { "itemType" => "journalArticle", "title" => "" })
            else
                captured = JSON.parse(req[:body])
                resp(body: { "success" => { "0" => "NEWKEY01" }, "failed" => {} })
            end
        end
        response = with_client(client) do
            ZoteroMCP::CreateItem.call(
                item_type: "journalArticle",
                fields: { "title" => "A Study" },
                creators: [{ "creatorType" => "author", "lastName" => "Ada" }],
                tags: ["important"],
                collection_keys: ["COL1"],
            )
        end
        item = captured.first
        assert_equal "A Study", item["title"]
        assert_equal "Ada", item["creators"].first["lastName"]
        assert_equal [{ "tag" => "important" }], item["tags"]
        assert_equal ["COL1"], item["collections"]
        assert_equal ["NEWKEY01"], text_of(response)["created_keys"]
    end

    def test_create_note_as_child_ignores_collections
        captured = nil
        client = stub_client do |req|
            if req[:method] == :get
                resp(body: { "itemType" => "note", "note" => "" })
            else
                captured = JSON.parse(req[:body]).first
                resp(body: { "success" => { "0" => "NOTE0001" }, "failed" => {} })
            end
        end
        with_client(client) do
            ZoteroMCP::CreateNote.call(note_html: "<p>hi</p>",
                parent_item_key: "PARENT01", collection_keys: ["COL1"])
        end
        assert_equal "<p>hi</p>", captured["note"]
        assert_equal "PARENT01", captured["parentItem"]
        refute captured.key?("collections")
    end

    def test_update_item_requires_some_change
        response = with_client(stub_client) do
            ZoteroMCP::UpdateItem.call(item_key: "ITEM0001")
        end
        assert_match(/Provide fields, tags, or collection_keys/,
            text_of(response)["error"])
    end

    def test_delete_item_rejects_empty_and_oversized_batches
        empty = with_client(stub_client) { ZoteroMCP::DeleteItem.call(item_keys: []) }
        assert_match(/at least one/i, text_of(empty)["error"])

        big_keys = Array.new(ZoteroMCP::MAX_WRITE_BATCH + 1, "K")
        big = with_client(stub_client) { ZoteroMCP::DeleteItem.call(item_keys: big_keys) }
        assert_match(/at most/i, text_of(big)["error"])
    end

    def test_generate_bibliography_requires_input
        response = with_client(stub_client) do
            ZoteroMCP::GenerateBibliography.call
        end
        assert_match(/Provide item_keys or collection_key/,
            text_of(response)["error"])
    end

    def test_generate_bibliography_returns_entries
        client = stub_client { |_req| resp(body: [{ "bib" => "Ref 1" }]) }
        response = with_client(client) do
            ZoteroMCP::GenerateBibliography.call(item_keys: ["AAAA1111"], style: "ieee")
        end
        payload = text_of(response)
        assert_equal "ieee", payload["style"]
        assert_equal ["Ref 1"], payload["entries"]
    end

    def test_get_item_template_lists_types_without_argument
        client = stub_client do |req|
            assert_equal "/itemTypes", req[:path]
            resp(body: [{ "itemType" => "book", "localized" => "Book" }])
        end
        response = with_client(client) { ZoteroMCP::GetItemTemplate.call }
        assert_equal "book", text_of(response)["itemTypes"].first["itemType"]
    end

    def test_list_collections_shapes_entries
        client = stub_client do |_req|
            resp(body: [{ "key" => "COL1", "data" => { "name" => "Papers" },
                "meta" => { "numItems" => 4 } }], headers: { "Total-Results" => "1" })
        end
        response = with_client(client) { ZoteroMCP::ListCollections.call }
        collection = text_of(response)["collections"].first
        assert_equal "COL1", collection["key"]
        assert_equal "Papers", collection["name"]
        assert_equal 4, collection["numItems"]
    end

    def test_create_collection_nests_under_parent
        captured = nil
        client = stub_client do |req|
            captured = JSON.parse(req[:body]).first
            resp(body: { "success" => { "0" => "COLNEW01" }, "failed" => {} })
        end
        with_client(client) do
            ZoteroMCP::CreateCollection.call(name: "New", parent_collection_key: "PARENT01")
        end
        assert_equal "New", captured["name"]
        assert_equal "PARENT01", captured["parentCollection"]
    end
end

# frozen_string_literal: true

require_relative "test_helper"

# zotero_update_item, zotero_delete_item and zotero_create_collection: input
# validation short-circuits (flagged as errors on the wire) and payloads.
class MutateToolsTest < Minitest::Test
    def test_update_item_requires_some_change
        response = with_client(stub_client) do
            Zotero::MCP::UpdateItem.call(item_key: "ITEM0001")
        end
        assert_match(/Provide fields, tags, or collection_keys/,
                     text_of(response)["error"])
    end

    def test_delete_item_rejects_empty_and_oversized_batches
        empty = with_client(stub_client) { Zotero::MCP::DeleteItem.call(item_keys: []) }
        assert_match(/at least one/i, text_of(empty)["error"])

        big_keys = Array.new(Zotero::MCP::MAX_WRITE_BATCH + 1, "K")
        big = with_client(stub_client) { Zotero::MCP::DeleteItem.call(item_keys: big_keys) }
        assert_match(/at most/i, text_of(big)["error"])
    end

    # ------------------------------------------------------------------ #
    # Early error returns are flagged as errors (A)
    # ------------------------------------------------------------------ #

    def test_update_item_without_changes_flags_error
        response = with_client(stub_client) do
            Zotero::MCP::UpdateItem.call(item_key: "ITEM0001")
        end
        assert response.error?
    end

    def test_delete_item_rejects_oversized_batch_flags_error
        big_keys = Array.new(Zotero::MCP::MAX_WRITE_BATCH + 1, "K")
        response = with_client(stub_client) do
            Zotero::MCP::DeleteItem.call(item_keys: big_keys)
        end
        assert response.error?
    end

    def test_create_collection_nests_under_parent
        captured = nil
        client = stub_client do |req|
            captured = JSON.parse(req[:body]).first
            resp(body: { "success" => { "0" => "COLNEW01" }, "failed" => {} })
        end
        with_client(client) { call_create_collection }
        assert_equal "New", captured["name"]
        assert_equal "PARENT01", captured["parentCollection"]
    end

    private

    def call_create_collection
        Zotero::MCP::CreateCollection.call(name: "New",
                                           parent_collection_key: "PARENT01")
    end
end

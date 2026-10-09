# frozen_string_literal: true

require_relative "test_helper"

# zotero_create_item and zotero_create_note: payload building from a
# fetched template, and the parent-item-key/collection-keys conflict rule.
class CreateToolsTest < Minitest::Test
    def test_create_item_applies_fields_creators_and_tags
        capture = {}
        client = stub_client { |req| create_item_stub_response(req, capture) }
        response = with_client(client) { call_create_item }
        assert_created_item(capture[:item], text_of(response)["created_keys"])
    end

    def test_create_note_as_child_sets_parent_item
        capture = note_capturing_stub
        with_client(capture[:client]) do
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                                         parent_item_key: "PARENT01")
        end
        note = capture[:note]
        assert_equal "<p>hi</p>", note["note"]
        assert_equal "PARENT01", note["parentItem"]
        refute note.key?("collections")
    end

    # H: collection_keys only make sense for a standalone note.
    def test_create_note_rejects_parent_item_key_with_collection_keys
        client = stub_client { |_req| flunk "no request should be sent" }
        response = with_client(client) do
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                                         parent_item_key: "PARENT01",
                                         collection_keys: ["COL1"])
        end
        assert response.error?
        assert_match(/collection_keys apply only to standalone notes/,
                     text_of(response)["error"])
        assert_empty client.requests
    end

    def test_create_note_as_child_accepts_empty_collection_keys
        capture = note_capturing_stub
        response = with_client(capture[:client]) do
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                                         parent_item_key: "PARENT01",
                                         collection_keys: [])
        end
        refute response.error?
        assert_equal "PARENT01", capture[:note]["parentItem"]
        refute capture[:note].key?("collections")
    end

    private

    def create_item_stub_response(req, capture)
        return item_template_response if req[:method] == :get

        capture[:item] = JSON.parse(req[:body]).first
        created_key_response("NEWKEY01")
    end

    def call_create_item
        Zotero::MCP::CreateItem.call(
            item_type: "journalArticle", fields: { "title" => "A Study" },
            creators: [{ "creatorType" => "author", "lastName" => "Ada" }],
            tags: ["important"], collection_keys: ["COL1"]
        )
    end

    def item_template_response
        resp(body: { "itemType" => "journalArticle", "title" => "" })
    end

    def created_key_response(key)
        resp(body: { "success" => { "0" => key }, "failed" => {} })
    end

    def assert_created_item(item, created_keys)
        assert_equal "A Study", item["title"]
        assert_equal "Ada", item["creators"].first["lastName"]
        assert_equal [{ "tag" => "important" }], item["tags"]
        assert_equal ["COL1"], item["collections"]
        assert_equal ["NEWKEY01"], created_keys
    end

    def note_capturing_stub
        capture = {}
        capture[:client] = note_stub_client(capture)
        capture
    end

    def note_stub_client(capture)
        stub_client { |req| note_stub_response(req, capture) }
    end

    def note_stub_response(req, capture)
        return resp(body: { "itemType" => "note", "note" => "" }) if
            req[:method] == :get

        capture[:note] = JSON.parse(req[:body]).first
        resp(body: { "success" => { "0" => "NOTE0001" }, "failed" => {} })
    end
end

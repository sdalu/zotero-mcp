# frozen_string_literal: true

require_relative "test_helper"

# zotero_get_item_fulltext's 404 fallback: when the key has no indexed text,
# whether it looks like a parent decides which 404 the caller sees.
class FulltextErrorsTest < Minitest::Test
    def test_get_item_fulltext_raises_not_found_when_no_child_has_text
        client = stub_client { |req| no_text_children_response(req) }
        response = with_client(client) { call_fulltext("PARENT1") }
        assert response.error?
        assert_match(/No indexed full text/, text_of(response)["error"])
    end

    def test_get_item_fulltext_reraises_original_when_children_also_missing
        client = stub_client { |_req| resp(code: "404", body: "original") }
        response = with_client(client) { call_fulltext("PARENT1") }
        assert response.error?
        assert_match(/Not found/, text_of(response)["error"])
    end

    def test_get_item_fulltext_keeps_original_404_when_key_is_not_a_parent
        client = stub_client { |req| not_a_parent_response(req) }
        response = with_client(client) { call_fulltext("ATT00001") }
        assert response.error?
        message = text_of(response)["error"]
        assert_match(/Server said: no indexed text\z/, message)
        refute_match(/not a parent item/, message)
    end

    def test_get_item_fulltext_on_childless_key_says_no_text
        client = stub_client { |req| childless_key_response(req) }
        response = with_client(client) { call_fulltext("ATT00001") }
        assert response.error?
        assert_equal "No indexed full text for this item or its attachments.",
                     text_of(response)["error"]
    end

    private

    def call_fulltext(item_key)
        Zotero::MCP::GetItemFulltext.call(item_key: item_key)
    end

    def no_text_children_response(req)
        return resp(code: "404") if req[:path].end_with?("/fulltext")
        return resp(body: [not_a_parent_attachment]) if
            req[:path].end_with?("/children")

        resp(code: "404")
    end

    def not_a_parent_attachment
        { "key" => "ATT1", "data" => { "itemType" => "attachment" } }
    end

    def not_a_parent_response(req)
        if req[:path].end_with?("/children")
            resp(code: "400", body: "not a parent item")
        else
            resp(code: "404", body: "no indexed text")
        end
    end

    def childless_key_response(req)
        req[:path].end_with?("/children") ? resp(body: []) : resp(code: "404")
    end
end

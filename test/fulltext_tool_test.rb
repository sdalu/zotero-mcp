# frozen_string_literal: true

require_relative "test_helper"

# zotero_get_item_fulltext: paging through content, and resolving a parent
# key to its best attachment (PDF preferred over other attachment types).
class FulltextToolTest < Minitest::Test
    def test_get_item_fulltext_pages_content
        client = stub_client { |_req| paged_content_response }
        response = with_client(client) do
            call_fulltext(offset: 3, max_chars: 4)
        end
        assert_fulltext_page(text_of(response), paged_content_expectations)
    end

    def test_get_item_fulltext_omits_next_offset_when_exhausted
        client = stub_client { |_req| resp(body: { "content" => "hello" }) }
        response = with_client(client) { call_fulltext }
        payload = text_of(response)
        refute payload.key?("next_offset")
        assert_equal 5, payload["returned_chars"]
    end

    def test_get_item_fulltext_prefers_pdf_attachment_over_earlier_non_pdf
        client = stub_client { |req| pdf_preference_response(req) }
        response = with_client(client) { call_fulltext(item_key: "PARENT1") }
        payload = text_of(response)
        assert_equal "ATTPDF01", payload["item_key"]
        assert_equal "PARENT1", payload["parent_key"]
        assert_equal "pdf content", payload["content"]
    end

    private

    def call_fulltext(item_key: "ATT00001", offset: 0, max_chars: nil)
        if max_chars
            Zotero::MCP::GetItemFulltext.call(item_key: item_key,
                                              offset: offset,
                                              max_chars: max_chars)
        else
            Zotero::MCP::GetItemFulltext.call(item_key: item_key,
                                              offset: offset)
        end
    end

    def assert_fulltext_page(payload, expected)
        expected.each { |field, value| assert_equal value, payload[field] }
    end

    def paged_content_response
        resp(body: { "content" => "0123456789", "indexedPages" => 1,
                     "totalPages" => 1 })
    end

    def paged_content_expectations
        { "item_key" => "ATT00001", "content" => "3456", "offset" => 3,
          "returned_chars" => 4, "total_chars" => 10, "next_offset" => 7,
          "indexedPages" => 1, "totalPages" => 1 }
    end

    def pdf_children
        [
            { "key" => "NOTE0001", "data" => { "itemType" => "note" } },
            { "key" => "ATTTXT01",
              "data" => { "itemType" => "attachment",
                          "contentType" => "text/plain" } },
            { "key" => "ATTPDF01",
              "data" => { "itemType" => "attachment",
                          "contentType" => "application/pdf" } }
        ]
    end

    def pdf_preference_response(req)
        return resp(code: "404") if
            req[:path].end_with?("/items/PARENT1/fulltext")
        return resp(body: pdf_children) if req[:path].end_with?("/children")
        return resp(body: { "content" => "text content" }) if
            req[:path].end_with?("/ATTTXT01/fulltext")
        return resp(body: { "content" => "pdf content" }) if
            req[:path].end_with?("/ATTPDF01/fulltext")

        resp(code: "404")
    end
end

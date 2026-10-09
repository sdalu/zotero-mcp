# frozen_string_literal: true

require_relative "test_helper"

# zotero_generate_bibliography: input validation, the batch limit, and
# collection paging (100 items at a time, with truncated/next_start).
class BibliographyToolTest < Minitest::Test
    def test_generate_bibliography_requires_input
        response = with_client(stub_client) do
            Zotero::MCP::GenerateBibliography.call
        end
        assert_match(/Provide item_keys or collection_key/,
                     text_of(response)["error"])
    end

    def test_generate_bibliography_returns_entries
        client = stub_client { |_req| resp(body: [{ "bib" => "Ref 1" }]) }
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(item_keys: ["AAAA1111"],
                                                   style: "ieee")
        end
        payload = text_of(response)
        assert_equal "ieee", payload["style"]
        assert_equal ["Ref 1"], payload["entries"]
    end

    def test_generate_bibliography_rejects_too_many_item_keys
        client = stub_client { |_req| flunk "no request should be sent" }
        keys = Array.new(Zotero::MCP::MAX_WRITE_BATCH + 1, "AAAA1111")
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(item_keys: keys)
        end
        assert response.error?
        assert_match(/At most 50 item keys per call/,
                     text_of(response)["error"])
        assert_empty client.requests
    end

    def test_generate_bibliography_flags_truncated_results
        client = stub_client do |_req|
            resp(body: [{ "bib" => "Ref 1" }],
                 headers: { "Total-Results" => "5" })
        end
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(item_keys: ["AAAA1111"])
        end
        payload = text_of(response)
        assert_equal 5, payload["total"]
        assert payload["truncated"]
    end

    def test_generate_bibliography_pages_a_collection
        starts = []
        client = stub_client do |req|
            starts << req[:params]["start"]
            first_page_response
        end
        response = with_client(client) { call_bibliography }
        assert_equal ["0"], starts
        assert_bibliography_page(text_of(response), 99, 130, 100)
    end

    def test_generate_bibliography_last_page_has_no_next_start
        starts = []
        client = stub_client do |req|
            starts << req[:params]["start"]
            last_page_response
        end
        response = with_client(client) { call_bibliography(start: 100) }
        assert_equal ["100"], starts
        assert_no_pagination(text_of(response))
    end

    private

    def call_bibliography(start: 0)
        Zotero::MCP::GenerateBibliography.call(collection_key: "COL1",
                                               start: start)
    end

    # 100 items on the first page, one of them (a note) with no bib.
    def first_page_response
        items = Array.new(99) { |i| { "bib" => "Ref #{i}" } } + [{}]
        resp(body: items, headers: { "Total-Results" => "130" })
    end

    def last_page_response
        resp(body: Array.new(30) { |i| { "bib" => "Ref #{i}" } },
             headers: { "Total-Results" => "130" })
    end

    def assert_bibliography_page(payload, entries_count, total, next_start)
        assert_equal entries_count, payload["entries"].length
        assert_equal total, payload["total"]
        assert payload["truncated"]
        assert_equal next_start, payload["next_start"]
    end

    def assert_no_pagination(payload)
        refute payload.key?("truncated")
        refute payload.key?("next_start")
    end
end

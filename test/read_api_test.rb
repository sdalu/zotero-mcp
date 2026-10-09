# frozen_string_literal: true

require_relative "test_helper"

# Client's read-side HTTP endpoints: path building, param compaction, and the
# bibliography endpoint's item-keys-vs-collection and bib-vs-citation modes.
class ReadApiTest < Minitest::Test
    def test_search_items_builds_top_path_and_params
        client = stub_client do |_req|
            resp(body: [], headers: { "Total-Results" => "0" })
        end
        client.search_items(query: "cats", qmode: "everything",
                            item_type: "book", tag: "fun", top_only: true,
                            sort: "title", direction: "asc", limit: 10,
                            start: 5)
        assert_params(client.requests.first, "/users/42/items/top",
                      "q" => "cats", "qmode" => "everything",
                      "itemType" => "book", "limit" => "10", "start" => "5")
    end

    def test_search_items_omits_qmode_without_query
        client = stub_client { |_req| resp(body: []) }
        client.search_items(query: nil, qmode: "everything", item_type: nil,
                            tag: nil, top_only: false, sort: nil,
                            direction: nil, limit: nil, start: nil)
        req = client.requests.first
        assert_equal "/users/42/items", req[:path]
        refute req[:params].key?("qmode")
        refute req[:params].key?("q")
        assert_equal "25", req[:params]["limit"]
    end

    def test_search_items_returns_page_with_total
        client = stub_client do |_req|
            resp(body: [{ "key" => "A" }], headers: { "Total-Results" => "3" })
        end
        page = client.search_items(query: nil, qmode: nil, item_type: nil,
                                   tag: nil, top_only: true, sort: nil,
                                   direction: nil, limit: 1, start: 0)
        assert_equal 3, page.total
        assert_equal 1, page.items.length
        assert page.more?
    end

    def test_item_validates_key_before_requesting
        client = stub_client { |_req| resp(body: {}) }
        assert_raises(Zotero::MCP::Error) { client.item("bad key") }
        assert_empty client.requests
    end

    def test_collection_items_path
        client = stub_client { |_req| resp(body: [], headers: {}) }
        client.collection_items(key: "COL1", top_only: true, item_type: "book",
                                tag: nil, limit: 5, start: 0)
        req = client.requests.first
        assert_equal "/users/42/collections/COL1/items/top", req[:path]
        assert_equal "book", req[:params]["itemType"]
    end

    def test_fulltext_path
        client = stub_client { |_req| resp(body: { "content" => "text" }) }
        result = client.fulltext("ATTACH01")
        assert_equal "text", result["content"]
        assert_equal "/users/42/items/ATTACH01/fulltext",
                     client.requests.first[:path]
    end

    # ------------------------------------------------------------------ #
    # Bibliography
    # ------------------------------------------------------------------ #

    def test_bibliography_by_item_keys
        client = stub_client do |req|
            assert_item_keys_request(req)
            resp(body: [{ "bib" => "Entry one" }, { "bib" => "Entry two" }],
                 headers: { "Total-Results" => "2" })
        end
        result = client.bibliography(item_keys: %w[AAAA1111 BBBB2222],
                                     collection_key: nil, style: "apa",
                                     mode: "bibliography")
        assert_equal ["Entry one", "Entry two"], result[:entries]
        assert_equal 2, result[:total]
    end

    # F: the collection path uses /items/top, so child notes and attachments
    # pulled in by a collection contribute no bibliography entries.
    def test_bibliography_by_collection_uses_top_only_path_and_citation_mode
        client = stub_client do |req|
            assert_equal "/users/42/collections/COL1/items/top", req[:path]
            assert_equal "citation", req[:params]["include"]
            resp(body: [{ "citation" => "(Ada, 2023)" },
                        { "bib" => "ignored" }])
        end
        result = client.bibliography(item_keys: [], collection_key: "COL1",
                                     style: "ieee", mode: "citation")
        assert_equal ["(Ada, 2023)"], result[:entries]
    end

    private

    def assert_params(req, path, expected)
        assert_equal path, req[:path]
        expected.each { |key, value| assert_equal value, req[:params][key] }
    end

    def assert_item_keys_request(req)
        assert_equal "/users/42/items", req[:path]
        assert_equal "bib", req[:params]["include"]
        assert_equal "AAAA1111,BBBB2222", req[:params]["itemKey"]
    end
end

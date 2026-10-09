# frozen_string_literal: true

require_relative "test_helper"

# The MCP tool classes: their `.call` methods build the right client calls,
# surface guard errors as text, and short-circuit on invalid arguments. The
# client is stubbed via Zotero::MCP's memoized instance.
class ToolsTest < Minitest::Test
    def test_search_items_returns_formatted_summary
        client = stub_client do |req|
            assert_equal "/users/42/items/top", req[:path]
            resp(body: [{ "key" => "K1", "data" => { "itemType" => "book",
                "title" => "Dune" } }], headers: { "Total-Results" => "1" })
        end
        response = with_client(client) do
            Zotero::MCP::SearchItems.call(query: "dune")
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
            Zotero::MCP::GetItem.call(item_key: "ITEM0001", include_children: true)
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
            Zotero::MCP::CreateItem.call(
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

    def test_create_note_as_child_sets_parent_item
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
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                parent_item_key: "PARENT01")
        end
        assert_equal "<p>hi</p>", captured["note"]
        assert_equal "PARENT01", captured["parentItem"]
        refute captured.key?("collections")
    end

    # H: collection_keys only make sense for a standalone note.
    def test_create_note_rejects_parent_item_key_with_collection_keys
        client = stub_client { |_req| flunk "no request should be sent" }
        response = with_client(client) do
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                parent_item_key: "PARENT01", collection_keys: ["COL1"])
        end
        assert response.error?
        assert_match(/collection_keys apply only to standalone notes/,
            text_of(response)["error"])
        assert_empty client.requests
    end

    def test_create_note_as_child_accepts_empty_collection_keys
        captured = nil
        client = stub_client do |req|
            if req[:method] == :get
                resp(body: { "itemType" => "note", "note" => "" })
            else
                captured = JSON.parse(req[:body]).first
                resp(body: { "success" => { "0" => "NOTE0001" }, "failed" => {} })
            end
        end
        response = with_client(client) do
            Zotero::MCP::CreateNote.call(note_html: "<p>hi</p>",
                parent_item_key: "PARENT01", collection_keys: [])
        end
        refute response.error?
        assert_equal "PARENT01", captured["parentItem"]
        refute captured.key?("collections")
    end

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
            Zotero::MCP::GenerateBibliography.call(item_keys: ["AAAA1111"], style: "ieee")
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
        response = with_client(client) { Zotero::MCP::GetItemTemplate.call }
        assert_equal "book", text_of(response)["itemTypes"].first["itemType"]
    end

    def test_list_collections_shapes_entries
        client = stub_client do |_req|
            resp(body: [{ "key" => "COL1", "data" => { "name" => "Papers" },
                "meta" => { "numItems" => 4 } }], headers: { "Total-Results" => "1" })
        end
        response = with_client(client) { Zotero::MCP::ListCollections.call }
        collection = text_of(response)["collections"].first
        assert_equal "COL1", collection["key"]
        assert_equal "Papers", collection["name"]
        assert_equal 4, collection["numItems"]
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

    # ------------------------------------------------------------------ #
    # Input-schema enums (E)
    # ------------------------------------------------------------------ #

    def test_search_items_schema_declares_enums
        properties = Zotero::MCP::SearchItems.input_schema.to_h[:properties]
        assert_equal %w[titleCreatorYear everything], properties[:qmode][:enum]
        assert_equal %w[asc desc], properties[:direction][:enum]
        assert_equal %w[summary json], properties[:response_format][:enum]
    end

    def test_get_collection_items_schema_declares_response_format_enum
        properties = Zotero::MCP::GetCollectionItems.input_schema.to_h[:properties]
        assert_equal %w[summary json], properties[:response_format][:enum]
    end

    def test_generate_bibliography_schema_declares_mode_enum
        properties = Zotero::MCP::GenerateBibliography.input_schema.to_h[:properties]
        assert_equal %w[bibliography citation], properties[:mode][:enum]
    end

    # ------------------------------------------------------------------ #
    # Bibliography batch limit and truncation (F)
    # ------------------------------------------------------------------ #

    def test_generate_bibliography_rejects_too_many_item_keys
        client = stub_client { |_req| flunk "no request should be sent" }
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(
                item_keys: Array.new(Zotero::MCP::MAX_WRITE_BATCH + 1, "AAAA1111"),
            )
        end
        assert response.error?
        assert_match(/At most 50 item keys per call/, text_of(response)["error"])
        assert_empty client.requests
    end

    def test_generate_bibliography_flags_truncated_results
        client = stub_client do |_req|
            resp(body: [{ "bib" => "Ref 1" }], headers: { "Total-Results" => "5" })
        end
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(item_keys: ["AAAA1111"])
        end
        payload = text_of(response)
        assert_equal 5, payload["total"]
        assert payload["truncated"]
    end

    # ------------------------------------------------------------------ #
    # Full-text paging and parent resolution (G)
    # ------------------------------------------------------------------ #

    def test_get_item_fulltext_pages_content
        client = stub_client do |_req|
            resp(body: { "content" => "0123456789", "indexedPages" => 1,
                "totalPages" => 1 })
        end
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "ATT00001", offset: 3, max_chars: 4)
        end
        payload = text_of(response)
        assert_equal "ATT00001", payload["item_key"]
        assert_equal "3456", payload["content"]
        assert_equal 3, payload["offset"]
        assert_equal 4, payload["returned_chars"]
        assert_equal 10, payload["total_chars"]
        assert_equal 7, payload["next_offset"]
        assert_equal 1, payload["indexedPages"]
        assert_equal 1, payload["totalPages"]
    end

    def test_get_item_fulltext_omits_next_offset_when_exhausted
        client = stub_client { |_req| resp(body: { "content" => "hello" }) }
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "ATT00001")
        end
        payload = text_of(response)
        refute payload.key?("next_offset")
        assert_equal 5, payload["returned_chars"]
    end

    def test_get_item_fulltext_prefers_pdf_attachment_over_earlier_non_pdf
        client = stub_client do |req|
            if req[:path].end_with?("/items/PARENT1/fulltext")
                resp(code: "404")
            elsif req[:path].end_with?("/children")
                resp(body: [
                    { "key" => "NOTE0001", "data" => { "itemType" => "note" } },
                    { "key" => "ATTTXT01", "data" => { "itemType" => "attachment",
                        "contentType" => "text/plain" } },
                    { "key" => "ATTPDF01", "data" => { "itemType" => "attachment",
                        "contentType" => "application/pdf" } },
                ])
            elsif req[:path].end_with?("/ATTTXT01/fulltext")
                resp(body: { "content" => "text content" })
            elsif req[:path].end_with?("/ATTPDF01/fulltext")
                resp(body: { "content" => "pdf content" })
            else
                resp(code: "404")
            end
        end
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "PARENT1")
        end
        payload = text_of(response)
        assert_equal "ATTPDF01", payload["item_key"]
        assert_equal "PARENT1", payload["parent_key"]
        assert_equal "pdf content", payload["content"]
    end

    def test_get_item_fulltext_raises_not_found_when_no_child_has_text
        client = stub_client do |req|
            if req[:path].end_with?("/fulltext")
                resp(code: "404")
            elsif req[:path].end_with?("/children")
                resp(body: [
                    { "key" => "ATT1", "data" => { "itemType" => "attachment" } },
                ])
            else
                resp(code: "404")
            end
        end
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "PARENT1")
        end
        assert response.error?
        assert_match(/No indexed full text/, text_of(response)["error"])
    end

    def test_get_item_fulltext_reraises_original_when_children_also_missing
        client = stub_client { |_req| resp(code: "404", body: "original") }
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "PARENT1")
        end
        assert response.error?
        assert_match(/Not found/, text_of(response)["error"])
    end

    def test_get_item_fulltext_keeps_original_404_when_key_is_not_a_parent
        client = stub_client do |req|
            if req[:path].end_with?("/children")
                resp(code: "400", body: "not a parent item")
            else
                resp(code: "404", body: "no indexed text")
            end
        end
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "ATT00001")
        end
        assert response.error?
        message = text_of(response)["error"]
        assert_match(/Server said: no indexed text\z/, message)
        refute_match(/not a parent item/, message)
    end

    def test_get_item_fulltext_on_childless_key_says_no_text
        client = stub_client do |req|
            if req[:path].end_with?("/children")
                resp(body: [])
            else
                resp(code: "404")
            end
        end
        response = with_client(client) do
            Zotero::MCP::GetItemFulltext.call(item_key: "ATT00001")
        end
        assert response.error?
        assert_equal "No indexed full text for this item or its attachments.",
            text_of(response)["error"]
    end

    # ------------------------------------------------------------------ #
    # Bibliography paging
    # ------------------------------------------------------------------ #

    def test_generate_bibliography_pages_a_collection
        starts = []
        client = stub_client do |req|
            starts << req[:params]["start"]
            # 100 items on the first page, one of them (a note) with no bib.
            items = Array.new(99) { |i| { "bib" => "Ref #{i}" } } + [{}]
            resp(body: items, headers: { "Total-Results" => "130" })
        end
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(collection_key: "COL1")
        end
        payload = text_of(response)
        assert_equal ["0"], starts
        assert_equal 99, payload["entries"].length
        assert_equal 130, payload["total"]
        assert payload["truncated"]
        assert_equal 100, payload["next_start"]
    end

    def test_generate_bibliography_last_page_has_no_next_start
        starts = []
        client = stub_client do |req|
            starts << req[:params]["start"]
            resp(body: Array.new(30) { |i| { "bib" => "Ref #{i}" } },
                headers: { "Total-Results" => "130" })
        end
        response = with_client(client) do
            Zotero::MCP::GenerateBibliography.call(collection_key: "COL1",
                start: 100)
        end
        payload = text_of(response)
        assert_equal ["100"], starts
        refute payload.key?("truncated")
        refute payload.key?("next_start")
    end

    def test_create_collection_nests_under_parent
        captured = nil
        client = stub_client do |req|
            captured = JSON.parse(req[:body]).first
            resp(body: { "success" => { "0" => "COLNEW01" }, "failed" => {} })
        end
        with_client(client) do
            Zotero::MCP::CreateCollection.call(name: "New", parent_collection_key: "PARENT01")
        end
        assert_equal "New", captured["name"]
        assert_equal "PARENT01", captured["parentCollection"]
    end
end

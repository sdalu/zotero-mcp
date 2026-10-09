# frozen_string_literal: true

require_relative "test_helper"

# Item summarization (summarize and its field-picking helpers) and the page
# formatting / pagination-block helpers built on top of it.
class FormattingTest < Minitest::Test
    def sample_item
        { "key" => "ABCD2345", "version" => 7, "data" => sample_data,
          "meta" => { "numChildren" => 2 } }
    end

    def sample_data
        {
            "itemType" => "journalArticle", "title" => "On Testing",
            "date" => "2023", "DOI" => "10.1/x", "url" => "http://x",
            "publicationTitle" => "J. Tests",
            "creators" => [{ "creatorType" => "author", "firstName" => "Ada",
                             "lastName" => "Lovelace" }],
            "tags" => [{ "tag" => "science" }, { "tag" => "history" }],
            "collections" => ["COL1"]
        }
    end

    def test_summarize_extracts_key_fields
        summary = Zotero::MCP.summarize(sample_item)
        expected = {
            key: "ABCD2345", itemType: "journalArticle",
            title: "On Testing", creators: "Ada Lovelace",
            publication: "J. Tests", tags: %w[science history],
            collections: ["COL1"], numChildren: 2
        }
        expected.each { |field, value| assert_equal value, summary[field] }
    end

    def test_summarize_omits_absent_fields
        summary = Zotero::MCP.summarize("key" => "K1",
                                        "data" => { "itemType" => "note" })
        assert_equal "K1", summary[:key]
        refute summary.key?(:title)
        refute summary.key?(:tags)
        refute summary.key?(:collections)
    end

    def test_title_falls_back_to_case_and_subject
        assert_equal "T",
                     Zotero::MCP.title_of("title" => "T", "caseName" => "C")
        assert_equal "C", Zotero::MCP.title_of("caseName" => "C")
        assert_equal "S", Zotero::MCP.title_of("subject" => "S")
    end

    def test_publication_fallback_order
        assert_equal "P", Zotero::MCP.publication_of("publicationTitle" => "P",
                                                     "bookTitle" => "B")
        assert_equal "B", Zotero::MCP.publication_of("bookTitle" => "B")
        assert_equal "Pub", Zotero::MCP.publication_of("publisher" => "Pub")
    end

    def test_creators_uses_name_field
        data = { "creators" => [{ "name" => "OpenAI" }] }
        assert_equal "OpenAI", Zotero::MCP.creators_of(data, {})
    end

    def test_creators_truncates_after_three
        data = {
            "creators" => (1..5).map { |i| { "lastName" => "Author#{i}" } }
        }
        assert_equal "Author1, Author2, Author3 (+2 more)",
                     Zotero::MCP.creators_of(data, {})
    end

    def test_creators_fall_back_to_creator_summary
        meta = { "creatorSummary" => "Curie et al." }
        assert_equal "Curie et al.", Zotero::MCP.creators_of({}, meta)
        assert_nil Zotero::MCP.creators_of({}, {})
    end

    def test_summarize_prefers_parsed_date_when_no_date
        item = { "key" => "K", "data" => { "itemType" => "book" },
                 "meta" => { "parsedDate" => "2020-01-02" } }
        assert_equal "2020-01-02", Zotero::MCP.summarize(item)[:date]
    end

    # ------------------------------------------------------------------ #
    # Page formatting / pagination
    # ------------------------------------------------------------------ #

    def test_format_page_summary_vs_json
        page = Zotero::MCP::Page.new(items: [sample_item], total: 1, start: 0)

        summary = Zotero::MCP.format_page(page, "summary")
        assert_equal "On Testing", summary[:items].first[:title]

        raw = Zotero::MCP.format_page(page, "json")
        assert_equal sample_item, raw[:items].first
    end

    def test_pagination_of_compacts_nil_fields
        page = Zotero::MCP::Page.new(items: Array.new(3), total: nil, start: 0)
        pagination = Zotero::MCP.pagination_of(page)
        assert_equal 3, pagination[:count]
        assert_equal 0, pagination[:start]
        assert_equal false, pagination[:has_more]
        refute pagination.key?(:total)
        refute pagination.key?(:next_start)
    end
end

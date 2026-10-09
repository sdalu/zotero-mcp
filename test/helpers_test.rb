# frozen_string_literal: true

require_relative "test_helper"

# Pure helpers, value objects, configuration and formatting: everything that
# needs no HTTP client.
class HelpersTest < Minitest::Test
    # ------------------------------------------------------------------ #
    # Small helpers
    # ------------------------------------------------------------------ #

    def test_truthy_accepts_common_true_words_case_insensitively
        %w[1 true TRUE yes Yes on ON].each do |value|
            assert Zotero::MCP.truthy?(value), value.inspect
        end
    end

    def test_truthy_rejects_everything_else
        [nil, "", "0", "false", "no", "off", "maybe", 2].each do |value|
            refute Zotero::MCP.truthy?(value), value.inspect
        end
    end

    def test_presence_strips_and_nils_blanks
        assert_equal "abc", Zotero::MCP.presence("  abc  ")
        assert_nil Zotero::MCP.presence("   ")
        assert_nil Zotero::MCP.presence(nil)
    end

    def test_clamp_limit_defaults_and_caps
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(nil)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(0)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(-5)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit("10")
        assert_equal 10, Zotero::MCP.clamp_limit(10)
        assert_equal Zotero::MCP::MAX_LIMIT, Zotero::MCP.clamp_limit(1000)
    end

    def test_clamp_start_keeps_positive_ints_else_zero
        assert_equal 7, Zotero::MCP.clamp_start(7)
        assert_equal 0, Zotero::MCP.clamp_start(0)
        assert_equal 0, Zotero::MCP.clamp_start(-3)
        assert_equal 0, Zotero::MCP.clamp_start("4")
        assert_equal 0, Zotero::MCP.clamp_start(nil)
    end

    def test_validate_key_accepts_alphanumeric
        assert_equal "ABCD2345", Zotero::MCP.validate_key!("ABCD2345")
        assert_equal "a1", Zotero::MCP.validate_key!("a1")
    end

    def test_validate_key_rejects_bad_input
        ["", "AB CD", "abc/def", "a" * 33, nil, "a-b"].each do |bad|
            assert_raises(Zotero::MCP::Error) { Zotero::MCP.validate_key!(bad) }
        end
    end

    def test_compact_drops_nil_and_empty_string_only
        result = Zotero::MCP.compact(a: 1, b: nil, c: "", d: false, e: 0)
        assert_equal({ a: 1, d: false, e: 0 }, result)
    end

    def test_batch_error_messages
        assert_match(/at least one/i, Zotero::MCP.batch_error([]))
        assert_nil Zotero::MCP.batch_error(%w[A B])
        assert_nil Zotero::MCP.batch_error(Array.new(Zotero::MCP::MAX_WRITE_BATCH, "K"))
        assert_match(/at most/i,
            Zotero::MCP.batch_error(Array.new(Zotero::MCP::MAX_WRITE_BATCH + 1, "K")))
    end

    def test_nonempty
        assert_nil Zotero::MCP.nonempty(nil)
        assert_nil Zotero::MCP.nonempty([])
        assert_equal [1], Zotero::MCP.nonempty([1])
    end

    # ------------------------------------------------------------------ #
    # Config
    # ------------------------------------------------------------------ #

    def test_config_base_url_and_write_allowed
        web = build_config(local: false)
        assert_equal Zotero::MCP::WEB_BASE, web.base_url
        assert web.write_allowed?

        local = build_config(local: true)
        assert_equal Zotero::MCP::LOCAL_BASE, local.base_url
        refute local.write_allowed?
    end

    def test_config_from_env_defaults_to_user
        with_env("ZOTERO_API_KEY" => "K", "ZOTERO_LIBRARY_ID" => "9",
            "ZOTERO_LIBRARY_TYPE" => nil, "ZOTERO_LOCAL" => nil) do
            config = Zotero::MCP::Config.from_env
            assert_equal "user", config.library_type
            assert_equal "K", config.api_key
            assert_equal "9", config.library_id
            refute config.local
        end
    end

    def test_config_from_env_blank_key_becomes_nil
        with_env("ZOTERO_API_KEY" => "   ", "ZOTERO_LIBRARY_ID" => nil,
            "ZOTERO_LIBRARY_TYPE" => "group", "ZOTERO_LOCAL" => "yes") do
            config = Zotero::MCP::Config.from_env
            assert_nil config.api_key
            assert_nil config.library_id
            assert_equal "group", config.library_type
            assert config.local
        end
    end

    def test_config_from_env_rejects_bad_type
        with_env("ZOTERO_LIBRARY_TYPE" => "team") do
            assert_raises(Zotero::MCP::ConfigurationError) { Zotero::MCP::Config.from_env }
        end
    end

    # ------------------------------------------------------------------ #
    # Page
    # ------------------------------------------------------------------ #

    def test_page_pagination_math
        page = Zotero::MCP::Page.new(items: Array.new(25), total: 100, start: 0)
        assert page.has_more?
        assert_equal 25, page.next_start
    end

    def test_page_last_page_has_no_more
        page = Zotero::MCP::Page.new(items: Array.new(10), total: 30, start: 20)
        refute page.has_more?
        assert_nil page.next_start
    end

    def test_page_without_total_is_terminal
        page = Zotero::MCP::Page.new(items: Array.new(5), total: nil, start: 0)
        refute page.has_more?
        assert_nil page.next_start
    end

    # ------------------------------------------------------------------ #
    # Formatting: summarize and friends
    # ------------------------------------------------------------------ #

    def sample_item
        {
            "key" => "ABCD2345", "version" => 7,
            "data" => {
                "itemType" => "journalArticle", "title" => "On Testing",
                "date" => "2023", "DOI" => "10.1/x", "url" => "http://x",
                "publicationTitle" => "J. Tests",
                "creators" => [
                    { "creatorType" => "author", "firstName" => "Ada",
                      "lastName" => "Lovelace" },
                ],
                "tags" => [{ "tag" => "science" }, { "tag" => "history" }],
                "collections" => ["COL1"],
            },
            "meta" => { "numChildren" => 2 },
        }
    end

    def test_summarize_extracts_key_fields
        summary = Zotero::MCP.summarize(sample_item)
        assert_equal "ABCD2345", summary[:key]
        assert_equal "journalArticle", summary[:itemType]
        assert_equal "On Testing", summary[:title]
        assert_equal "Ada Lovelace", summary[:creators]
        assert_equal "J. Tests", summary[:publication]
        assert_equal %w[science history], summary[:tags]
        assert_equal ["COL1"], summary[:collections]
        assert_equal 2, summary[:numChildren]
    end

    def test_summarize_omits_absent_fields
        summary = Zotero::MCP.summarize("key" => "K1", "data" => { "itemType" => "note" })
        assert_equal "K1", summary[:key]
        refute summary.key?(:title)
        refute summary.key?(:tags)
        refute summary.key?(:collections)
    end

    def test_title_falls_back_to_case_and_subject
        assert_equal "T", Zotero::MCP.title_of("title" => "T", "caseName" => "C")
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
            "creators" => (1..5).map { |i| { "lastName" => "Author#{i}" } },
        }
        assert_equal "Author1, Author2, Author3 (+2 more)",
            Zotero::MCP.creators_of(data, {})
    end

    def test_creators_fall_back_to_creator_summary
        assert_equal "Curie et al.",
            Zotero::MCP.creators_of({}, { "creatorSummary" => "Curie et al." })
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

    # ------------------------------------------------------------------ #
    # text / guard
    # ------------------------------------------------------------------ #

    def test_text_wraps_pretty_json
        response = Zotero::MCP.text(hello: "world")
        assert_equal "text", response.content.first[:type]
        assert_equal({ "hello" => "world" }, text_of(response))
    end

    def test_guard_converts_domain_errors_to_text
        response = Zotero::MCP.guard { raise Zotero::MCP::NotFoundError, "gone" }
        assert_equal "gone", text_of(response)["error"]
    end

    def test_guard_labels_unexpected_errors
        response = Zotero::MCP.guard { raise ArgumentError, "boom" }
        assert_match(/Unexpected ArgumentError: boom/, text_of(response)["error"])
    end

    def test_guard_passes_through_success
        response = Zotero::MCP.guard { Zotero::MCP.text(ok: true) }
        assert_equal({ "ok" => true }, text_of(response))
    end

    # ------------------------------------------------------------------ #
    # error_text / guard error flagging (A)
    # ------------------------------------------------------------------ #

    def test_error_text_sets_error_flag_and_body
        response = Zotero::MCP.error_text("gone")
        assert response.error?
        assert_equal({ "error" => "gone" }, text_of(response))
    end

    def test_guard_flags_domain_errors_as_error
        response = Zotero::MCP.guard { raise Zotero::MCP::NotFoundError, "gone" }
        assert response.error?
    end

    def test_guard_flags_unexpected_errors_as_error
        response = Zotero::MCP.guard { raise ArgumentError, "boom" }
        assert response.error?
    end

    def test_guard_success_is_not_flagged_as_error
        response = Zotero::MCP.guard { Zotero::MCP.text(ok: true) }
        refute response.error?
    end

    # ------------------------------------------------------------------ #
    # clamp_max_chars (G)
    # ------------------------------------------------------------------ #

    def test_clamp_max_chars_defaults_and_caps
        assert_equal Zotero::MCP::DEFAULT_MAX_CHARS, Zotero::MCP.clamp_max_chars(nil)
        assert_equal Zotero::MCP::DEFAULT_MAX_CHARS, Zotero::MCP.clamp_max_chars(0)
        assert_equal Zotero::MCP::DEFAULT_MAX_CHARS, Zotero::MCP.clamp_max_chars(-5)
        assert_equal Zotero::MCP::DEFAULT_MAX_CHARS, Zotero::MCP.clamp_max_chars("100")
        assert_equal 500, Zotero::MCP.clamp_max_chars(500)
        assert_equal Zotero::MCP::MAX_MAX_CHARS, Zotero::MCP.clamp_max_chars(1_000_000)
    end
end

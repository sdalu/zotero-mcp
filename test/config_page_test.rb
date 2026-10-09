# frozen_string_literal: true

require_relative "test_helper"

# Config (env parsing, base_url, write_allowed?) and Page (pagination math).
class ConfigPageTest < Minitest::Test
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
            assert_raises(Zotero::MCP::ConfigurationError) do
                Zotero::MCP::Config.from_env
            end
        end
    end

    # ------------------------------------------------------------------ #
    # Page
    # ------------------------------------------------------------------ #

    def test_page_pagination_math
        page = Zotero::MCP::Page.new(items: Array.new(25), total: 100, start: 0)
        assert page.more?
        assert_equal 25, page.next_start
    end

    def test_page_last_page_has_no_more
        page = Zotero::MCP::Page.new(items: Array.new(10), total: 30, start: 20)
        refute page.more?
        assert_nil page.next_start
    end

    def test_page_without_total_is_terminal
        page = Zotero::MCP::Page.new(items: Array.new(5), total: nil, start: 0)
        refute page.more?
        assert_nil page.next_start
    end
end

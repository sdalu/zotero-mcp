# frozen_string_literal: true

require_relative "test_helper"

# The HTTP client core: status handling, retry-on-429, read endpoints,
# write endpoints, and library-id resolution. No real network is used; the
# StubClient records requests and returns canned FakeResponses.
class ClientTest < Minitest::Test
    # ------------------------------------------------------------------ #
    # Response status handling
    # ------------------------------------------------------------------ #

    def test_handle_returns_response_for_2xx
        client = stub_client
        ok = resp(code: "204")
        assert_same ok, client.send(:handle, ok)
    end

    def test_handle_maps_status_codes_to_errors
        client = stub_client
        {
            "403" => ZoteroMCP::NotAuthorisedError,
            "404" => ZoteroMCP::NotFoundError,
            "412" => ZoteroMCP::ConflictError,
            "500" => ZoteroMCP::APIError,
        }.each do |code, klass|
            assert_raises(klass) { client.send(:handle, resp(code: code)) }
        end
    end

    def test_rate_limited_reads_retry_after_then_backoff
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "429", headers: { "Retry-After" => "5" }))
        end
        assert_equal 5, error.retry_after

        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "429", headers: { "Backoff" => "3" }))
        end
        assert_equal 3, error.retry_after
    end

    def test_rate_limited_without_header_has_nil_retry_after
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "429"))
        end
        assert_nil error.retry_after
        assert_match(/a few seconds/, error.message)
    end

    # ------------------------------------------------------------------ #
    # Server-said body suffixes (B)
    # ------------------------------------------------------------------ #

    def test_handle_appends_response_body_to_error_message
        client = stub_client
        error = assert_raises(ZoteroMCP::NotAuthorisedError) do
            client.send(:handle, resp(code: "403", body: "key disabled"))
        end
        assert_match(/Server said: key disabled\z/, error.message)
    end

    def test_handle_omits_suffix_when_body_is_blank
        client = stub_client
        error = assert_raises(ZoteroMCP::NotFoundError) do
            client.send(:handle, resp(code: "404", body: "   "))
        end
        refute_match(/Server said/, error.message)
    end

    def test_handle_truncates_long_response_body
        client = stub_client
        error = assert_raises(ZoteroMCP::APIError) do
            client.send(:handle, resp(code: "500", body: "x" * 600))
        end
        assert_match(/Server said: #{"x" * 500}…\z/, error.message)
    end

    def test_rate_limited_message_includes_body_suffix
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "429",
                headers: { "Retry-After" => "5" }, body: "slow down"))
        end
        assert_match(/Server said: slow down\z/, error.message)
    end

    # ------------------------------------------------------------------ #
    # 503 retry (C)
    # ------------------------------------------------------------------ #

    def test_service_unavailable_with_retry_after_is_rate_limited
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "503", headers: { "Retry-After" => "4" }))
        end
        assert_equal 4, error.retry_after
        assert_equal "Service unavailable (503). Retry in 4 seconds.", error.message
    end

    def test_service_unavailable_message_includes_body_suffix
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "503",
                headers: { "Retry-After" => "4" }, body: "maintenance"))
        end
        assert_match(/\AService unavailable \(503\)\. Retry in 4 seconds\./,
            error.message)
        assert_match(/Server said: maintenance\z/, error.message)
    end

    def test_service_unavailable_with_backoff_is_rate_limited
        client = stub_client
        error = assert_raises(ZoteroMCP::RateLimitedError) do
            client.send(:handle, resp(code: "503", headers: { "Backoff" => "9" }))
        end
        assert_equal 9, error.retry_after
    end

    def test_service_unavailable_without_header_is_api_error
        client = stub_client
        assert_raises(ZoteroMCP::APIError) do
            client.send(:handle, resp(code: "503"))
        end
    end

    def test_request_retries_after_503_then_succeeds
        attempts = 0
        client = stub_client do |_req|
            attempts += 1
            attempts == 1 ? resp(code: "503", headers: { "Retry-After" => "1" }) \
                          : resp(code: "200", body: { ok: true })
        end
        response = client.request(:get, "/users/42/items")
        assert_equal "200", response.code
        assert_equal [1], client.sleeps
    end

    # ------------------------------------------------------------------ #
    # Retry loop
    # ------------------------------------------------------------------ #

    def test_request_retries_after_429_then_succeeds
        attempts = 0
        client = stub_client do |_req|
            attempts += 1
            attempts == 1 ? resp(code: "429", headers: { "Retry-After" => "1" }) \
                          : resp(code: "200", body: { ok: true })
        end
        response = client.request(:get, "/users/42/items")
        assert_equal "200", response.code
        assert_equal [1], client.sleeps
        assert_equal 2, attempts
    end

    def test_request_gives_up_after_max_retries
        client = stub_client do |_req|
            resp(code: "429", headers: { "Retry-After" => "1" })
        end
        assert_raises(ZoteroMCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_equal ZoteroMCP::MAX_RETRIES, client.sleeps.length
    end

    def test_request_does_not_retry_without_retry_after
        calls = 0
        client = stub_client do |_req|
            calls += 1
            resp(code: "429")
        end
        assert_raises(ZoteroMCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_equal 1, calls
        assert_empty client.sleeps
    end

    def test_request_does_not_retry_when_backoff_exceeds_cap
        client = stub_client do |_req|
            resp(code: "429", headers: { "Retry-After" => (ZoteroMCP::MAX_BACKOFF + 1).to_s })
        end
        assert_raises(ZoteroMCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_empty client.sleeps
    end

    # ------------------------------------------------------------------ #
    # prefix / library id
    # ------------------------------------------------------------------ #

    def test_prefix_uses_type_and_id
        assert_equal "/users/42", stub_client.prefix
        assert_equal "/groups/99",
            stub_client(build_config(library_type: "group", library_id: "99")).prefix
    end

    def test_library_id_resolves_from_current_key
        client = stub_client(build_config(library_id: nil)) do |req|
            assert_equal "/keys/current", req[:path]
            resp(body: { "userID" => 777 })
        end
        assert_equal "777", client.library_id
        assert_equal "/users/777", client.prefix
    end

    def test_group_without_id_raises
        client = stub_client(build_config(library_type: "group", library_id: nil))
        assert_raises(ZoteroMCP::ConfigurationError) { client.library_id }
    end

    def test_user_without_key_or_id_raises
        client = stub_client(build_config(api_key: nil, library_id: nil))
        assert_raises(ZoteroMCP::ConfigurationError) { client.library_id }
    end

    def test_local_library_id_is_zero
        client = stub_client(build_config(local: true, library_id: nil))
        assert_equal "0", client.library_id
    end

    # ------------------------------------------------------------------ #
    # Read endpoints
    # ------------------------------------------------------------------ #

    def test_search_items_builds_top_path_and_params
        client = stub_client do |req|
            resp(body: [], headers: { "Total-Results" => "0" })
        end
        client.search_items(query: "cats", qmode: "everything", item_type: "book",
            tag: "fun", top_only: true, sort: "title", direction: "asc",
            limit: 10, start: 5)
        req = client.requests.first
        assert_equal "/users/42/items/top", req[:path]
        assert_equal "cats", req[:params]["q"]
        assert_equal "everything", req[:params]["qmode"]
        assert_equal "book", req[:params]["itemType"]
        assert_equal "10", req[:params]["limit"]
        assert_equal "5", req[:params]["start"]
    end

    def test_search_items_omits_qmode_without_query
        client = stub_client { |_req| resp(body: []) }
        client.search_items(query: nil, qmode: "everything", item_type: nil,
            tag: nil, top_only: false, sort: nil, direction: nil,
            limit: nil, start: nil)
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
            tag: nil, top_only: true, sort: nil, direction: nil,
            limit: 1, start: 0)
        assert_equal 3, page.total
        assert_equal 1, page.items.length
        assert page.has_more?
    end

    def test_item_validates_key_before_requesting
        client = stub_client { |_req| resp(body: {}) }
        assert_raises(ZoteroMCP::Error) { client.item("bad key") }
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
        assert_equal "/users/42/items/ATTACH01/fulltext", client.requests.first[:path]
    end

    # ------------------------------------------------------------------ #
    # Bibliography
    # ------------------------------------------------------------------ #

    def test_bibliography_by_item_keys
        client = stub_client do |req|
            assert_equal "/users/42/items", req[:path]
            assert_equal "bib", req[:params]["include"]
            assert_equal "AAAA1111,BBBB2222", req[:params]["itemKey"]
            resp(body: [{ "bib" => "Entry one" }, { "bib" => "Entry two" }],
                headers: { "Total-Results" => "2" })
        end
        result = client.bibliography(item_keys: %w[AAAA1111 BBBB2222],
            collection_key: nil, style: "apa", mode: "bibliography")
        assert_equal ["Entry one", "Entry two"], result[:entries]
        assert_equal 2, result[:total]
    end

    # F: the collection path uses /items/top, so child notes and attachments
    # pulled in by a collection contribute no bibliography entries.
    def test_bibliography_by_collection_uses_top_only_path_and_citation_mode
        client = stub_client do |req|
            assert_equal "/users/42/collections/COL1/items/top", req[:path]
            assert_equal "citation", req[:params]["include"]
            resp(body: [{ "citation" => "(Ada, 2023)" }, { "bib" => "ignored" }])
        end
        result = client.bibliography(item_keys: [], collection_key: "COL1",
            style: "ieee", mode: "citation")
        assert_equal ["(Ada, 2023)"], result[:entries]
    end

    # ------------------------------------------------------------------ #
    # Write endpoints
    # ------------------------------------------------------------------ #

    def test_create_items_normalizes_success_map
        client = stub_client do |req|
            assert_equal :post, req[:method]
            resp(body: { "success" => { "0" => "NEWKEY01" }, "failed" => {} })
        end
        result = client.create_items([{ "itemType" => "book" }])
        assert result[:success]
        assert_equal ["NEWKEY01"], result[:created_keys]
        refute result.key?(:failed)
    end

    def test_create_items_reports_failures_and_unchanged
        client = stub_client do |_req|
            resp(body: {
                "successful" => { "0" => { "key" => "OKKEY001" } },
                "failed" => { "1" => { "code" => 400, "message" => "bad" } },
                "unchanged" => { "2" => "SAMEKEY0" },
            })
        end
        result = client.create_items([{}, {}, {}])
        refute result[:success]
        assert_equal ["OKKEY001"], result[:created_keys]
        assert_equal "bad", result[:failed]["1"]["message"]
        assert result.key?(:unchanged)
    end

    def test_update_item_fetches_version_then_patches
        seen = []
        client = stub_client do |req|
            seen << req[:method]
            case req[:method]
            when :get then resp(body: { "key" => "ITEM0001", "version" => 12 })
            else resp(code: "204")
            end
        end
        result = client.update_item(key: "ITEM0001", changes: { "title" => "New" })
        assert result[:success]
        assert_equal "ITEM0001", result[:key]
        assert_equal %i[get patch], seen
        patch = client.requests.last
        assert_equal "12", patch[:headers]["If-Unmodified-Since-Version"]
        assert_equal({ "title" => "New" }, JSON.parse(patch[:body]))
    end

    def test_delete_items_partitions_success_and_failure
        client = stub_client do |req|
            if req[:path].end_with?("/GONE0001")
                resp(code: "404")
            elsif req[:method] == :get
                resp(body: { "version" => 4 })
            else
                resp(code: "204")
            end
        end
        result = client.delete_items(%w[OK000001 GONE0001])
        assert_equal ["OK000001"], result[:deleted]
        assert_equal 1, result[:failed].length
        assert_equal "GONE0001", result[:failed].first[:key]
    end

    def test_add_to_collection_merges_without_duplicates
        client = stub_client do |req|
            if req[:method] == :get
                resp(body: { "version" => 1, "data" => { "collections" => ["EXIST001"] } })
            else
                resp(code: "204")
            end
        end
        result = client.add_to_collection(collection_key: "TARGET01", keys: ["ITEM0001"])
        assert_equal ["ITEM0001"], result[:added]
        patch = client.requests.last
        assert_equal %w[EXIST001 TARGET01], JSON.parse(patch[:body])["collections"]
    end

    def test_write_json_sends_write_token_once_and_reuses_on_retry
        tokens = []
        attempts = 0
        client = stub_client do |req|
            tokens << req[:headers]["Zotero-Write-Token"]
            attempts += 1
            attempts == 1 ? resp(code: "429", headers: { "Retry-After" => "1" }) \
                          : resp(body: { "success" => {}, "failed" => {} })
        end
        client.create_items([{ "itemType" => "book" }])
        assert_equal 2, tokens.length
        assert_match(/\A[0-9a-f]{32}\z/, tokens.first)
        assert_equal tokens.first, tokens.last
    end

    def test_writes_blocked_on_local_config
        client = stub_client(build_config(local: true, library_id: nil))
        assert_raises(ZoteroMCP::ReadOnlyError) do
            client.create_items([{ "itemType" => "book" }])
        end
        assert_empty client.requests
    end

    # ------------------------------------------------------------------ #
    # JSON parsing / headers
    # ------------------------------------------------------------------ #

    def test_invalid_json_raises_api_error
        client = stub_client { |_req| resp(body: "<html>not json</html>") }
        assert_raises(ZoteroMCP::APIError) { client.item("ABCD1234") }
    end

    def test_default_headers_carry_api_version_and_key
        headers = stub_client.send(:default_headers)
        assert_equal ZoteroMCP::API_VERSION, headers["Zotero-API-Version"]
        assert_equal "KEY123", headers["Zotero-API-Key"]
    end

    def test_default_headers_omit_key_when_absent
        headers = stub_client(build_config(api_key: nil)).send(:default_headers)
        refute headers.key?("Zotero-API-Key")
    end
end

# frozen_string_literal: true

require_relative "test_helper"

# Response status handling: 2xx pass-through, status-to-error mapping, and
# the "Server said: ..." body suffix appended to error messages.
class ResponseStatusTest < Minitest::Test
    def test_handle_returns_response_for_2xx
        client = stub_client
        ok = resp(code: "204")
        assert_same ok, client.send(:handle, ok)
    end

    def test_handle_maps_status_codes_to_errors
        client = stub_client
        {
            "403" => Zotero::MCP::NotAuthorisedError,
            "404" => Zotero::MCP::NotFoundError,
            "412" => Zotero::MCP::ConflictError,
            "500" => Zotero::MCP::APIError
        }.each do |code, klass|
            assert_raises(klass) { client.send(:handle, resp(code: code)) }
        end
    end

    def test_rate_limited_reads_retry_after_then_backoff
        client = stub_client
        error = rate_limited_error(client, "Retry-After" => "5")
        assert_equal 5, error.retry_after

        error = rate_limited_error(client, "Backoff" => "3")
        assert_equal 3, error.retry_after
    end

    def test_rate_limited_without_header_has_nil_retry_after
        client = stub_client
        error = assert_raises(Zotero::MCP::RateLimitedError) do
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
        error = assert_raises(Zotero::MCP::NotAuthorisedError) do
            client.send(:handle, resp(code: "403", body: "key disabled"))
        end
        assert_match(/Server said: key disabled\z/, error.message)
    end

    def test_handle_omits_suffix_when_body_is_blank
        client = stub_client
        error = assert_raises(Zotero::MCP::NotFoundError) do
            client.send(:handle, resp(code: "404", body: "   "))
        end
        refute_match(/Server said/, error.message)
    end

    def test_handle_truncates_long_response_body
        client = stub_client
        error = assert_raises(Zotero::MCP::APIError) do
            client.send(:handle, resp(code: "500", body: "x" * 600))
        end
        assert_match(/Server said: #{"x" * 500}…\z/, error.message)
    end

    def test_rate_limited_message_includes_body_suffix
        client = stub_client
        error = rate_limited_error(client, { "Retry-After" => "5" },
                                   "slow down")
        assert_match(/Server said: slow down\z/, error.message)
    end

    private

    def rate_limited_error(client, headers, body = "")
        assert_raises(Zotero::MCP::RateLimitedError) do
            client.send(:handle,
                        resp(code: "429", headers: headers, body: body))
        end
    end
end

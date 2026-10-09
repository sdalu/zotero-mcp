# frozen_string_literal: true

require_relative "test_helper"

# 503 handling and the request retry loop: retryable rate-limit errors are
# retried up to MAX_RETRIES times, as long as the backoff stays under the cap.
class RetryTest < Minitest::Test
    # ------------------------------------------------------------------ #
    # 503 retry (C)
    # ------------------------------------------------------------------ #

    def test_service_unavailable_with_retry_after_is_rate_limited
        client = stub_client
        error = assert_raises(Zotero::MCP::RateLimitedError) do
            client.send(:handle,
                        resp(code: "503", headers: { "Retry-After" => "4" }))
        end
        assert_equal 4, error.retry_after
        assert_equal "Service unavailable (503). Retry in 4 seconds.",
                     error.message
    end

    def test_service_unavailable_message_includes_body_suffix
        client = stub_client
        error = unavailable_error(client, "Retry-After" => "4")
        assert_match(/\AService unavailable \(503\)\. Retry in 4 seconds\./,
                     error.message)
        assert_match(/Server said: maintenance\z/, error.message)
    end

    def test_service_unavailable_with_backoff_is_rate_limited
        client = stub_client
        error = assert_raises(Zotero::MCP::RateLimitedError) do
            client.send(:handle,
                        resp(code: "503", headers: { "Backoff" => "9" }))
        end
        assert_equal 9, error.retry_after
    end

    def test_service_unavailable_without_header_is_api_error
        client = stub_client
        assert_raises(Zotero::MCP::APIError) do
            client.send(:handle, resp(code: "503"))
        end
    end

    def test_request_retries_after_503_then_succeeds
        attempts = 0
        client = stub_client do |_req|
            attempts += 1
            next retry_response if attempts == 1

            resp(code: "200", body: { ok: true })
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
            next rate_limited_response if attempts == 1

            resp(code: "200", body: { ok: true })
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
        assert_raises(Zotero::MCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_equal Zotero::MCP::MAX_RETRIES, client.sleeps.length
    end

    def test_request_does_not_retry_without_retry_after
        calls = 0
        client = stub_client do |_req|
            calls += 1
            resp(code: "429")
        end
        assert_raises(Zotero::MCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_equal 1, calls
        assert_empty client.sleeps
    end

    def test_request_does_not_retry_when_backoff_exceeds_cap
        cap = Zotero::MCP::MAX_BACKOFF + 1
        client = stub_client do |_req|
            resp(code: "429", headers: { "Retry-After" => cap.to_s })
        end
        assert_raises(Zotero::MCP::RateLimitedError) do
            client.request(:get, "/users/42/items")
        end
        assert_empty client.sleeps
    end

    private

    def unavailable_error(client, headers)
        assert_raises(Zotero::MCP::RateLimitedError) do
            client.send(:handle,
                        resp(code: "503", headers: headers,
                             body: "maintenance"))
        end
    end

    def retry_response
        resp(code: "503", headers: { "Retry-After" => "1" })
    end

    def rate_limited_response
        resp(code: "429", headers: { "Retry-After" => "1" })
    end
end

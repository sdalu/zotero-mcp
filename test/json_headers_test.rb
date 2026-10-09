# frozen_string_literal: true

require_relative "test_helper"

# JSON body parsing, the default outgoing headers, and the local-API
# write guard.
class JsonHeadersTest < Minitest::Test
    def test_invalid_json_raises_api_error
        client = stub_client { |_req| resp(body: "<html>not json</html>") }
        assert_raises(Zotero::MCP::APIError) { client.item("ABCD1234") }
    end

    def test_writes_blocked_on_local_config
        client = stub_client(build_config(local: true, library_id: nil))
        assert_raises(Zotero::MCP::ReadOnlyError) do
            client.create_items([{ "itemType" => "book" }])
        end
        assert_empty client.requests
    end

    def test_default_headers_carry_api_version_and_key
        headers = stub_client.send(:default_headers)
        assert_equal Zotero::MCP::API_VERSION, headers["Zotero-API-Version"]
        assert_equal "KEY123", headers["Zotero-API-Key"]
    end

    def test_default_headers_omit_key_when_absent
        headers = stub_client(build_config(api_key: nil)).send(:default_headers)
        refute headers.key?("Zotero-API-Key")
    end
end

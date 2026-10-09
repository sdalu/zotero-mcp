# frozen_string_literal: true

require_relative "test_helper"

# Client#prefix and Client#library_id: the id is either taken from config or
# resolved from /keys/current, except for the local (desktop) API.
class LibraryIdTest < Minitest::Test
    def test_prefix_uses_type_and_id
        assert_equal "/users/42", stub_client.prefix
        assert_equal "/groups/99",
                     stub_client(build_config(library_type: "group",
                                              library_id: "99")).prefix
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
        client = stub_client(build_config(library_type: "group",
                                          library_id: nil))
        assert_raises(Zotero::MCP::ConfigurationError) { client.library_id }
    end

    def test_user_without_key_or_id_raises
        client = stub_client(build_config(api_key: nil, library_id: nil))
        assert_raises(Zotero::MCP::ConfigurationError) { client.library_id }
    end

    def test_local_library_id_is_zero
        client = stub_client(build_config(local: true, library_id: nil))
        assert_equal "0", client.library_id
    end
end

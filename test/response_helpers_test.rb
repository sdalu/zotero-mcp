# frozen_string_literal: true

require_relative "test_helper"

# text/error_text build MCP tool responses, and guard turns domain and
# unexpected errors into error-flagged text responses.
class ResponseHelpersTest < Minitest::Test
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
        assert_match(/Unexpected ArgumentError: boom/,
                     text_of(response)["error"])
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
end

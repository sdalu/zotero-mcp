# frozen_string_literal: true

require_relative "test_helper"

# Input-schema enums (E): a few tools declare an explicit `enum` on a
# property, and it must reach the MCP client exactly as written.
class SchemaTest < Minitest::Test
    def test_search_items_schema_declares_enums
        properties = Zotero::MCP::SearchItems.input_schema.to_h[:properties]
        assert_equal %w[titleCreatorYear everything], properties[:qmode][:enum]
        assert_equal %w[asc desc], properties[:direction][:enum]
        assert_equal %w[summary json], properties[:response_format][:enum]
    end

    def test_get_collection_items_schema_declares_response_format_enum
        tool = Zotero::MCP::GetCollectionItems
        properties = tool.input_schema.to_h[:properties]
        assert_equal %w[summary json], properties[:response_format][:enum]
    end

    def test_generate_bibliography_schema_declares_mode_enum
        tool = Zotero::MCP::GenerateBibliography
        properties = tool.input_schema.to_h[:properties]
        assert_equal %w[bibliography citation], properties[:mode][:enum]
    end
end

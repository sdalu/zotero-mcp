# frozen_string_literal: true

module Zotero
    module MCP
        class GetCollectionItems < ::MCP::Tool
            tool_name "zotero_get_collection_items"
            description <<~DESC
                List the items in a specific collection. Same response shape as
                zotero_search_items: a `pagination` block and an `items` list
                (compact summaries by default).
            DESC

            collection_key_desc = "The collection key to list items from."
            top_only_desc = "Only top-level items (default true)."
            item_type_desc = "Filter by item type, e.g. 'book'."
            tag_desc = "Filter by tag (boolean syntax allowed)."
            start_desc = "Offset for pagination (default 0)."
            response_format_desc = "'summary' (default) or 'json'."

            input_schema(
                properties: {
                    collection_key: { type: "string",
                                      description: collection_key_desc },
                    top_only: { type: "boolean", description: top_only_desc },
                    item_type: { type: "string", description: item_type_desc },
                    tag: { type: "string", description: tag_desc },
                    limit: { type: "integer",
                             description: "Max items, 1-100 (default 25)." },
                    start: { type: "integer", description: start_desc },
                    response_format: { type: "string",
                                       enum: %w[summary json],
                                       description: response_format_desc }
                },
                required: ["collection_key"]
            )
            annotations(title: "Get items in a collection",
                        read_only_hint: true, destructive_hint: false,
                        idempotent_hint: true, open_world_hint: true)

            def self.call(collection_key:, top_only: true, item_type: nil, # rubocop:disable Metrics/ParameterLists -- mirrors the input_schema
                          tag: nil, limit: DEFAULT_LIMIT, start: 0,
                          response_format: "summary")
                Zotero::MCP.guard do
                    page = Zotero::MCP.client.collection_items(
                        key: collection_key, top_only: top_only,
                        item_type: item_type, tag: tag, limit: limit,
                        start: start
                    )
                    Zotero::MCP.text(Zotero::MCP.format_page(page,
                                                             response_format))
                end
            end
        end
    end
end

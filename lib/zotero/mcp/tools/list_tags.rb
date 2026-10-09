# frozen_string_literal: true

module Zotero
    module MCP
        class ListTags < ::MCP::Tool
            tool_name "zotero_list_tags"
            description <<~DESC
                List tags used in the library, optionally filtered by text. Returns
                a `pagination` block and a `tags` list of tag objects.
            DESC
            filter_text_desc = "Only tags matching this text."

            input_schema(
                properties: {
                    filter_text: { type: "string",
                                   description: filter_text_desc },
                    limit: { type: "integer",
                             description: "Max tags, 1-100 (default 25)." },
                    start: { type: "integer",
                             description: "Offset for pagination (default 0)." }
                },
                required: []
            )
            annotations(title: "List Zotero tags", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(filter_text: nil, limit: DEFAULT_LIMIT, start: 0)
                Zotero::MCP.guard do
                    page = Zotero::MCP.client.tags(
                        query: filter_text, limit: limit, start: start
                    )
                    Zotero::MCP.text(
                        pagination: Zotero::MCP.pagination_of(page),
                        tags: page.items
                    )
                end
            end
        end
    end
end

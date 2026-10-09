# frozen_string_literal: true

module Zotero
    module MCP
        class ListCollections < ::MCP::Tool
            tool_name "zotero_list_collections"
            description <<~DESC
                List collections (folders) in the library. Returns a `pagination`
                block plus a `collections` list, each with key, name,
                parentCollection, numItems and numCollections.
            DESC

            top_only_desc = "Only top-level collections (default false)."

            input_schema(
                properties: {
                    top_only: { type: "boolean", description: top_only_desc },
                    limit: { type: "integer",
                             description: "Max results, 1-100 (default 25)." },
                    start: { type: "integer",
                             description: "Offset for pagination (default 0)." }
                },
                required: []
            )
            annotations(title: "List Zotero collections", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(top_only: false, limit: DEFAULT_LIMIT, start: 0)
                Zotero::MCP.guard do
                    page = Zotero::MCP.client.collections(
                        top_only: top_only, limit: limit, start: start
                    )
                    Zotero::MCP.text(collections_payload(page))
                end
            end

            def self.collections_payload(page)
                {
                    pagination: Zotero::MCP.pagination_of(page),
                    collections: page.items.map { |col| collection_of(col) }
                }
            end

            def self.collection_of(col)
                data = col["data"] || {}
                meta = col["meta"] || {}
                {
                    key: col["key"], name: data["name"],
                    parentCollection: data["parentCollection"],
                    numItems: meta["numItems"],
                    numCollections: meta["numCollections"]
                }.compact
            end
        end
    end
end

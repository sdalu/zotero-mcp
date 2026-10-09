# frozen_string_literal: true

module Zotero
    module MCP
        class SearchItems < ::MCP::Tool
            tool_name "zotero_search_items"
            description <<~DESC
                Search or browse items in the Zotero library. Returns a JSON
                object with a `pagination` block (count, start, total, has_more,
                next_start) and an `items` list. In 'summary' format each item has
                key, itemType, title, creators, date, publication, tags and
                numChildren; use zotero_get_item with the key for the full record.
            DESC

            query_desc = "Free-text search; omit to browse all."
            qmode_desc = "'titleCreatorYear' (default) or 'everything' " \
                         "(also searches attachment full text)."
            item_type_desc = "Filter by type, e.g. 'journalArticle', 'book'. " \
                             "Boolean syntax like '-attachment' works."
            tag_desc = "Filter by tag; boolean 'a && b' / 'a || b'."
            top_only_desc = "Only top-level items (default true)."
            sort_desc = "Sort field, e.g. 'dateModified', 'title'."
            limit_desc = "Max items, 1-100 (default 25)."
            start_desc = "Offset for pagination (default 0)."
            response_format_desc = "'summary' (default) or 'json' for raw " \
                                   "data."

            input_schema(
                properties: {
                    query: { type: "string", description: query_desc },
                    qmode: { type: "string",
                             enum: %w[titleCreatorYear everything],
                             description: qmode_desc },
                    item_type: { type: "string", description: item_type_desc },
                    tag: { type: "string", description: tag_desc },
                    top_only: { type: "boolean", description: top_only_desc },
                    sort: { type: "string", description: sort_desc },
                    direction: { type: "string", enum: %w[asc desc],
                                 description: "'asc' or 'desc'." },
                    limit: { type: "integer", description: limit_desc },
                    start: { type: "integer", description: start_desc },
                    response_format: { type: "string",
                                       enum: %w[summary json],
                                       description: response_format_desc }
                },
                required: []
            )
            annotations(title: "Search Zotero items", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(query: nil, qmode: "titleCreatorYear", # rubocop:disable Metrics/ParameterLists -- mirrors the input_schema
                          item_type: nil, tag: nil, top_only: true, sort: nil,
                          direction: nil, limit: DEFAULT_LIMIT, start: 0,
                          response_format: "summary")
                Zotero::MCP.guard do
                    page = Zotero::MCP.client.search_items(
                        query: query, qmode: qmode, item_type: item_type,
                        tag: tag, top_only: top_only, sort: sort,
                        direction: direction, limit: limit, start: start
                    )
                    Zotero::MCP.text(Zotero::MCP.format_page(page,
                                                             response_format))
                end
            end
        end
    end
end

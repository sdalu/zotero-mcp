# frozen_string_literal: true

module Zotero
    module MCP
        class GetItemFulltext < ::MCP::Tool
            tool_name "zotero_get_item_fulltext"
            description <<~DESC
                Return the indexed full-text content of an attachment item (e.g. a
                stored PDF). Either the attachment's own key or its parent item's
                key is accepted; given a parent key, the attachment (PDFs first)
                is resolved automatically. The content is paged: use offset and
                max_chars, and next_offset in the result, to read more.
            DESC

            item_key_desc = "Key of an attachment with indexed text, or of " \
                            "its parent item."
            max_chars_desc = "Max characters to return, 1-200000 " \
                             "(default 20000)."

            input_schema(
                properties: {
                    item_key: { type: "string", description: item_key_desc },
                    offset: { type: "integer",
                              description: "Character offset to start from " \
                                           "(default 0)." },
                    max_chars: { type: "integer",
                                 description: max_chars_desc }
                },
                required: ["item_key"]
            )
            annotations(title: "Get item full text", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(item_key:, offset: 0,
                          max_chars: Zotero::MCP::DEFAULT_MAX_CHARS)
                Zotero::MCP.guard do
                    resolved = Zotero::MCP.fulltext_with_fallback(
                        Zotero::MCP.client, item_key
                    )
                    Zotero::MCP.text(
                        Zotero::MCP.paginate_fulltext(resolved, offset,
                                                      max_chars)
                    )
                end
            end
        end
    end
end

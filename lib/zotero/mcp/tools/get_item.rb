# frozen_string_literal: true

module Zotero
    module MCP
        class GetItem < ::MCP::Tool
            tool_name "zotero_get_item"
            description <<~DESC
                Fetch the full data for a single item by its key. Returns the
                complete item JSON. When include_children is true, an additional
                `children` array with the item's notes and attachments is added.
                Children in the trash are left out, although the item's
                meta.numChildren counts them.
            DESC

            item_key_desc = "The 8-character item key, e.g. 'ABCD2345'."
            include_children_desc = "Also fetch child notes/attachments."

            input_schema(
                properties: {
                    item_key: { type: "string", description: item_key_desc },
                    include_children: { type: "boolean",
                                        description: include_children_desc }
                },
                required: ["item_key"]
            )
            annotations(title: "Get a Zotero item", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(item_key:, include_children: false)
                Zotero::MCP.guard do
                    client = Zotero::MCP.client
                    result = { item: client.item(item_key) }
                    if include_children
                        result[:children] = client.children(item_key)
                    end
                    Zotero::MCP.text(result)
                end
            end
        end
    end
end

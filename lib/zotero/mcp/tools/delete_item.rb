# frozen_string_literal: true

module Zotero
    module MCP
        class DeleteItem < ::MCP::Tool
            tool_name "zotero_delete_item"
            description <<~DESC
                Delete one or more items (moves them to the Zotero trash, so
                deletions are recoverable). Up to 50 keys per call. Returns the
                deleted keys and any that could not be deleted.
            DESC
            input_schema(
                properties: {
                    item_keys: { type: "array", items: { type: "string" },
                                 description: "Item keys to delete (max 50)." }
                },
                required: ["item_keys"]
            )
            annotations(title: "Delete Zotero items", read_only_hint: false,
                        destructive_hint: true, idempotent_hint: false,
                        open_world_hint: true)

            def self.call(item_keys:)
                Zotero::MCP.guard do
                    error = Zotero::MCP.batch_error(item_keys)
                    next Zotero::MCP.error_text(error) if error

                    Zotero::MCP.text(Zotero::MCP.client.delete_items(item_keys))
                end
            end
        end
    end
end

# frozen_string_literal: true

module Zotero
    module MCP
        class AddToCollection < ::MCP::Tool
            tool_name "zotero_add_to_collection"
            description <<~DESC
                Add existing items to a collection, leaving other memberships
                intact. Returns which keys were added and any failures.
            DESC
            input_schema(
                properties: {
                    collection_key: { type: "string",
                                      description: "Target collection key." },
                    item_keys: { type: "array", items: { type: "string" },
                                 description: "Keys of items to add." }
                },
                required: %w[collection_key item_keys]
            )
            annotations(title: "Add items to a collection",
                        read_only_hint: false, destructive_hint: false,
                        idempotent_hint: true, open_world_hint: true)

            def self.call(collection_key:, item_keys:)
                Zotero::MCP.guard do
                    error = Zotero::MCP.batch_error(item_keys)
                    next Zotero::MCP.error_text(error) if error

                    Zotero::MCP.text(
                        Zotero::MCP.client.add_to_collection(
                            collection_key: collection_key, keys: item_keys
                        )
                    )
                end
            end
        end
    end
end

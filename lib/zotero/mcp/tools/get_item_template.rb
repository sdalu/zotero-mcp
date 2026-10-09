# frozen_string_literal: true

module Zotero
    module MCP
        class GetItemTemplate < ::MCP::Tool
            tool_name "zotero_get_item_template"
            description <<~DESC
                Get a blank item template, or list all valid item types. With no
                item_type, returns the list of item types. With an item_type,
                returns a blank editable template plus valid creator types — use
                this before zotero_create_item.
            DESC

            item_type_desc = "Type to template, e.g. 'journalArticle'. " \
                             "Omit to list all item types."

            input_schema(
                properties: {
                    item_type: { type: "string", description: item_type_desc }
                },
                required: []
            )
            annotations(title: "Get item type template", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(item_type: nil)
                Zotero::MCP.guard do
                    client = Zotero::MCP.client
                    next Zotero::MCP.text(itemTypes: client.item_types) unless
                        item_type

                    Zotero::MCP.text(item_template_payload(client, item_type))
                end
            end

            def self.item_template_payload(client, item_type)
                {
                    itemType: item_type,
                    template: client.item_template(item_type),
                    creatorTypes: client.creator_types(item_type)
                }
            end
        end
    end
end

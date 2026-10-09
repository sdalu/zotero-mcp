# frozen_string_literal: true

module Zotero
    module MCP
        class CreateNote < ::MCP::Tool
            tool_name "zotero_create_note"
            description <<~DESC
                Create a standalone or child note. If parent_item_key is set, the
                note is created as a child of that item. Returns the new note key.
            DESC

            note_html_desc = "Note content as HTML (plain text is fine)."
            parent_item_key_desc = "Make the note a child of this item."
            collection_keys_desc = "Collections for a standalone note."

            input_schema(
                properties: {
                    note_html: { type: "string",
                                 description: note_html_desc },
                    parent_item_key: { type: "string",
                                       description: parent_item_key_desc },
                    tags: { type: "array", items: { type: "string" },
                            description: "Tag strings for the note." },
                    collection_keys: { type: "array",
                                       items: { type: "string" },
                                       description: collection_keys_desc }
                },
                required: ["note_html"]
            )
            annotations(title: "Create a Zotero note", read_only_hint: false,
                        destructive_hint: false, idempotent_hint: false,
                        open_world_hint: true)

            def self.call(note_html:, parent_item_key: nil, tags: nil,
                          collection_keys: nil)
                Zotero::MCP.guard do
                    error = note_conflict_error(parent_item_key,
                                                collection_keys)
                    next Zotero::MCP.error_text(error) if error

                    client = Zotero::MCP.client
                    note = build_note(client, note_html, parent_item_key,
                                      tags, collection_keys)
                    Zotero::MCP.text(client.create_items([note]))
                end
            end

            def self.note_conflict_error(parent_item_key, collection_keys)
                return nil unless parent_item_key &&
                                  Array(collection_keys).any?

                "collection_keys apply only to standalone notes; omit " \
                    "parent_item_key or collection_keys."
            end

            def self.build_note(client, note_html, parent_item_key, tags,
                                collection_keys)
                note = client.item_template("note")
                note["note"] = note_html
                note["tags"] = tags.map { |tag| { "tag" => tag } } if tags
                note["parentItem"] = parent_item_key if parent_item_key
                if collection_keys && parent_item_key.nil?
                    note["collections"] = collection_keys
                end
                note
            end
        end
    end
end

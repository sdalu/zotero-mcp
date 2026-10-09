# frozen_string_literal: true

module Zotero
    module MCP
        # ----------------------------------------------------------------- #
        # Module-level glue: client, formatting, tool responses
        # ----------------------------------------------------------------- #

        def self.client = @client ||= Client.new(Config.from_env)

        def self.text(object)
            ::MCP::Tool::Response.new(
                [{ type: "text", text: JSON.pretty_generate(object) }]
            )
        end

        def self.error_text(message)
            ::MCP::Tool::Response.new(
                [{ type: "text", text: JSON.pretty_generate(error: message) }],
                error: true
            )
        end

        def self.guard
            yield
        rescue Error => e
            error_text(e.message)
        rescue StandardError => e
            error_text("Unexpected #{e.class}: #{e.message}")
        end

        def self.format_page(page, response_format)
            items = if response_format == "json"
                        page.items
                    else
                        page.items.map { |item| summarize(item) }
                    end
            { pagination: pagination_of(page), items: items }
        end

        def self.pagination_of(page)
            {
                count: page.items.length, start: page.start, total: page.total,
                has_more: page.more?, next_start: page.next_start
            }.compact
        end

        def self.summarize(item)
            data = item["data"] || {}
            meta = item["meta"] || {}
            summary_core(item, data, meta).merge(
                summary_extra(data, meta)
            ).compact
        end

        def self.summary_core(item, data, meta)
            {
                key: item["key"], version: item["version"],
                itemType: data["itemType"], title: title_of(data),
                creators: creators_of(data, meta),
                date: data["date"] || meta["parsedDate"]
            }
        end

        def self.summary_extra(data, meta)
            {
                publication: publication_of(data), DOI: data["DOI"],
                url: data["url"], tags: tags_of(data),
                collections: nonempty(data["collections"]),
                numChildren: meta["numChildren"]
            }
        end

        def self.title_of(data)
            data["title"] || data["caseName"] || data["subject"]
        end

        def self.publication_of(data)
            data["publicationTitle"] || data["bookTitle"] ||
                data["proceedingsTitle"] || data["publisher"]
        end

        def self.tags_of(data)
            names = (data["tags"] || []).map { |tag| tag["tag"] }
            nonempty(names)
        end

        def self.creators_of(data, meta)
            names = (data["creators"] || [])
                    .map { |creator| creator_name(creator) }
                    .reject(&:empty?)
            return meta["creatorSummary"] if names.empty?

            summarize_names(names)
        end

        def self.creator_name(creator)
            creator["name"] ||
                [creator["firstName"], creator["lastName"]].compact.join(" ")
        end

        def self.summarize_names(names)
            return names.join(", ") if names.length <= 3

            "#{names.first(3).join(", ")} (+#{names.length - 3} more)"
        end
    end
end

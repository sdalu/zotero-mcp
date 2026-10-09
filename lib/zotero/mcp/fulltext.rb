# frozen_string_literal: true

module Zotero
    module MCP
        DEFAULT_MAX_CHARS = 20_000
        MAX_MAX_CHARS = 200_000

        def self.clamp_max_chars(max_chars)
            unless max_chars.is_a?(Integer) && max_chars >= 1
                return DEFAULT_MAX_CHARS
            end

            max_chars.clamp(1, MAX_MAX_CHARS)
        end

        # Full text lives on the attachment, not its parent, but callers often
        # only have the parent's key. Falling back to the children (PDFs first)
        # means either key works for zotero_get_item_fulltext.
        def self.fulltext_with_fallback(client, item_key)
            { body: client.fulltext(item_key), item_key: item_key }
        # rubocop:disable Naming/RescuedExceptionsVariableName -- names the error re-raised below
        rescue NotFoundError => original
            # rubocop:enable Naming/RescuedExceptionsVariableName
            begin
                kids = client.children(item_key)
            rescue NotFoundError, APIError
                # Not a parent item (Zotero refuses /children on an
                # attachment or a note): the original 404 is the answer.
                raise original
            end
            fulltext_from_children(client, item_key, kids) ||
                (raise NotFoundError,
                       "No indexed full text for this item or its attachments.")
        end

        def self.fulltext_from_children(client, parent_key, children)
            candidate_attachments(children).each do |child|
                key = child["key"]
                begin
                    return { body: client.fulltext(key), item_key: key,
                             parent_key: parent_key }
                rescue NotFoundError
                    next
                end
            end
            nil
        end

        def self.candidate_attachments(children)
            attachments = children.select do |child|
                child.dig("data", "itemType") == "attachment"
            end
            pdfs, others = attachments.partition do |child|
                child.dig("data", "contentType") == "application/pdf"
            end
            pdfs + others
        end

        def self.paginate_fulltext(resolved, offset, max_chars)
            content = resolved[:body]["content"].to_s
            start = clamp_start(offset)
            slice = content[start, clamp_max_chars(max_chars)] || ""
            result = fulltext_slice_result(resolved, content, start, slice)
            copy_fulltext_meta(result, resolved[:body])
        end

        def self.fulltext_slice_result(resolved, content, start, slice)
            result = {
                item_key: resolved[:item_key], content: slice, offset: start,
                returned_chars: slice.length, total_chars: content.length
            }
            result[:parent_key] = resolved[:parent_key] if resolved[:parent_key]
            next_offset = start + slice.length
            result[:next_offset] = next_offset if next_offset < content.length
            result
        end

        def self.copy_fulltext_meta(result, body)
            %w[indexedPages totalPages indexedChars totalChars].each do |field|
                result[field.to_sym] = body[field] if body.key?(field)
            end
            result
        end
    end
end

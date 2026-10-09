# frozen_string_literal: true

module Zotero
    module MCP
        # HTTP status-code interpretation for Client: dispatches a response to
        # the matching domain error (or the retryable rate-limit path) and
        # builds the error message text. Included into Client.
        module ResponseHandling
            private

            def handle(response)
                status = response.code.to_i
                return response if (200..299).cover?(status)

                raise_for_status(status, response)
            end

            def raise_for_status(status, response)
                case status
                in 403 then raise NotAuthorisedError, forbidden_text(response)
                in 404 then raise NotFoundError, not_found_text(response)
                in 412 then raise ConflictError, conflict_text(response)
                in 429 then raise_rate_limited(response)
                in 503 then raise_service_unavailable(response)
                else raise APIError, api_error_text(status, response)
                end
            end

            def forbidden_text(response)
                "#{forbidden_message}#{body_suffix(response)}"
            end

            def not_found_text(response)
                "Not found (404). Check the key.#{body_suffix(response)}"
            end

            def conflict_text(response)
                "#{conflict_message}#{body_suffix(response)}"
            end

            def api_error_text(status, response)
                "Zotero API error #{status}.#{body_suffix(response)}"
            end

            def raise_rate_limited(response)
                header = response["Retry-After"] || response["Backoff"]
                seconds = Zotero::MCP.presence(header)&.to_i
                raise RateLimitedError.new(
                    "Rate limited (429). Retry in #{seconds || "a few"} " \
                    "seconds.#{body_suffix(response)}",
                    retry_after: seconds
                )
            end

            def raise_service_unavailable(response)
                header = retry_header(response)
                return unavailable_without_retry(response) unless header

                raise RateLimitedError.new(service_unavailable_text(header,
                                                                    response),
                                           retry_after: header.to_i)
            end

            def retry_header(response)
                Zotero::MCP.presence(
                    response["Retry-After"] || response["Backoff"]
                )
            end

            def unavailable_without_retry(response)
                raise APIError, "Zotero API error 503.#{body_suffix(response)}"
            end

            def service_unavailable_text(header, response)
                "Service unavailable (503). Retry in #{header.to_i} " \
                    "seconds.#{body_suffix(response)}"
            end

            def forbidden_message
                "Permission denied (403). The API key is missing, invalid, " \
                    "or lacks the access needed (write keys need write " \
                    "permission)."
            end

            def conflict_message
                "Version conflict (412). The object changed on the server; " \
                    "re-fetch it and retry."
            end

            # Non-2xx responses often carry a plain-text explanation;
            # surfacing it (bounded, so a huge body can't blow up an error
            # message) helps diagnose failures that the generic status
            # message cannot.
            def body_suffix(response)
                body = Zotero::MCP.presence(response.body)
                return "" unless body

                snippet = body.length > 500 ? "#{body[0, 500]}…" : body
                " Server said: #{snippet}"
            end
        end
    end
end

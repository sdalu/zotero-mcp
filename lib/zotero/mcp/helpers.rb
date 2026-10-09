# frozen_string_literal: true

module Zotero
    module MCP
        # ----------------------------------------------------------------- #
        # Small helpers
        # ----------------------------------------------------------------- #

        def self.truthy?(value)
            %w[1 true yes on].include?(value.to_s.downcase)
        end

        def self.presence(value)
            stripped = value.to_s.strip
            stripped.empty? ? nil : stripped
        end

        def self.clamp_limit(limit)
            return DEFAULT_LIMIT unless limit.is_a?(Integer) && limit.positive?

            [limit, MAX_LIMIT].min
        end

        def self.clamp_start(start)
            start.is_a?(Integer) && start.positive? ? start : 0
        end

        # Zotero keys are short alphanumeric strings. Rejecting anything else
        # keeps bad input out of URL paths and fails with a clear message.
        def self.validate_key!(key)
            return key if KEY_PATTERN.match?(key.to_s)

            raise Error, "Invalid Zotero key: #{key.inspect}."
        end

        def self.compact(hash)
            hash.reject { |_key, value| value.nil? || value == "" }
        end

        def self.batch_error(keys)
            return "Provide at least one item key." if keys.empty?
            return nil if keys.length <= MAX_WRITE_BATCH

            "At most #{MAX_WRITE_BATCH} items per call."
        end

        def self.nonempty(value) = value.nil? || value.empty? ? nil : value
    end
end

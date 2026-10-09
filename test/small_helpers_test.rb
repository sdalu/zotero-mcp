# frozen_string_literal: true

require_relative "test_helper"

# The small module-level helpers: truthy?, presence, clamp_limit,
# clamp_start, validate_key!, compact, batch_error, nonempty, clamp_max_chars.
class SmallHelpersTest < Minitest::Test
    def test_truthy_accepts_common_true_words_case_insensitively
        %w[1 true TRUE yes Yes on ON].each do |value|
            assert Zotero::MCP.truthy?(value), value.inspect
        end
    end

    def test_truthy_rejects_everything_else
        [nil, "", "0", "false", "no", "off", "maybe", 2].each do |value|
            refute Zotero::MCP.truthy?(value), value.inspect
        end
    end

    def test_presence_strips_and_nils_blanks
        assert_equal "abc", Zotero::MCP.presence("  abc  ")
        assert_nil Zotero::MCP.presence("   ")
        assert_nil Zotero::MCP.presence(nil)
    end

    def test_clamp_limit_defaults_and_caps
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(nil)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(0)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit(-5)
        assert_equal Zotero::MCP::DEFAULT_LIMIT, Zotero::MCP.clamp_limit("10")
        assert_equal 10, Zotero::MCP.clamp_limit(10)
        assert_equal Zotero::MCP::MAX_LIMIT, Zotero::MCP.clamp_limit(1000)
    end

    def test_clamp_start_keeps_positive_ints_else_zero
        assert_equal 7, Zotero::MCP.clamp_start(7)
        assert_equal 0, Zotero::MCP.clamp_start(0)
        assert_equal 0, Zotero::MCP.clamp_start(-3)
        assert_equal 0, Zotero::MCP.clamp_start("4")
        assert_equal 0, Zotero::MCP.clamp_start(nil)
    end

    def test_validate_key_accepts_alphanumeric
        assert_equal "ABCD2345", Zotero::MCP.validate_key!("ABCD2345")
        assert_equal "a1", Zotero::MCP.validate_key!("a1")
    end

    def test_validate_key_rejects_bad_input
        ["", "AB CD", "abc/def", "a" * 33, nil, "a-b"].each do |bad|
            assert_raises(Zotero::MCP::Error) { Zotero::MCP.validate_key!(bad) }
        end
    end

    def test_compact_drops_nil_and_empty_string_only
        result = Zotero::MCP.compact(a: 1, b: nil, c: "", d: false, e: 0)
        assert_equal({ a: 1, d: false, e: 0 }, result)
    end

    def test_batch_error_messages
        max = Zotero::MCP::MAX_WRITE_BATCH
        assert_match(/at least one/i, Zotero::MCP.batch_error([]))
        assert_nil Zotero::MCP.batch_error(%w[A B])
        assert_nil Zotero::MCP.batch_error(Array.new(max, "K"))
        assert_match(/at most/i, Zotero::MCP.batch_error(Array.new(max + 1,
                                                                   "K")))
    end

    def test_nonempty
        assert_nil Zotero::MCP.nonempty(nil)
        assert_nil Zotero::MCP.nonempty([])
        assert_equal [1], Zotero::MCP.nonempty([1])
    end

    # ------------------------------------------------------------------ #
    # clamp_max_chars (G)
    # ------------------------------------------------------------------ #

    def test_clamp_max_chars_defaults_and_caps
        default = Zotero::MCP::DEFAULT_MAX_CHARS
        [nil, 0, -5, "100"].each do |input|
            assert_equal default, Zotero::MCP.clamp_max_chars(input)
        end
        assert_equal 500, Zotero::MCP.clamp_max_chars(500)
        assert_equal Zotero::MCP::MAX_MAX_CHARS,
                     Zotero::MCP.clamp_max_chars(1_000_000)
    end
end

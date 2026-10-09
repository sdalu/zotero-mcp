# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies (the mcp gem) are declared in zotero-mcp.gemspec.
gemspec

group :development, :test do
    gem "minitest", "~> 6.0"
    gem "rake", "~> 13.0"
    # Patch releases only: a minor release adds cops, and .rubocop.yml
    # enables new cops, so an unpinned upgrade could fail CI on its own.
    gem "rubocop", "~> 1.91.0"
end

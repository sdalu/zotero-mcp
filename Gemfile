# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies (the mcp gem) are declared in zotero-mcp.gemspec.
gemspec

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.0"
    # Patch releases only: a minor release adds cops, and .rubocop.yml
    # enables new cops, so an unpinned upgrade could fail CI on its own.
    gem "rubocop", "~> 1.90.0"
    # rubocop's parallel dependency: 2.x needs Ruby 3.3, and CI also
    # runs on 3.2, the gemspec's floor.
    gem "parallel", "~> 1.28"
end

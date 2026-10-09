# frozen_string_literal: true

# Load every test file so a single `ruby test/all.rb` runs the whole suite.
# minitest/autorun (pulled in by test_helper) executes them at exit.
Dir[File.join(__dir__, "*_test.rb")].each { |file| require file }

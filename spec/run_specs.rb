require "bundler/setup"
require "rspec"
require "./spec/spec_helper"

exit RSpec::Core::Runner.run(%w[./spec], $stderr, $stdout)

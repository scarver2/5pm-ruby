require "simplecov"
SimpleCov.start do
  skip "/spec/"
  minimum_coverage 90
end
require "five_pm"

module Commandant::Bench
  # Base class for errors raised by the bench API.
  class Error < Exception
  end

  # Raised when a ruleset or rule reference does not resolve to anything.
  class NotFoundError < Error
  end
end

# = Regular Expression Construction.
#
# Construct regular expressions using the re() method.
#
# Usage:
#
#   include Re
#
#   number = re.any("0-9").all
#   if number =~ string
#     puts "Matches!"
#   else
#     puts "No Match"
#   end
#
# Examples:
#
#   re("a")                -- matches "a"
#   re("a") + re("b")      -- matches "ab"
#   re("a") | re("b")      -- matches "a" or "b"
#   re("a").many           -- matches "", "a", "aaaaaa"
#   re("a").one_or_more    -- matches "a", "aaaaaa", but not ""
#   re("a").optional       -- matches "" or "a"
#   re("a").all            -- matches "a", but not "xab"
#
# See Re::Rexp for a complete list of expressions.
#
# Using re without an argument allows access to a number of common
# regular expression constants.  For example:
#
#   re.space              -- matches " ", "\n" or "\t"
#   re.spaces             -- matches any number of spaces (but at least one)
#   re.digit / re.digits  -- matches a digit / sequence of digits
#
# See Re::NULL for a complete list of common constants.
#
# See Re.re,
# Re::Rexp, and Re::NULL for details.

module Re
  class Result
    def initialize(match_data, rexp)
      @match_data = match_data
      @rexp = rexp
    end
    def data(name=nil)
      if name
        index = @rexp.capture_keys.index(name)
        index ? @match_data[index+1] : nil
      else
        @match_data[0]
      end
    end
  end
  
  # Precedence levels for regular expressions:

  GROUPED = 4                   # (r), [chars]      :nodoc:
  POSTFIX = 3                   # r*, r+, r?        :nodoc:
  CONCAT  = 2                   # r + r, literal    :nodoc:
  ALT     = 1                   # r | r             :nodoc:


  # Constructed regular expressions.
  class Rexp
    attr_reader :string, :level, :flags, :capture_keys

    # Create a regular expression from the string.  The regular
    # expression will have a precedence of +level+ and will recognized
    # +keys+ as a list of capture keys.
    def initialize(string, level, flags, keys)
      @string = string
      @level = level
      @flags = flags
      @capture_keys = keys
    end

    # Return a real regular expression from the the constructed
    # regular expression.
    def regexp
      @regexp ||= Regexp.new(string, flags)
    end

    # Does it match a string? (returns Re::Result if match, nil otherwise)
    def match(string)
      md = regexp.match(string)
      md ? Result.new(md, self) : nil
    end
    alias =~ match
    
    # Concatenate two regular expressions
    def +(other)
      Rexp.new(parenthesize(CONCAT) + other.parenthesize(CONCAT),
        CONCAT,
        flags | other.flags,
        capture_keys + other.capture_keys)
    end

    # Matches either self or other
    def |(other)
      Rexp.new(parenthesize(ALT) + "|" + other.parenthesize(ALT),
        ALT,
        flags | other.flags,
        capture_keys + other.capture_keys)
    end

    # self is optional
    def optional
      Rexp.new(parenthesize(POSTFIX) + "?", POSTFIX, flags, capture_keys)
    end

    # self matches many times (zero or more)
    def many
      Rexp.new(parenthesize(POSTFIX) + "*", POSTFIX, flags, capture_keys)
    end

    # self matches one or more times
    def one_or_more
      Rexp.new(parenthesize(POSTFIX) + "+", POSTFIX, flags, capture_keys)
    end

    # self is repeated from min to max times.  If max is omitted, then
    # it is repeated exactly min times.
    def repeat(min, max=nil)
      if min && max
        Rexp.new(parenthesize(POSTFIX) + "{#{min},#{max}}", POSTFIX, flags, capture_keys)
      else
        Rexp.new(parenthesize(POSTFIX) + "{#{min}}", POSTFIX, flags, capture_keys)
      end
    end

    # self is repeated at least min times
    def at_least(min)
      Rexp.new(parenthesize(POSTFIX) + "{#{min},}", POSTFIX, flags, capture_keys)
    end

    # self is repeated at least max times
    def at_most(max)
      Rexp.new(parenthesize(POSTFIX) + "{0,#{max}}", POSTFIX, flags, capture_keys)
    end

    # None of the given characters will match.
    def none(chars)
      Rexp.new("[^" + Rexp.escape_any(chars) + "]", GROUPED, 0, [])
    end

    # self must match all of the string
    def all
      self.begin.very_end
    end

    # self must match almost all of the string (trailing new lines are allowed)
    def almost_all
      self.begin.end
    end

    # self must match at the beginning of a line
    def bol
      Rexp.new("^" + parenthesize(CONCAT), CONCAT, flags, capture_keys)
    end

    # self must match at the end of a line
    def eol
      Rexp.new(parenthesize(CONCAT) + "$", CONCAT, flags, capture_keys)
    end

    # self must match at the beginning of the string
    def begin
      Rexp.new("\\A" + parenthesize(CONCAT), CONCAT, flags, capture_keys)
    end

    # self must match the end of the string (with an optional new line)
    def end
      Rexp.new(parenthesize(CONCAT) + "\\Z", CONCAT, flags, capture_keys)
    end

    # self must match the very end of the string (including any new lines)
    def very_end
      Rexp.new(parenthesize(CONCAT) + "\\z", CONCAT, flags, capture_keys)
    end

    # self must match an entire line.
    def line
      self.bol.eol
    end

    # self is contained in a non-capturing group
    def group
      Rexp.new("(?:" + string + ")", GROUPED, flags, capture_keys)
    end

    # self is a capturing group with the given name.
    def capture(name)
      Rexp.new("(" + string + ")", GROUPED, flags, [name] + capture_keys)
    end
    
    # self will work in multiline matches
    def multiline
      Rexp.new(string, GROUPED, flags|Regexp::MULTILINE, capture_keys)
    end
    
    # Is this a multiline regular expression?
    def multiline?
      (flags & Regexp::MULTILINE) != 0
    end

    # self will work in multiline matches
    def ignore_case
      Rexp.new(string, GROUPED, flags|Regexp::IGNORECASE, capture_keys)
    end

    # Does this regular expression ignore case?
    def ignore_case?
      (flags & Regexp::IGNORECASE) != 0
    end

    # String representation of the constructed regular expression.
    def to_s
      regexp.to_s
    end
    
    protected

    # String representation with grouping if needed.
    #
    # If the precedence of the current Regexp is less than the new
    # precedence level, return the string wrapped in a non-capturing
    # group.  Otherwise just return the string.
    def parenthesize(new_level)
      if level >= new_level
        string
      else
        group.string
      end
    end
    
    # Create a literal regular expression (concatenation level
    # precedence, no capture keywords).
    def self.literal(chars)
      new(Regexp.escape(chars), CONCAT, 0, [])
    end

    # Create a regular expression from a raw string representing a
    # regular expression.  The raw string should represent a regular
    # expression with the highest level of precedence (you should use
    # parenthesis if it is not).
    def self.raw(re_string)     # :no-doc:
      new(re_string, GROUPED, 0, [])
    end

    # Escape any special characters.
    def self.escape_any(chars)
      chars.gsub(/([\[\]\^\-])/) { "\\#{$1}" }
    end
  end

  
  # Construct a regular expression from the literal string.  Special
  # Regexp characters will be escaped before constructing the regular
  # expression.  If no literal is given, then the NULL regular
  # expression is returned.
  #
  # See Re for example usage.
  #
  def re(exp=nil)
    exp ? Rexp.literal(exp) : NULL
  end
  
  # Matches an empty string.  Additional common regular expression
  # constants are defined as methods on the NULL Rexp.  See Re::NULL.
  NULL = Rexp.literal("")

  # Matches the null string
  def NULL.null
    self
  end

  # :call-seq:
  #   re.any
  #   re.any(chars)
  #   re.any(range)
  #   re.any(chars, range, ...)
  #
  # Match a character from the character class.
  #
  # Any without any arguments will match any single character.  Any
  # with one or more arguments will construct a character class for
  # the arguments.  If the argument is a three character string where
  # the middle character is "-", then the argument represents a range
  # of characters.  Otherwise the arguments are treated as a list of
  # characters to be added to the character class.
  #
  # Examples:
  #
  #   re.any                            -- match any character
  #   re.any("aieouy")                  -- match vowels
  #   re.any("0-9")                     -- match digits
  #   re.any("A-Z", "a-z", "0-9")       -- match alphanumerics
  #   re.any("A-Z", "a-z", "0-9", "_")  -- match alphanumerics
  #
  def NULL.any(*chars)
    if chars.empty?
      @dot ||= Rexp.raw(".")
    else
      any_chars = ''
      chars.each do |chs|
        if /^.-.$/ =~ chs
          any_chars << chs
        else
          any_chars << Rexp.escape_any(chs)
        end
      end
      Rexp.new("[" + any_chars  + "]", GROUPED, 0, [])
    end
  end
  
  # Matches any white space
  def NULL.space
    @space ||= Rexp.raw("\\s")
  end

    # Matches any white space
  def NULL.spaces
    @spaces ||= space.one_or_more
  end

  # Matches any non-white space
  def NULL.nonspace
    @nonspace ||= Rexp.raw("\\S")
  end
  
  # Matches any non-white space
  def NULL.nonspaces
    @nonspaces ||= Rexp.raw("\\S").one_or_more
  end
  
  # Matches any sequence of word characters
  def NULL.word_char
    @word_char ||= Rexp.raw("\\w")
  end
  
  # Matches any sequence of word characters
  def NULL.word
    @word ||= word_char.one_or_more
  end
  
  # Zero-length matches any break
  def NULL.break
    @break ||= Rexp.raw("\\b")
  end
  
  # Matches a digit
  def NULL.digit
    @digit ||= any("0-9")
  end
  
  # Matches a sequence of digits
  def NULL.digits
    @digits ||= digit.one_or_more
  end
  
  # Matches a hex digit (upper or lower case)
  def NULL.hex_digit
    @hex_digit ||= any("0-9", "a-f", "A-F")
  end
  
  # Matches a sequence of hex digits
  def NULL.hex_digits
    @hex_digits ||= hex_digit.one_or_more
  end
end

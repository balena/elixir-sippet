// Copyright (c) 2017 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Parts of this code was taken from Chromium sources:
// Copyright (c) 2011-2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "utils.h"

#include <string>
#include <iostream>
#include <limits>

namespace {

// Utility to convert a character to a digit in a given base
template<typename CHAR, int BASE, bool BASE_LTE_10> class BaseCharToDigit {
};

// Faster specialization for bases <= 10
template<typename CHAR, int BASE> class BaseCharToDigit<CHAR, BASE, true> {
 public:
  static bool Convert(CHAR c, uint8_t* digit) {
    if (c >= '0' && c < '0' + BASE) {
      *digit = static_cast<uint8_t>(c - '0');
      return true;
    }
    return false;
  }
};

// Specialization for bases where 10 < base <= 36
template<typename CHAR, int BASE> class BaseCharToDigit<CHAR, BASE, false> {
 public:
  static bool Convert(CHAR c, uint8_t* digit) {
    if (c >= '0' && c <= '9') {
      *digit = c - '0';
    } else if (c >= 'a' && c < 'a' + BASE - 10) {
      *digit = c - 'a' + 10;
    } else if (c >= 'A' && c < 'A' + BASE - 10) {
      *digit = c - 'A' + 10;
    } else {
      return false;
    }
    return true;
  }
};

template <int BASE, typename CHAR>
bool CharToDigit(CHAR c, uint8_t* digit) {
  return BaseCharToDigit<CHAR, BASE, BASE <= 10>::Convert(c, digit);
}

// There is an IsUnicodeWhitespace for wchars defined in string_util.h, but it
// is locale independent, whereas the functions we are replacing were
// locale-dependent. TBD what is desired, but for the moment let's not
// introduce a change in behaviour.
template<typename CHAR> class WhitespaceHelper {
};

template<> class WhitespaceHelper<char> {
 public:
  static bool Invoke(char c) {
    return 0 != isspace(static_cast<unsigned char>(c));
  }
};

template<typename CHAR> bool LocalIsWhitespace(CHAR c) {
  return WhitespaceHelper<CHAR>::Invoke(c);
}

// IteratorRangeToNumberTraits should provide:
//  - a typedef for iterator_type, the iterator type used as input.
//  - a typedef for value_type, the target numeric type.
//  - static functions min, max (returning the minimum and maximum permitted
//    values)
//  - constant kBase, the base in which to interpret the input
template<typename IteratorRangeToNumberTraits>
class IteratorRangeToNumber {
 public:
  typedef IteratorRangeToNumberTraits traits;
  typedef typename traits::iterator_type const_iterator;
  typedef typename traits::value_type value_type;

  // Generalized iterator-range-to-number conversion.
  //
  static bool Invoke(const_iterator begin,
                     const_iterator end,
                     value_type* output) {
    bool valid = true;

    while (begin != end && LocalIsWhitespace(*begin)) {
      valid = false;
      ++begin;
    }

    if (begin != end && *begin == '-') {
      if (!std::numeric_limits<value_type>::is_signed) {
        *output = 0;
        valid = false;
      } else if (!Negative::Invoke(begin + 1, end, output)) {
        valid = false;
      }
    } else {
      if (begin != end && *begin == '+') {
        ++begin;
      }
      if (!Positive::Invoke(begin, end, output)) {
        valid = false;
      }
    }

    return valid;
  }

 private:
  // Sign provides:
  //  - a static function, CheckBounds, that determines whether the next digit
  //    causes an overflow/underflow
  //  - a static function, Increment, that appends the next digit appropriately
  //    according to the sign of the number being parsed.
  template<typename Sign>
  class Base {
   public:
    static bool Invoke(const_iterator begin, const_iterator end,
                       typename traits::value_type* output) {
      *output = 0;

      if (begin == end) {
        return false;
      }

      // Note: no performance difference was found when using template
      // specialization to remove this check in bases other than 16
      if (traits::kBase == 16 && end - begin > 2 && *begin == '0' &&
          (*(begin + 1) == 'x' || *(begin + 1) == 'X')) {
        begin += 2;
      }

      for (const_iterator current = begin; current != end; ++current) {
        uint8_t new_digit = 0;

        if (!CharToDigit<traits::kBase>(*current, &new_digit)) {
          return false;
        }

        if (current != begin) {
          if (!Sign::CheckBounds(output, new_digit)) {
            return false;
          }
          *output *= traits::kBase;
        }

        Sign::Increment(new_digit, output);
      }
      return true;
    }
  };

  class Positive : public Base<Positive> {
   public:
    static bool CheckBounds(value_type* output, uint8_t new_digit) {
      if (*output > static_cast<value_type>(traits::max() / traits::kBase) ||
          (*output == static_cast<value_type>(traits::max() / traits::kBase) &&
           new_digit > traits::max() % traits::kBase)) {
        *output = traits::max();
        return false;
      }
      return true;
    }
    static void Increment(uint8_t increment, value_type* output) {
      *output += increment;
    }
  };

  class Negative : public Base<Negative> {
   public:
    static bool CheckBounds(value_type* output, uint8_t new_digit) {
      if (*output < traits::min() / traits::kBase ||
          (*output == traits::min() / traits::kBase &&
           new_digit > 0 - traits::min() % traits::kBase)) {
        *output = traits::min();
        return false;
      }
      return true;
    }
    static void Increment(uint8_t increment, value_type* output) {
      *output -= increment;
    }
  };
};

template<typename ITERATOR, typename VALUE, int BASE>
class BaseIteratorRangeToNumberTraits {
 public:
  typedef ITERATOR iterator_type;
  typedef VALUE value_type;
  static value_type min() {
    return std::numeric_limits<value_type>::min();
  }
  static value_type max() {
    return std::numeric_limits<value_type>::max();
  }
  static const int kBase = BASE;
};

template <typename VALUE, int BASE>
class StringPieceToNumberTraits
    : public BaseIteratorRangeToNumberTraits<StringPiece::const_iterator,
                                             VALUE,
                                             BASE> {
};

template <typename VALUE>
bool StringToIntImpl(const StringPiece& input, VALUE* output) {
  return IteratorRangeToNumber<StringPieceToNumberTraits<VALUE, 10> >::Invoke(
      input.begin(), input.end(), output);
}

// See RFC 2616 Sec 2.2 for the definition of |token|.
template<typename It>
bool IsTokenImpl(It begin, It end) {
  if (begin == end)
    return false;
  for (It iter = begin; iter != end; ++iter) {
    if (!IsTokenChar(*iter))
      return false;
  }
  return true;
}

bool UnquoteImpl(std::string::const_iterator begin,
                 std::string::const_iterator end,
                 bool strict_quotes,
                 std::string* out) {
  // Empty string
  if (begin == end)
    return false;

  // Nothing to unquote.
  if (!IsQuote(*begin))
    return false;

  // Anything other than double quotes in strict mode.
  if (strict_quotes && *begin != '"')
    return false;

  // No terminal quote mark.
  if (end - begin < 2 || *begin != *(end - 1))
    return false;

  char quote = *begin;

  // Strip quotemarks
  ++begin;
  --end;

  // Unescape quoted-pair (defined in RFC 2616 section 2.2)
  bool prev_escape = false;
  std::string unescaped;
  for (; begin != end; ++begin) {
    char c = *begin;
    if (c == '\\' && !prev_escape) {
      prev_escape = true;
      continue;
    }
    if (strict_quotes && !prev_escape && c == quote)
      return false;
    prev_escape = false;
    unescaped.push_back(c);
  }

  // Terminal quote is escaped.
  if (strict_quotes && prev_escape)
    return false;

  *out = std::move(unescaped);
  return true;
}

bool StrictUnquote(std::string::const_iterator begin,
                   std::string::const_iterator end,
                   std::string* out) {
  return UnquoteImpl(begin, end, true, out);
}

}  // namespace

bool IsTokenChar(unsigned char c) {
  return !(c >= 0x80 || c <= 0x1F || c == 0x7F || c == '(' || c == ')' ||
           c == '<' || c == '>' || c == '@' || c == ',' || c == ';' ||
           c == ':' || c == '\\' || c == '"' || c == '/' || c == '[' ||
           c == ']' || c == '?' || c == '=' || c == '{' || c == '}' ||
           c == ' ' || c == '\t');
}

bool IsToken(std::string::const_iterator begin,
             std::string::const_iterator end) {
  return IsTokenImpl(begin, end);
}
bool IsToken(StringPiece::const_iterator begin,
             StringPiece::const_iterator end) {
  return IsTokenImpl(begin, end);
}

// ASCII-specific tolower.  The standard library's tolower is locale sensitive,
// so we don't want to use it here.
char ToLowerASCII(char c) {
  return (c >= 'A' && c <= 'Z') ? (c + ('a' - 'A')) : c;
}

std::string ToLowerASCII(StringPiece str) {
  std::string ret;
  ret.reserve(str.size());
  for (size_t i = 0; i < str.size(); i++)
    ret.push_back(ToLowerASCII(str[i]));
  return ret;
}

// Implementation note: Normally this function will be called with a hardcoded
// constant for the lowercase_ascii parameter. Constructing a StringPiece from
// a C constant requires running strlen, so the result will be two passes
// through the buffers, one to file the length of lowercase_ascii, and one to
// compare each letter.
//
// This function could have taken a const char* to avoid this and only do one
// pass through the string. But the strlen is faster than the case-insensitive
// compares and lets us early-exit in the case that the strings are different
// lengths (will often be the case for non-matches). So whether one approach or
// the other will be faster depends on the case.
//
// The hardcoded strings are typically very short so it doesn't matter, and the
// string piece gives additional flexibility for the caller (doesn't have to be
// null terminated) so we choose the StringPiece route.
bool LowerCaseEqualsASCII(StringPiece str, StringPiece lowercase_ascii) {
  if (str.size() != lowercase_ascii.size())
    return false;
  for (size_t i = 0; i < str.size(); i++) {
    if (ToLowerASCII(str[i]) != lowercase_ascii[i])
      return false;
  }
  return true;
}

bool StringToInt(const StringPiece& input, int* output) {
  return StringToIntImpl(input, output);
}

bool StringToDouble(const StringPiece& input, double* output) {
  try {
    *output = stod(input.as_string());
    return true;
  } catch (const std::exception& e) {
    return false;
  }
}

bool IsLWS(char c) {
  return strchr(SIP_LWS, c) != NULL;
}

void TrimLWS(std::string::const_iterator* begin,
             std::string::const_iterator* end) {
  // leading whitespace
  while (*begin < *end && IsLWS((*begin)[0]))
    ++(*begin);

  // trailing whitespace
  while (*begin < *end && IsLWS((*end)[-1]))
    --(*end);
}

bool IsQuote(char c) {
  // Single quote mark isn't actually part of quoted-text production,
  // but apparently some servers rely on this.
  return c == '"' || c == '\'';
}

std::string Unquote(std::string::const_iterator begin,
                    std::string::const_iterator end) {
  std::string result;
  if (!UnquoteImpl(begin, end, false, &result))
    return std::string(begin, end);

  return result;
}

bool ParseHostAndPort(std::string::const_iterator host_and_port_begin,
                      std::string::const_iterator host_and_port_end,
                      std::string* host,
                      int* port) {
  if (host_and_port_begin >= host_and_port_end)
    return false;

  // hostport       = host [ COLON port ]
  // host           = hostname / IPv4address / IPv6reference
  // hostname       = *( domainlabel "." ) toplabel [ "." ]
  // domainlabel    =  alphanum / alphanum *( alphanum / "-" ) alphanum
  // toplabel       = ALPHA / ALPHA *( alphanum / "-" ) alphanum
  // IPv4address    =  1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT
  // IPv6reference  =  "[" IPv6address "]"
  // IPv6address    =  hexpart [ ":" IPv4address ]
  // hexpart        =  hexseq / hexseq "::" [ hexseq ] / "::" [ hexseq ]
  // hexseq         =  hex4 *( ":" hex4)
  // hex4           =  1*4HEXDIG
  // port           =  1*DIGIT

  std::string::const_iterator host_start = host_and_port_begin, host_end;
  if (*host_and_port_begin == '[') {
    // parse an IPv6 address
    for (; host_and_port_begin < host_and_port_end; host_and_port_begin++) {
      if (*host_and_port_begin == ']')
        break;
    }
    if (host_and_port_begin == host_and_port_end)
      return false;
    host_end = ++host_and_port_begin;
  } else {
    // parse a hostname or IPv4 address
    for (; host_and_port_begin < host_and_port_end; host_and_port_begin++) {
      if (*host_and_port_begin == ':')
        break;
    }
    host_end = host_and_port_begin;
  }

  std::string::const_iterator port_start, port_end;
  if (host_and_port_begin < host_and_port_end
      && *host_and_port_begin == ':') {
    port_start = ++host_and_port_begin;
    for (; host_and_port_begin < host_and_port_end; host_and_port_begin++) {
      if (!isdigit(*host_and_port_begin))
        return false;
    }
    port_end = host_and_port_begin;
  } else {
    port_start = port_end = host_and_port_end;
  }

  if (host_and_port_begin < host_and_port_end) {
    // trailing garbage is considered error
    return false;
  }

  if (port_start < port_end) {
    if (!StringToInt(StringPiece(port_start, port_end), port))
      return false;
  } else {
    *port = -1;
  }

  host->assign(host_start, host_end);
  return true;
}

bool ParseHostAndPort(const std::string& host_and_port,
                      std::string* host,
                      int* port) {
  return ParseHostAndPort(
      host_and_port.begin(), host_and_port.end(), host, port);
}

HeadersIterator::HeadersIterator(
    std::string::const_iterator headers_begin,
    std::string::const_iterator headers_end,
    const std::string& line_delimiter)
    : lines_(headers_begin, headers_end, line_delimiter) {
}

HeadersIterator::~HeadersIterator() {
}

bool HeadersIterator::GetNext() {
  while (lines_.GetNext()) {
    name_begin_ = lines_.token_begin();
    values_end_ = lines_.token_end();

    std::string::const_iterator colon(std::find(name_begin_, values_end_, ':'));
    if (colon == values_end_)
      continue;  // skip malformed header

    name_end_ = colon;

    // If the name starts with LWS, it is an invalid line.
    // Leading LWS implies a line continuation, and these should have
    // already been joined by AssembleRawHeaders().
    if (name_begin_ == name_end_ || IsLWS(*name_begin_))
      continue;

    TrimLWS(&name_begin_, &name_end_);
    if (!IsToken(name_begin_, name_end_))
      continue;  // skip malformed header

    values_begin_ = colon + 1;
    TrimLWS(&values_begin_, &values_end_);

    // if we got a header name, then we are done.
    return true;
  }
  return false;
}

bool HeadersIterator::AdvanceTo(const char* name) {
  while (GetNext()) {
    if (LowerCaseEqualsASCII(StringPiece(name_begin_, name_end_), name)) {
      return true;
    }
  }
  return false;
}

ValuesIterator::ValuesIterator(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end,
    char delimiter)
    : values_(values_begin, values_end, std::string(1, delimiter)) {
  values_.set_quote_chars("\'\"");
}

ValuesIterator::ValuesIterator(const ValuesIterator& other) = default;

ValuesIterator::~ValuesIterator() {
}

bool ValuesIterator::GetNext() {
  while (values_.GetNext()) {
    value_begin_ = values_.token_begin();
    value_end_ = values_.token_end();
    TrimLWS(&value_begin_, &value_end_);

    // bypass empty values.
    if (value_begin_ != value_end_)
      return true;
  }
  return false;
}

GenericParametersIterator::GenericParametersIterator(
    std::string::const_iterator begin,
    std::string::const_iterator end)
    : props_(begin, end, ';'),
      valid_(true),
      name_begin_(end),
      name_end_(end),
      value_begin_(end),
      value_end_(end),
      value_is_quoted_(false) {
}

GenericParametersIterator::~GenericParametersIterator() {
}

bool GenericParametersIterator::GetNext() {
  if (!props_.GetNext())
    return false;

  value_begin_ = props_.value_begin();
  value_end_ = props_.value_end();
  name_begin_ = name_end_ = value_end_;

  std::string::const_iterator equals =
      std::find(value_begin_, value_end_, '=');
  if (equals != value_end_ && equals != value_begin_) {
    name_begin_ = value_begin_;
    name_end_ = equals;
    value_begin_ = equals + 1;
  } else {
    name_begin_ = value_begin_;
    name_end_ = value_end_;
    value_begin_ = value_end_;
  }

  TrimLWS(&name_begin_, &name_end_);
  TrimLWS(&value_begin_, &value_end_);
  value_is_quoted_ = false;
  unquoted_value_.clear();

  if (value_begin_ != value_end_) {
    if (IsQuote(*value_begin_)) {
      if (*value_begin_ != *(value_end_ - 1)
          || value_begin_ + 1 == value_end_) {
        ++value_begin_;
      } else {
        value_is_quoted_ = true;
        unquoted_value_ = Unquote(value_begin_, value_end_);
      }
    }
  }

  return true;
}

NameValuePairsIterator::NameValuePairsIterator(
    std::string::const_iterator begin,
    std::string::const_iterator end,
    char delimiter,
    Values optional_values,
    Quotes strict_quotes)
    : props_(begin, end, delimiter),
      valid_(true),
      name_begin_(end),
      name_end_(end),
      value_begin_(end),
      value_end_(end),
      value_is_quoted_(false),
      values_optional_(optional_values == Values::NOT_REQUIRED),
      strict_quotes_(strict_quotes == Quotes::STRICT_QUOTES) {
  if (strict_quotes_)
    props_.set_quote_chars("\"");
}

NameValuePairsIterator::NameValuePairsIterator(
    std::string::const_iterator begin,
    std::string::const_iterator end,
    char delimiter)
    : NameValuePairsIterator(begin,
                             end,
                             delimiter,
                             Values::REQUIRED,
                             Quotes::NOT_STRICT) {}

NameValuePairsIterator::NameValuePairsIterator(
    const NameValuePairsIterator& other) = default;

NameValuePairsIterator::~NameValuePairsIterator() {}

// We expect properties to be formatted as one of:
//   name="value"
//   name='value'
//   name='\'value\''
//   name=value
//   name = value
//   name (if values_optional_ is true)
// Due to buggy implementations found in some embedded devices, we also
// accept values with missing close quotemark (http://crbug.com/39836):
//   name="value
bool NameValuePairsIterator::GetNext() {
  if (!props_.GetNext())
    return false;

  // Set the value as everything. Next we will split out the name.
  value_begin_ = props_.value_begin();
  value_end_ = props_.value_end();
  name_begin_ = name_end_ = value_end_;

  // Scan for the equals sign.
  std::string::const_iterator equals = std::find(value_begin_, value_end_, '=');
  if (equals == value_begin_)
    return valid_ = false;  // Malformed, no name
  if (equals == value_end_ && !values_optional_)
    return valid_ = false;  // Malformed, no equals sign and values are required

  // If an equals sign was found, verify that it wasn't inside of quote marks.
  if (equals != value_end_) {
    for (std::string::const_iterator it = value_begin_; it != equals; ++it) {
      if (IsQuote(*it))
        return valid_ = false;  // Malformed, quote appears before equals sign
    }
  }

  name_begin_ = value_begin_;
  name_end_ = equals;
  value_begin_ = (equals == value_end_) ? value_end_ : equals + 1;

  TrimLWS(&name_begin_, &name_end_);
  TrimLWS(&value_begin_, &value_end_);
  value_is_quoted_ = false;
  unquoted_value_.clear();

  if (equals != value_end_ && value_begin_ == value_end_) {
    // Malformed; value is empty
    return valid_ = false;
  }

  if (value_begin_ != value_end_ && IsQuote(*value_begin_)) {
    value_is_quoted_ = true;

    if (strict_quotes_) {
      if (!StrictUnquote(value_begin_, value_end_, &unquoted_value_))
        return valid_ = false;
      return true;
    }

    // Trim surrounding quotemarks off the value
    if (*value_begin_ != *(value_end_ - 1) || value_begin_ + 1 == value_end_) {
      // NOTE: This is not as graceful as it sounds:
      // * quoted-pairs will no longer be unquoted
      //   (["\"hello] should give ["hello]).
      // * Does not detect when the final quote is escaped
      //   (["value\"] should give [value"])
      value_is_quoted_ = false;
      ++value_begin_;  // Gracefully recover from mismatching quotes.
    } else {
      // Do not store iterators into this. See declaration of unquoted_value_.
      unquoted_value_ = Unquote(value_begin_, value_end_);
    }
  }

  return true;
}

bool NameValuePairsIterator::IsQuote(char c) const {
  if (strict_quotes_)
    return c == '"';
  return ::IsQuote(c);
}

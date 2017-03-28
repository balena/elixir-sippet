// Copyright (c) 2017 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Parts of this code was taken from Chromium sources:
// Copyright (c) 2011-2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


#ifndef UTILS_H_
#define UTILS_H_

#include <string>

#include "string_tokenizer.h"


// ASCII-specific tolower.  The standard library's tolower is locale sensitive,
// so we don't want to use it here.
char ToLowerASCII(char c);

// Converts the given string to it's ASCII-lowercase equivalent.
std::string ToLowerASCII(StringPiece str);

// Compare the lower-case form of the given string against the given
// previously-lower-cased ASCII string (typically a constant).
bool LowerCaseEqualsASCII(StringPiece str, StringPiece lowercase_ascii);

// Perform a best-effort conversion of the input string to a numeric type,
// setting |*output| to the result of the conversion.  Returns true for
// "perfect" conversions; returns false in the following cases:
//  - Overflow. |*output| will be set to the maximum value supported
//    by the data type.
//  - Underflow. |*output| will be set to the minimum value supported
//    by the data type.
//  - Trailing characters in the string after parsing the number.  |*output|
//    will be set to the value of the number that was parsed.
//  - Leading whitespace in the string before parsing the number. |*output| will
//    be set to the value of the number that was parsed.
//  - No characters parseable as a number at the beginning of the string.
//    |*output| will be set to 0.
//  - Empty string.  |*output| will be set to 0.
// WARNING: Will write to |output| even when returning false.
//          Read the comments above carefully.
bool StringToInt(const StringPiece& input, int* output);

// For floating-point conversions, only conversions of input strings in decimal
// form are defined to work.  Behavior with strings representing floating-point
// numbers in hexadecimal, and strings representing non-finite values (such as
// NaN and inf) is undefined.  Otherwise, these behave the same as the integral
// variants.  This expects the input string to NOT be specific to the locale.
// If your input is locale specific, use ICU to read the number.
// WARNING: Will write to |output| even when returning false.
//          Read the comments here and above StringToInt() carefully.
bool StringToDouble(const StringPiece& input, double* output);

// Return true if the character is SIP "linear white space" (SP | HT).
// This definition corresponds with the SIP_LWS macro, and does not match
// newlines.
bool IsLWS(char c);

// This is a macro to support extending this string literal at compile time.
// Please excuse me polluting your global namespace!
#define SIP_LWS " \t"

bool IsTokenChar(unsigned char c);

// Whether the string is a valid |token| as defined in RFC 2616 Sec 2.2.
bool IsToken(std::string::const_iterator begin,
             std::string::const_iterator end);
bool IsToken(StringPiece::const_iterator begin,
             StringPiece::const_iterator end);
inline bool IsToken(StringPiece str) {
  return IsToken(str.begin(), str.end());
}

// Trim SIP_LWS chars from the beginning and end of the string.
void TrimLWS(std::string::const_iterator* begin,
             std::string::const_iterator* end);

// Whether the character is the start of a quotation mark.
bool IsQuote(char c);

// RFC 2616 Sec 2.2:
// quoted-string = ( <"> *(qdtext | quoted-pair ) <"> )
// Unquote() strips the surrounding quotemarks off a string, and unescapes
// any quoted-pair to obtain the value contained by the quoted-string.
// If the input is not quoted, then it works like the identity function.
std::string Unquote(std::string::const_iterator begin,
                    std::string::const_iterator end);

// Splits an input of the form <host>[":"<port>] into its consitituent parts.
// Saves the result into |*host| and |*port|. If the input did not have
// the optional port, sets |*port| to -1.
// Returns true if the parsing was successful, false otherwise.
// The returned host is NOT canonicalized, and may be invalid.
//
// IPv6 literals must be specified in a bracketed form, for instance:
//   [::1]:90 and [::1]
//
// The resultant |*host| in both cases will be "::1" (not bracketed).
bool ParseHostAndPort(
    std::string::const_iterator host_and_port_begin,
    std::string::const_iterator host_and_port_end,
    std::string* host,
    int* port);
bool ParseHostAndPort(const std::string& host_and_port,
                      std::string* host,
                      int* port);

// Used to iterate over the name/value pairs of SIP headers.  To iterate
// over the values in a multi-value header, use ValuesIterator.
// See AssembleRawHeaders for joining line continuations (this iterator
// does not expect any).
class HeadersIterator {
 public:
  HeadersIterator(std::string::const_iterator headers_begin,
                  std::string::const_iterator headers_end,
                  const std::string& line_delimiter);
  ~HeadersIterator();

  // Advances the iterator to the next header, if any.  Returns true if there
  // is a next header.  Use name* and values* methods to access the resultant
  // header name and values.
  bool GetNext();

  // Iterates through the list of headers, starting with the current position
  // and looks for the specified header.  Note that the name _must_ be
  // lower cased.
  // If the header was found, the return value will be true and the current
  // position points to the header.  If the return value is false, the
  // current position will be at the end of the headers.
  bool AdvanceTo(const char* lowercase_name);

  void Reset() {
    lines_.Reset();
  }

  std::string::const_iterator name_begin() const {
    return name_begin_;
  }
  std::string::const_iterator name_end() const {
    return name_end_;
  }
  std::string name() const {
    return std::string(name_begin_, name_end_);
  }

  std::string::const_iterator values_begin() const {
    return values_begin_;
  }
  std::string::const_iterator values_end() const {
    return values_end_;
  }
  std::string values() const {
    return std::string(values_begin_, values_end_);
  }

 private:
  StringTokenizer lines_;
  std::string::const_iterator name_begin_;
  std::string::const_iterator name_end_;
  std::string::const_iterator values_begin_;
  std::string::const_iterator values_end_;
};

// Iterates over delimited values in a SIP header.  SIP LWS is
// automatically trimmed from the resulting values.
//
// When using this class to iterate over response header values, be aware that
// for some headers (e.g., Last-Modified), commas are not used as delimiters.
// This iterator should be avoided for headers like that which are considered
// non-coalescing (see IsNonCoalescingHeader).
//
// This iterator is careful to skip over delimiters found inside an SIP
// quoted string.
//
class ValuesIterator {
 public:
  ValuesIterator(std::string::const_iterator values_begin,
                 std::string::const_iterator values_end,
                 char delimiter);
  ValuesIterator(const ValuesIterator& other);
  ~ValuesIterator();

  // Set the characters to regard as quotes.  By default, this includes both
  // single and double quotes.
  void set_quote_chars(const char* quotes) {
    values_.set_quote_chars(quotes);
  }

  // Advances the iterator to the next value, if any.  Returns true if there
  // is a next value.  Use value* methods to access the resultant value.
  bool GetNext();

  std::string::const_iterator value_begin() const {
    return value_begin_;
  }
  std::string::const_iterator value_end() const {
    return value_end_;
  }
  std::string value() const {
    return std::string(value_begin_, value_end_);
  }

 private:
  StringTokenizer values_;
  std::string::const_iterator value_begin_;
  std::string::const_iterator value_end_;
};

// Iterates over SIP header parameters delimited by ';'.  SIP LWS is
// automatically trimmed from the resulting values.
//
class GenericParametersIterator {
 public:
  GenericParametersIterator(std::string::const_iterator begin,
                            std::string::const_iterator end);
  ~GenericParametersIterator();

  bool GetNext();

  bool valid() const { return valid_; }

  std::string::const_iterator name_begin() const { return name_begin_; }
  std::string::const_iterator name_end() const { return name_end_; }
  std::string name() const { return std::string(name_begin_, name_end_); }

  std::string::const_iterator value_begin() const {
    return value_is_quoted_ ? unquoted_value_.begin() : value_begin_;
  }
  std::string::const_iterator value_end() const {
    return value_is_quoted_ ? unquoted_value_.end() : value_end_;
  }
  std::string value() const {
    return value_is_quoted_ ? unquoted_value_ : std::string(value_begin_,
                                                            value_end_);
  }

  std::string raw_value() const { return std::string(value_begin_,
                                                      value_end_); }

 private:
  ValuesIterator props_;
  bool valid_;

  std::string::const_iterator name_begin_;
  std::string::const_iterator name_end_;

  std::string::const_iterator value_begin_;
  std::string::const_iterator value_end_;

  std::string unquoted_value_;

  bool value_is_quoted_;
};

// Iterates over a delimited sequence of name-value pairs in an HTTP header.
// Each pair consists of a token (the name), an equals sign, and either a
// token or quoted-string (the value). Arbitrary HTTP LWS is permitted outside
// of and between names, values, and delimiters.
//
// String iterators returned from this class' methods may be invalidated upon
// calls to GetNext() or after the NameValuePairsIterator is destroyed.
class NameValuePairsIterator {
 public:
  // Whether or not values are optional. Values::NOT_REQUIRED allows
  // e.g. name1=value1;name2;name3=value3, whereas Vaues::REQUIRED
  // will treat it as a parse error because name2 does not have a
  // corresponding equals sign.
  enum class Values { NOT_REQUIRED, REQUIRED };

  // Whether or not unmatched quotes should be considered a failure. By
  // default this class is pretty lenient and does a best effort to parse
  // values with mismatched quotes. When set to STRICT_QUOTES a value with
  // mismatched or otherwise invalid quotes is considered a parse error.
  enum class Quotes { STRICT_QUOTES, NOT_STRICT };

  NameValuePairsIterator(std::string::const_iterator begin,
                         std::string::const_iterator end,
                         char delimiter,
                         Values optional_values,
                         Quotes strict_quotes);

  // Treats values as not optional by default (Values::REQUIRED) and
  // treats quotes as not strict.
  NameValuePairsIterator(std::string::const_iterator begin,
                         std::string::const_iterator end,
                         char delimiter);

  NameValuePairsIterator(const NameValuePairsIterator& other);

  ~NameValuePairsIterator();

  // Advances the iterator to the next pair, if any.  Returns true if there
  // is a next pair.  Use name* and value* methods to access the resultant
  // value.
  bool GetNext();

  // Returns false if there was a parse error.
  bool valid() const { return valid_; }

  // The name of the current name-value pair.
  std::string::const_iterator name_begin() const { return name_begin_; }
  std::string::const_iterator name_end() const { return name_end_; }
  std::string name() const { return std::string(name_begin_, name_end_); }

  // The value of the current name-value pair.
  std::string::const_iterator value_begin() const {
    return value_is_quoted_ ? unquoted_value_.begin() : value_begin_;
  }
  std::string::const_iterator value_end() const {
    return value_is_quoted_ ? unquoted_value_.end() : value_end_;
  }
  std::string value() const {
    return value_is_quoted_ ? unquoted_value_ : std::string(value_begin_,
                                                            value_end_);
  }

  bool value_is_quoted() const { return value_is_quoted_; }

  // The value before unquoting (if any).
  std::string raw_value() const { return std::string(value_begin_,
                                                     value_end_); }

 private:
  bool IsQuote(char c) const;

  ValuesIterator props_;
  bool valid_;

  std::string::const_iterator name_begin_;
  std::string::const_iterator name_end_;

  std::string::const_iterator value_begin_;
  std::string::const_iterator value_end_;

  // Do not store iterators into this string. The NameValuePairsIterator
  // is copyable/assignable, and if copied the copy's iterators would point
  // into the original's unquoted_value_ member.
  std::string unquoted_value_;

  bool value_is_quoted_;

  // True if values are required for each name/value pair; false if a
  // name is permitted to appear without a corresponding value.
  bool values_optional_;

  // True if quotes values are required to be properly quoted; false if
  // mismatched quotes and other problems with quoted values should be more
  // or less gracefully treated as valid.
  bool strict_quotes_;
};

#endif // UTILS_H_

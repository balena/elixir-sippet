// Copyright (c) 2013 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef TOKENIZER_H_
#define TOKENIZER_H_

#include <string>

#include "string_piece.h"

class Tokenizer {
public:
  Tokenizer(std::string::const_iterator string_begin,
            std::string::const_iterator string_end);
  ~Tokenizer();

  std::string::const_iterator Skip(const StringPiece& chars) {
    for (; current_ != end_; ++current_) {
      if (chars.find(*current_) == std::string::npos)
        break;
    }
    return current_;
  }

  std::string::const_iterator SkipNotIn(const StringPiece& chars) {
    for (; current_ != end_; ++current_) {
      if (chars.find(*current_) != std::string::npos)
        break;
    }
    return current_;
  }

  std::string::const_iterator SkipTo(char c) {
    for (; current_ != end_; ++current_) {
      if (c == *current_)
        break;
    }
    return current_;
  }

  std::string::const_iterator Skip() {
    if (current_ != end_)
      ++current_;
    return current_;
  }

  std::string::const_iterator Skip(int n) {
    for (; current_ != end_ && n > 0; --n)
      ++current_;
    return current_;
  }

  bool EndOfInput() const {
    return current_ == end_;
  }

  std::string::const_iterator current() const { return current_; }
  void set_current(std::string::const_iterator current) {
    current_ = current;
  }

  std::string::const_iterator end() const { return end_; }
  void set_end(std::string::const_iterator end) {
    end_ = end;
  }

private:
  std::string::const_iterator current_;
  std::string::const_iterator end_;
};

#endif // TOKENIZER_H_

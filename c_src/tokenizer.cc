// Copyright (c) 2013 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "tokenizer.h"

Tokenizer::Tokenizer(std::string::const_iterator string_begin,
                     std::string::const_iterator string_end)
  : current_(string_begin), end_(string_end) {
}

Tokenizer::~Tokenizer() {
}

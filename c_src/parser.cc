// Copyright (c) 2017 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Parts of this code was taken from Chromium sources:
// Copyright (c) 2011-2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <erl_nif.h>

#include <cstring>
#include <unordered_map>
#include <iostream>

#include "prtime.h"
#include "string_piece.h"
#include "tokenizer.h"
#include "string_tokenizer.h"
#include "utils.h"

namespace {

typedef ERL_NIF_TERM (*ParseFunction)(ErlNifEnv* env,
                                      std::string::const_iterator,
                                      std::string::const_iterator);

std::unordered_map<char, ERL_NIF_TERM> g_aliases;
std::unordered_map<ERL_NIF_TERM, ParseFunction> g_parsers;

bool MakeExistingAtom(ErlNifEnv* env, StringPiece atom_name,
    ERL_NIF_TERM *atom) {
  return enif_make_existing_atom_len(env, atom_name.data(), atom_name.size(),
      atom, ERL_NIF_LATIN1);
}

bool MakeLowerCaseExistingAtom(ErlNifEnv* env, StringPiece name,
    ERL_NIF_TERM *atom) {
  std::string atom_name(name.as_string());
  for (auto& c : atom_name) {
    if (c == '-')
      c = '_';
    else
      c = ToLowerASCII(c);
  }
  return MakeExistingAtom(env, atom_name, atom);
}

ERL_NIF_TERM MakeString(ErlNifEnv* env, StringPiece s) {
  ErlNifBinary bin;
  if (!enif_alloc_binary(s.size(), &bin))
    return enif_make_atom(env, "no_memory");
  memcpy(bin.data, s.data(), s.size());
  return enif_make_binary(env, &bin);
}

ERL_NIF_TERM MakeLowerCaseString(ErlNifEnv* env, StringPiece s) {
  std::string lowercase(s.as_string());
  for (auto& c : lowercase)
    c = ToLowerASCII(c);
  return MakeString(env, lowercase);
}

ERL_NIF_TERM MakeLowerCaseExistingAtomOrString(ErlNifEnv* env, StringPiece name) {
  ERL_NIF_TERM result;
  if (!MakeLowerCaseExistingAtom(env, name, &result))
    result = MakeString(env, name);
  return result;
}

bool IsStatusLine(
      std::string::const_iterator line_begin,
      std::string::const_iterator line_end) {
  return ((line_end - line_begin > 4)
      && LowerCaseEqualsASCII(
             StringPiece(line_begin, line_begin + 4), "sip/"));
}

std::string::const_iterator FindLineEnd(
    std::string::const_iterator begin,
    std::string::const_iterator end) {
  size_t i = StringPiece(begin, end).find_first_of("\r\n");
  if (i == StringPiece::npos)
    return end;
  return begin + i;
}

ERL_NIF_TERM ParseVersion(ErlNifEnv* env,
    std::string::const_iterator line_begin,
    std::string::const_iterator line_end) {
  Tokenizer tok(line_begin, line_end);

  if ((line_end - line_begin < 3) ||
      !LowerCaseEqualsASCII(
          StringPiece(line_begin, line_begin + 3), "sip")) {
    return enif_make_atom(env, "missing_version_spec");
  }

  tok.Skip(3);
  tok.Skip(SIP_LWS);

  if (tok.EndOfInput()
      || *tok.current() != '/') {
    return enif_make_atom(env, "missing_version");
  }

  tok.Skip();
  std::string::const_iterator major_start = tok.Skip(SIP_LWS);
  tok.SkipTo('.');
  tok.Skip();
  std::string::const_iterator minor_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput()) {
    return enif_make_atom(env, "malformed_version");
  }

  if (!isdigit(*major_start) || !isdigit(*minor_start)) {
    return enif_make_atom(env, "malformed_version_number");
  }

  int major = *major_start - '0';
  int minor = *minor_start - '0';

  return enif_make_tuple2(env, enif_make_int(env, major),
      enif_make_int(env, minor));
}

ERL_NIF_TERM ParseStatusLine(ErlNifEnv* env,
    std::string::const_iterator line_begin,
    std::string::const_iterator line_end) {
  // Extract the version number
  ERL_NIF_TERM version = ParseVersion(env, line_begin, line_end);
  if (enif_is_atom(env, version)) {
    return version;
  }

  std::string::const_iterator p = std::find(line_begin, line_end, ' ');
  if (p == line_end) {
    return enif_make_atom(env, "missing_status_code");
  }

  // Skip whitespace.
  while (*p == ' ')
    ++p;

  std::string::const_iterator code = p;
  while (*p >= '0' && *p <= '9')
    ++p;

  if (p == code) {
    return enif_make_atom(env, "empty_status_code");
  }

  int status_code;
  if (!StringToInt(StringPiece(code, p), &status_code)) {
    return enif_make_atom(env, "invalid_status_code");
  }

  // Skip whitespace.
  while (*p == ' ')
    ++p;

  // Trim trailing whitespace.
  while (line_end > p && line_end[-1] == ' ')
    --line_end;

  std::string reason_phrase;
  if (p < line_end) {
    reason_phrase.assign(p, line_end);
  }

  ERL_NIF_TERM status_line = enif_make_new_map(env);
  enif_make_map_put(env, status_line, enif_make_atom(env, "version"), version,
      &status_line);
  enif_make_map_put(env, status_line, enif_make_atom(env, "status_code"),
      enif_make_int(env, status_code), &status_line);
  enif_make_map_put(env, status_line, enif_make_atom(env, "reason_phrase"),
      MakeString(env, reason_phrase), &status_line);
  return status_line;
}

ERL_NIF_TERM ParseRequestLine(ErlNifEnv* env,
    std::string::const_iterator line_begin,
    std::string::const_iterator line_end) {

  // Skip any leading whitespace.
  while (line_begin != line_end &&
         (*line_begin == ' ' || *line_begin == '\t' ||
          *line_begin == '\r' || *line_begin == '\n'))
    ++line_begin;

  std::string::const_iterator method_start = line_begin;
  std::string::const_iterator p = std::find(line_begin, line_end, ' ');

  if (p == line_end) {
    return enif_make_atom(env, "missing_method");
  }
  
  std::string method(method_start, p);

  // Skip whitespace.
  while (*p == ' ')
    ++p;

  std::string::const_iterator uri_start = p;
  p = std::find(p, line_end, ' ');

  if (p == line_end) {
    return enif_make_atom(env, "missing_uri");
  }
  
  std::string uri(uri_start, p);

  // Skip whitespace.
  while (*p == ' ')
    ++p;

  // Extract the version number
  ERL_NIF_TERM version = ParseVersion(env, p, line_end);
  if (enif_is_atom(env, version)) {
    return version;
  }

  ERL_NIF_TERM request_line = enif_make_new_map(env);
  enif_make_map_put(env, request_line, enif_make_atom(env, "method"),
      MakeLowerCaseExistingAtomOrString(env, method), &request_line);
  enif_make_map_put(env, request_line, enif_make_atom(env, "request_uri"),
      MakeString(env, uri), &request_line);
  enif_make_map_put(env, request_line, enif_make_atom(env, "version"), version,
      &request_line);
  return request_line;
}

ERL_NIF_TERM ParseToken(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator token_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    return enif_make_atom(env, "empty_value");
  }
  return MakeString(env, StringPiece(token_start,
      tok->SkipNotIn(SIP_LWS ";")));
}

ERL_NIF_TERM ParseTypeSubtype(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator type_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    // empty header is OK
    return enif_make_tuple(env, 0);
  }
  StringPiece type(type_start, tok->SkipNotIn(SIP_LWS "/"));
  if (!IsToken(type)) {
    return enif_make_atom(env, "invalid_token");
  }

  tok->SkipTo('/');
  tok->Skip();

  std::string::const_iterator subtype_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    return enif_make_atom(env, "missing_subtype");
  }
  StringPiece subtype(subtype_start, tok->SkipNotIn(SIP_LWS ";"));
  if (!IsToken(subtype)) {
    return enif_make_atom(env, "invalid_token");
  }

  return enif_make_tuple2(env, MakeLowerCaseString(env, type),
      MakeLowerCaseString(env, subtype));
}

ERL_NIF_TERM ParseParameters(ErlNifEnv* env, Tokenizer* tok) {
  // TODO(balena): accept generic param such as ";token"
  ERL_NIF_TERM result = enif_make_new_map(env);
  if (tok->EndOfInput())
    return result;

  tok->SkipTo(';');
  tok->Skip();

  GenericParametersIterator it(tok->current(), tok->end());
  while (it.GetNext()) {
    enif_make_map_put(env, result, MakeLowerCaseString(env, it.name()),
        MakeString(env, it.value()), &result);
  }
  return result;
}

ERL_NIF_TERM ParseAuthScheme(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator scheme_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "missing_auth_scheme");
  StringPiece scheme(scheme_start, tok->SkipNotIn(SIP_LWS));
  return MakeString(env, scheme);
}

ERL_NIF_TERM ParseAuthParams(ErlNifEnv* env, Tokenizer* tok) {
  ERL_NIF_TERM result = enif_make_new_map(env);
  NameValuePairsIterator it(tok->current(), tok->end(), ',');
  while (it.GetNext()) {
    enif_make_map_put(env, result, MakeString(env, it.name()),
        MakeString(env, Unquote(it.value_begin(), it.value_end())), &result);
  }
  return result;
}

ERL_NIF_TERM ParseComment(ErlNifEnv* env, Tokenizer* tok) {
  tok->SkipTo('(');
  if (tok->EndOfInput())
    return enif_make_atom(env, "invalid_comment");

  std::string::const_iterator comment_start = tok->Skip();
  std::string::const_iterator comment_end = tok->end();

  int lparen = 1;
  while (!tok->EndOfInput()) {
    if (*tok->current() == ')') {
      if (--lparen == 0) {
        comment_end = tok->current();
        tok->Skip();
        break;
      }
    } else if (*tok->current() == '(') {
      lparen++;
    }
    tok->Skip();
  }

  if (comment_end == tok->end())
    return enif_make_atom(env, "invalid_comment");

  TrimLWS(&comment_start, &comment_end);
  StringPiece comment(comment_start, comment_end);
  return MakeString(env, comment);
}

ERL_NIF_TERM ParseUri(ErlNifEnv* env, Tokenizer* tok) {
  tok->SkipTo('<');
  if (tok->EndOfInput())
    return enif_make_atom(env, "invalid_uri");
  std::string::const_iterator uri_start = tok->Skip();
  std::string::const_iterator uri_end = tok->SkipTo('>');
  if (tok->EndOfInput())
    return enif_make_atom(env, "unclosed_laquot");
  tok->Skip();
  StringPiece uri(uri_start, uri_end);
  return MakeString(env, uri);
}

ERL_NIF_TERM ParseContact(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator display_name_start, display_name_end;
  StringPiece address;
  tok->Skip(SIP_LWS);
  if (IsQuote(*tok->current())) {
    // contact-param = quoted-string LAQUOT addr-spec RAQUOT
    display_name_start = tok->current();
    tok->Skip();
    for (; !tok->EndOfInput(); tok->Skip()) {
      if (*tok->current() == '\\') {
        tok->Skip();
        continue;
      }
      if (IsQuote(*tok->current()))
        break;
    }
    if (tok->EndOfInput())
      return enif_make_atom(env, "unclosed_qstring");
    display_name_end = tok->Skip();
    tok->SkipTo('<');
    if (tok->EndOfInput())
      return enif_make_atom(env, "missing_address");
    std::string::const_iterator address_start = tok->Skip();
    tok->SkipTo('>');
    if (tok->EndOfInput())
      return enif_make_atom(env, "unclosed_laquot");
    address = StringPiece(address_start, tok->current());
  } else {
    Tokenizer laquot(tok->current(), tok->end());
    laquot.SkipTo('<');
    if (!laquot.EndOfInput()) {
      // contact-param = *(token LWS) LAQUOT addr-spec RAQUOT
      display_name_start = tok->current();
      display_name_end = laquot.current();
      TrimLWS(&display_name_start, &display_name_end);
      std::string::const_iterator address_start = laquot.Skip();
      laquot.SkipTo('>');
      if (laquot.EndOfInput())
        return enif_make_atom(env, "unclosed_laquot");
      address = StringPiece(address_start, laquot.current());
      tok->set_current(laquot.Skip());
    } else if (IsToken(tok->current(), tok->current() + 1)) {
      display_name_start = display_name_end = tok->end();
      std::string::const_iterator address_start = tok->current();
      address = StringPiece(address_start, tok->SkipNotIn(SIP_LWS ";"));
    } else {
      return enif_make_atom(env, "invalid_char_found");
    }
  }

  std::string display_name(Unquote(display_name_start, display_name_end));
  return enif_make_tuple2(env, MakeString(env, display_name),
      MakeString(env, address));
}

bool ParseStar(ErlNifEnv* env, Tokenizer* tok, ERL_NIF_TERM* term) {
  Tokenizer star(tok->current(), tok->end());
  star.Skip(SIP_LWS);
  if (star.EndOfInput())
    return false;
  if (*star.current() != '*')
    return false;
  *term = MakeString(env, "*");
  return true;
}

ERL_NIF_TERM ParseWarning(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator code_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "empty_input");
  StringPiece code_string(code_start, tok->SkipNotIn(SIP_LWS));
  int code = 0;
  if (!StringToInt(code_string, &code)
      || code < 100 || code > 999)
    return enif_make_atom(env, "invalid_code");
  std::string::const_iterator agent_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "empty_warn_agent");
  StringPiece agent(agent_start, tok->SkipNotIn(SIP_LWS));
  tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "missing_warn_text");
  if (*tok->current() != '"')
    return enif_make_atom(env, "invalid_warn_text");
  std::string::const_iterator text_start = tok->current();
  tok->Skip();
  for (; !tok->EndOfInput(); tok->Skip()) {
    if (*tok->current() == '\\') {
      tok->Skip();
      continue;
    }
    if (*tok->current() == '"')
      break;
  }
  if (tok->EndOfInput())
    return enif_make_atom(env, "unclosed_qstring");
  std::string text(text_start, tok->Skip());
  text = Unquote(text.begin(), text.end());
  return enif_make_tuple3(env, enif_make_int(env, code),
      MakeString(env, agent), MakeString(env, text));
}

ERL_NIF_TERM ParseVia(ErlNifEnv* env, Tokenizer* tok) {
  std::string::const_iterator version_start = tok->Skip(SIP_LWS);
  if ((tok->end() - tok->current() < 3)
      || !LowerCaseEqualsASCII(
          StringPiece(tok->current(), tok->current() + 3), "sip"))
    return enif_make_atom(env, "unknown_version");
  tok->SkipTo('/');
  tok->Skip();
  ERL_NIF_TERM version = ParseVersion(env, version_start, tok->SkipTo('/'));
  if (enif_is_atom(env, version))
    return version;
  tok->Skip();
  std::string::const_iterator protocol_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "missing_sent_protocol");
  std::string protocol(protocol_start, tok->SkipNotIn(SIP_LWS));
  protocol = ToLowerASCII(protocol);
  std::string::const_iterator sentby_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput())
    return enif_make_atom(env, "missing_sentby");
  std::string::const_iterator sentby_end = tok->SkipTo(';');
  TrimLWS(&sentby_start, &sentby_end);
  StringPiece sentby_string(sentby_start, sentby_end);
  if (sentby_string.empty())
    return enif_make_atom(env, "missing_sentby");
  std::string host;
  int port;
  if (!ParseHostAndPort(sentby_string.as_string(), &host, &port))
    return enif_make_atom(env, "invalid_sentby");
  if (port == -1) {
    if (protocol == "udp" || protocol == "tcp")
      port = 5060;
    else if (protocol == "tls")
      port = 5061;
    else
      port = 0;
  }
  if (host[0] == '[')  // remove brackets from IPv6 addresses
    host = host.substr(1, host.size()-2);
  return enif_make_tuple3(env, version,
      MakeLowerCaseExistingAtomOrString(env, protocol),
      enif_make_tuple2(env, MakeString(env, host), enif_make_int(env, port)));
}

ERL_NIF_TERM ParseSingleToken(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  return ParseToken(env, &tok);
}

ERL_NIF_TERM ParseSingleTokenParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  ERL_NIF_TERM value = ParseToken(env, &tok);
  if (enif_is_atom(env, value))
    return value;
  ERL_NIF_TERM parameters = ParseParameters(env, &tok);
  if (enif_is_atom(env, parameters))
    return parameters;
  return enif_make_tuple2(env, value, parameters);
}

ERL_NIF_TERM ParseMultipleTokens(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    ERL_NIF_TERM token = ParseSingleToken(env, it.value_begin(),
        it.value_end());
    if (enif_is_atom(env, token))
      return token;
    result = enif_make_list_cell(env, token, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseMultipleTokenParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    ERL_NIF_TERM value = ParseSingleTokenParams(env, it.value_begin(),
        it.value_end());
    if (enif_is_atom(env, value))
      return value;
    result = enif_make_list_cell(env, value, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseSingleTypeSubtypeParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  ERL_NIF_TERM value = ParseTypeSubtype(env, &tok);
  if (enif_is_atom(env, value))
    return value;
  ERL_NIF_TERM parameters = ParseParameters(env, &tok);
  if (enif_is_atom(env, parameters))
    return parameters;
  return enif_make_tuple2(env, value, parameters);
}

ERL_NIF_TERM ParseMultipleTypeSubtypeParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    ERL_NIF_TERM value = ParseSingleTypeSubtypeParams(env, it.value_begin(),
        it.value_end());
    if (enif_is_atom(env, value))
      return value;
    result = enif_make_list_cell(env, value, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseMultipleUriParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    ERL_NIF_TERM uri = ParseUri(env, &tok);
    if (enif_is_atom(env, uri))
      return uri;
    ERL_NIF_TERM parameters = ParseParameters(env, &tok);
    if (enif_is_atom(env, parameters))
      return parameters;
    result = enif_make_list_cell(env,
        enif_make_tuple2(env, uri, parameters), result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseSingleInteger(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  std::string::const_iterator token_start = tok.Skip(SIP_LWS);
  std::string digits(token_start, tok.SkipNotIn(SIP_LWS));
  int i = 0;
  if (!StringToInt(digits, &i))
    return enif_make_atom(env, "invalid_digits");
  return enif_make_int(env, i);
}

ERL_NIF_TERM ParseOnlyAuthParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  return ParseAuthParams(env, &tok);
}

ERL_NIF_TERM ParseSchemeAndAuthParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  ERL_NIF_TERM scheme = ParseAuthScheme(env, &tok);
  if (enif_is_atom(env, scheme))
    return scheme;
  ERL_NIF_TERM parameters = ParseAuthParams(env, &tok);
  if (enif_is_atom(env, parameters))
    return parameters;
  return enif_make_list1(env,
      enif_make_tuple2(env, scheme, parameters));
}

ERL_NIF_TERM ParseSingleContactParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  ERL_NIF_TERM contact = ParseContact(env, &tok);
  if (enif_is_atom(env, contact))
    return contact;
  ERL_NIF_TERM parameters = ParseParameters(env, &tok);
  if (enif_is_atom(env, parameters))
    return parameters;
  int arity;
  const ERL_NIF_TERM *name_and_address;
  enif_get_tuple(env, contact, &arity, &name_and_address);
  return enif_make_tuple3(env, name_and_address[0], name_and_address[1],
      parameters);
}

ERL_NIF_TERM ParseMultipleContactParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    ERL_NIF_TERM value = ParseSingleContactParams(env, it.value_begin(),
        it.value_end());
    if (enif_is_atom(env, value))
      return value;
    result = enif_make_list_cell(env, value, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseStarOrMultipleContactParams(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  ERL_NIF_TERM star;
  if (ParseStar(env, &tok, &star)) {
    return star;
  } else {
    return ParseMultipleContactParams(env, values_begin, values_end);
  }
}

ERL_NIF_TERM ParseTrimmedUtf8(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  TrimLWS(&values_begin, &values_end);
  return MakeString(env, StringPiece(values_begin, values_end));
}

ERL_NIF_TERM ParseCseq(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  std::string::const_iterator integer_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput())
    return enif_make_atom(env, "missing_sequence");
  std::string integer_string(integer_start, tok.SkipNotIn(SIP_LWS));
  int sequence = 0;
  if (!StringToInt(integer_string, &sequence))
    return enif_make_atom(env, "invalid_sequence");
  std::string::const_iterator method_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput())
    return enif_make_atom(env, "missing_method");
  StringPiece method_name(method_start, tok.SkipNotIn(SIP_LWS));
  return enif_make_tuple2(env, enif_make_int(env, sequence),
      MakeLowerCaseExistingAtomOrString(env, method_name));
}

ERL_NIF_TERM ParseDate(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  TrimLWS(&values_begin, &values_end);
  if (values_begin == values_end)
    return enif_make_atom(env, "empty_date");

  PRExplodedTime result_time;
  std::string time_string(StringPiece(values_begin, values_end).as_string());
  PRStatus status = PR_ParseTimeStringToExplodedTime(time_string.c_str(),
      PR_TRUE, &result_time);
  if (PR_SUCCESS != status)
    return enif_make_atom(env, "invalid_date");

  PR_NormalizeTime(&result_time, &PR_GMTParameters);

  ERL_NIF_TERM result = enif_make_tuple3(env,
      enif_make_tuple3(env,
        enif_make_int(env, result_time.tm_year),
        enif_make_int(env, result_time.tm_month + 1),
        enif_make_int(env, result_time.tm_mday)),
      enif_make_tuple3(env,
        enif_make_int(env, result_time.tm_hour),
        enif_make_int(env, result_time.tm_min),
        enif_make_int(env, result_time.tm_sec)),
      enif_make_tuple2(env,
          enif_make_int(env, result_time.tm_usec),
          enif_make_int(env, result_time.tm_usec == 0 ? 0 : 5)));
  return result;
}

ERL_NIF_TERM ParseTimestamp(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  std::string::const_iterator timestamp_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput())
    return enif_make_atom(env, "missing_timestamp");
  StringPiece timestamp_string(timestamp_start, tok.SkipNotIn(SIP_LWS));
  double timestamp = .0;
  if (!StringToDouble(timestamp_string, &timestamp))
    return enif_make_atom(env, "invalid_timestamp");
  // delay is optional
  double delay = .0;
  std::string::const_iterator delay_start = tok.Skip(SIP_LWS);
  if (!tok.EndOfInput()) {
    StringPiece delay_string(delay_start, tok.SkipNotIn(SIP_LWS));
    StringToDouble(delay_string, &delay);
    // ignore errors parsing the optional delay
  }
  return enif_make_tuple2(env, enif_make_double(env, timestamp),
      enif_make_double(env, delay));
}

ERL_NIF_TERM ParseMimeVersion(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  std::string::const_iterator major_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput())
    return enif_make_atom(env, "missing_major");
  StringPiece major_string(major_start, tok.SkipTo('.'));
  int major = 0;
  if (major_string.empty()
      || !StringToInt(major_string, &major))
    return enif_make_atom(env, "missing_or_invalid_major");
  tok.Skip();
  std::string::const_iterator minor_start = tok.Skip(SIP_LWS);
  StringPiece minor_string(minor_start, tok.end());
  int minor = 0;
  if (minor_string.empty()
      || !StringToInt(minor_string, &minor))
    return enif_make_atom(env, "invalid_minor");
  return enif_make_tuple2(env, enif_make_int(env, major),
      enif_make_int(env, minor));
}

ERL_NIF_TERM ParseRetryAfter(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  Tokenizer tok(values_begin, values_end);
  std::string::const_iterator delta_start = tok.Skip(SIP_LWS);
  if (tok.EndOfInput())
    return enif_make_atom(env, "missing_delta_secs");
  StringPiece delta_string(delta_start, tok.SkipNotIn(SIP_LWS "(;"));
  int delta_seconds = 0;
  if (delta_string.empty()
      || !StringToInt(delta_string, &delta_seconds))
    return enif_make_atom(env, "missing_or_invalid_delta_secs");

  ERL_NIF_TERM comment;
  StringPiece remaining(tok.current(), tok.end());
  if (remaining.find('(') < remaining.find(';')) {
    comment = ParseComment(env, &tok);
    if (enif_is_atom(env, comment))
      return comment;
  } else {
    comment = MakeString(env, "");
  }

  ERL_NIF_TERM parameters;
  tok.SkipTo(';');
  if (!tok.EndOfInput()) {
    parameters = ParseParameters(env, &tok);
    if (enif_is_atom(env, parameters))
      return parameters;
  } else {
    parameters = enif_make_new_map(env);
  }

  return enif_make_tuple3(env, enif_make_int(env, delta_seconds), comment,
      parameters);
}

ERL_NIF_TERM ParseMultipleWarnings(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    ERL_NIF_TERM value = ParseWarning(env, &tok);
    if (enif_is_atom(env, value))
      return value;
    result = enif_make_list_cell(env, value, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseMultipleVias(ErlNifEnv* env,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM result = enif_make_list(env, 0);
  ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    ERL_NIF_TERM value = ParseVia(env, &tok);
    if (enif_is_atom(env, value))
      return value;
    ERL_NIF_TERM parameters = ParseParameters(env, &tok);
    if (enif_is_atom(env, parameters))
      return parameters;
    int arity;
    const ERL_NIF_TERM *via;
    enif_get_tuple(env, value, &arity, &via);
    ERL_NIF_TERM term = enif_make_tuple4(env, via[0], via[1], via[2],
        parameters);
    result = enif_make_list_cell(env, term, result);
  }
  enif_make_reverse_list(env, result, &result);
  return result;
}

ERL_NIF_TERM ParseHeader(ErlNifEnv* env,
    std::string::const_iterator name_begin,
    std::string::const_iterator name_end,
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  ERL_NIF_TERM header_name_term = 0, header_values_term;
  StringPiece header_name(name_begin, name_end);
  StringPiece header_values(values_begin, values_end);
  if (header_name.size() == 1) {
    auto alias = g_aliases.find(ToLowerASCII(header_name[0]));
    if (alias != g_aliases.end()) {
      header_name_term = alias->second;
    }
  }
  if (header_name_term == 0) {
    MakeLowerCaseExistingAtom(env, header_name, &header_name_term);
  }
  auto f = g_parsers.find(header_name_term);
  if (f != g_parsers.end()) {
    header_values_term = (f->second)(env, values_begin, values_end);
    if (enif_is_atom(env, header_values_term))
      return header_values_term;
  } else {
    header_name_term = MakeString(env, header_name);
    header_values_term = enif_make_list1(env, MakeString(env, header_values));
  }
  return enif_make_tuple2(env, header_name_term, header_values_term);
}

bool AssembleRawHeaders(const char* input, size_t length,
    std::string *output) {
  const char* line_start;
  const char* line_end;

  output->reserve(length);
  for (size_t i = 0; i < length; i++) {
    line_start = input + i;
    do {
      char c = *(input + i);
      if (c == '\r' || c == '\n')
        break;
      i++;
    } while (i < length);
    line_end = input + i;
    if (line_start != line_end)
      output->append(line_start, line_end);
    if (i == length)
      break;
    // now inspect the next character
    char c = *(input + i);
    if (c == '\n') {
      i++;  // accept single LF
    } else if (c == '\r') {
      i++;
      if (i < length && *(input + i) == '\n')
        i++;  // default CRLF sequence
      else
        return false;  // invalid CRLF sequence
    }
    if (i == length)
      break;
    if (!IsLWS(*(input + i)))
      output->append(1, '\n');  // not line folding
    i--;  // return next character back
  }

  return true;
}

ERL_NIF_TERM Parse(ErlNifEnv* env, const char* raw_message, size_t length) {
  std::string input;
  if (!AssembleRawHeaders(raw_message, length, &input)) {
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
        enif_make_atom(env, "invalid_line_break"));
  }

  ERL_NIF_TERM message = enif_make_new_map(env);
  std::string::const_iterator i = input.begin();
  std::string::const_iterator end = input.end();
  std::string::const_iterator start = i;

  ERL_NIF_TERM start_line;
  
  i = FindLineEnd(start, end);
  if (IsStatusLine(start, i)) {
    start_line = ParseStatusLine(env, start, i);
  } else {
    start_line = ParseRequestLine(env, start, i);
  }

  if (enif_is_atom(env, start_line))
    return start_line;
  enif_make_map_put(env, message, enif_make_atom(env, "start_line"),
      start_line, &message);

  // Jump over next CRLF
  if (i != end) {
    if (*i == '\r')
      ++i;
    if (i != end && *i == '\n')
      ++i;
  }

  HeadersIterator it(i, end, "\r\n");
  ERL_NIF_TERM headers = enif_make_new_map(env);
  while (it.GetNext()) {
    ERL_NIF_TERM header = ParseHeader(env, it.name_begin(), it.name_end(),
        it.values_begin(), it.values_end());
    if (enif_is_atom(env, header))
      return enif_make_tuple2(env, enif_make_atom(env, "error"),
          header);

    int arity;
    const ERL_NIF_TERM* pair;
    if (enif_get_tuple(env, header, &arity, &pair) && arity == 2) {
      ERL_NIF_TERM header_name = pair[0], header_values = pair[1];

      ERL_NIF_TERM adding_header_values;
      if (enif_get_map_value(env, headers, header_name,
            &adding_header_values)) {
        if (!enif_is_list(env, adding_header_values)) {
          return enif_make_tuple2(env, enif_make_atom(env, "error"),
              enif_make_atom(env, "multiple_definition"));
        }
        enif_make_reverse_list(env, adding_header_values,
            &adding_header_values);
        ERL_NIF_TERM head, tail = header_values;
        while (enif_get_list_cell(env, tail, &head, &tail)) {
          adding_header_values = enif_make_list_cell(env, head,
              adding_header_values);
        }
        enif_make_reverse_list(env, adding_header_values,
            &adding_header_values);
      } else {
        adding_header_values = header_values;
      }
      enif_make_map_put(env, headers, header_name, adding_header_values,
          &headers);
    }
  }

  enif_make_reverse_list(env, headers, &headers);

  enif_make_map_put(env, message, enif_make_atom(env, "headers"), headers,
      &message);

  return enif_make_tuple2(env, enif_make_atom(env, "ok"), message);
}

void LoadMethodAtoms(ErlNifEnv* env) {
#define SIP_METHOD(x) \
  enif_make_atom(env, ToLowerASCII(#x).c_str());
#include "method_list.h"
#undef SIP_METHOD
}

void LoadHeaderNameAtoms(ErlNifEnv* env) {
  ERL_NIF_TERM atom;
#define X(header_name, compact_name, atom_name, format) \
  atom = enif_make_atom(env, #atom_name); \
  g_parsers.insert(std::make_pair(atom, &Parse##format)); \
  if (compact_name != 0) \
    g_aliases.insert(std::make_pair(compact_name, atom));
#include "header_list.h"
#undef X
}

void LoadProtocolAtoms(ErlNifEnv* env) {
#define SIP_PROTOCOL(x) \
  enif_make_atom(env, ToLowerASCII(#x).c_str());
#include "protocol_list.h"
#undef SIP_PROTOCOL
}

}  // namespace

extern "C" {

static ERL_NIF_TERM parse_wrapper(ErlNifEnv* env, int argc,
    const ERL_NIF_TERM argv[]) {
  if (argc != 1) {
    return enif_make_badarg(env);
  } else if (enif_is_binary(env, argv[0])) {
    ErlNifBinary bin;
    enif_inspect_binary(env, argv[0], &bin);
    return Parse(env, reinterpret_cast<const char*>(bin.data),
        static_cast<size_t>(bin.size));
  } else {
    return enif_make_badarg(env);
  }
}

int on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
  LoadMethodAtoms(env);
  LoadHeaderNameAtoms(env);
  LoadProtocolAtoms(env);
  return 0;
}

static ErlNifFunc nif_funcs[] = {
  {"parse", 1, parse_wrapper},
};

ERL_NIF_INIT(Elixir.Sippet.Parser, nif_funcs, on_load, NULL, NULL, NULL)

}  // extern "C"

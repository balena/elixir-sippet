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

ERL_NIF_TERM kRequestLineTerm = 0;
ERL_NIF_TERM kStatusLineTerm = 0;

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
  for (size_t i = 0; i < s.size(); i++)
    bin.data[i] = s[i];
  return enif_make_binary(env, &bin);
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
    return enif_make_atom(env, "missing_status_line");
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
  enif_make_map_put(env, status_line, enif_make_atom(env, "__struct__"),
      kStatusLineTerm, &status_line);
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
  enif_make_map_put(env, request_line, enif_make_atom(env, "__struct__"),
      kRequestLineTerm, &request_line);
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

  return enif_make_tuple2(env, MakeString(env, type),
      MakeString(env, subtype));
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
    enif_make_map_put(env, result, MakeString(env, it.name()),
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
        MakeString(env, it.raw_value()), &result);
  }
  return result;
}

#if 0
template<class HeaderType>
bool ParseUri(Tokenizer* tok, std::unique_ptr<HeaderType>* header) {
  tok->SkipTo('<');
  if (tok->EndOfInput()) {
    DVLOG(1) << "invalid uri";
    return false;
  }
  std::string::const_iterator uri_start = tok->Skip();
  std::string::const_iterator uri_end = tok->SkipTo('>');
  if (tok->EndOfInput()) {
    DVLOG(1) << "unclosed '<'";
    return false;
  }
  tok->Skip();
  std::string uri(uri_start, uri_end);
  (*header)->push_back(typename HeaderType::value_type(GURL(uri)));
  return true;
}

template<class HeaderType, typename Builder>
bool ParseContact(Tokenizer* tok, std::unique_ptr<HeaderType>* header,
    Builder builder) {
  std::string display_name;
  GURL address;
  tok->Skip(SIP_LWS);
  if (net::HttpUtil::IsQuote(*tok->current())) {
    // contact-param = quoted-string LAQUOT addr-spec RAQUOT
    std::string::const_iterator display_name_start = tok->current();
    tok->Skip();
    for (; !tok->EndOfInput(); tok->Skip()) {
      if (*tok->current() == '\\') {
        tok->Skip();
        continue;
      }
      if (net::HttpUtil::IsQuote(*tok->current()))
        break;
    }
    if (tok->EndOfInput()) {
      DVLOG(1) << "unclosed quoted-string";
      return false;
    }
    display_name.assign(display_name_start, tok->Skip());
    tok->SkipTo('<');
    if (tok->EndOfInput()) {
      DVLOG(1) << "missing address";
      return false;
    }
    std::string::const_iterator address_start = tok->Skip();
    tok->SkipTo('>');
    if (tok->EndOfInput()) {
      DVLOG(1) << "unclosed '<'";
      return false;
    }
    address = GURL(std::string(address_start, tok->current()));
  } else {
    Tokenizer laquot(tok->current(), tok->end());
    laquot.SkipTo('<');
    if (!laquot.EndOfInput()) {
      // contact-param = *(token LWS) LAQUOT addr-spec RAQUOT
      display_name.assign(tok->current(), laquot.current());
      base::TrimString(display_name, SIP_LWS, &display_name);
      std::string::const_iterator address_start = laquot.Skip();
      laquot.SkipTo('>');
      if (laquot.EndOfInput()) {
        DVLOG(1) << "unclosed '<'";
        return false;
      }
      address = GURL(std::string(address_start, laquot.current()));
      tok->set_current(laquot.Skip());
    } else if (net::HttpUtil::IsToken(tok->current(), tok->current()+1)) {
      std::string::const_iterator address_start = tok->current();
      address = GURL(std::string(address_start, tok->SkipNotIn(SIP_LWS ";")));
    } else {
      DVLOG(1) << "invalid char found";
      return false;
    }
  }

  display_name = net::HttpUtil::Unquote(display_name);
  builder(header, address, display_name);
  return true;
}

template<class HeaderType>
bool ParseStar(Tokenizer* tok, std::unique_ptr<HeaderType>* header) {
  Tokenizer star(tok->current(), tok->end());
  star.Skip(SIP_LWS);
  if (star.EndOfInput())
    return false;
  if (*star.current() != '*')
    return false;
  header->reset(new HeaderType(HeaderType::All));
  return true;
}

template<class HeaderType, typename Builder>
bool ParseWarning(Tokenizer* tok, std::unique_ptr<HeaderType>* header,
    Builder builder) {
  std::string::const_iterator code_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    DVLOG(1) << "empty input";
    return false;
  }
  std::string code_string(code_start, tok->SkipNotIn(SIP_LWS));
  int code = 0;
  if (!base::StringToInt(code_string, &code)
      || code < 100 || code > 999) {
    DVLOG(1) << "invalid code";
    return false;
  }
  std::string::const_iterator agent_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    DVLOG(1) << "empty warn-agent";
    return false;
  }
  std::string agent(agent_start, tok->SkipNotIn(SIP_LWS));
  tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    DVLOG(1) << "missing warn-text";
    return false;
  }
  if (!net::HttpUtil::IsQuote(*tok->current())) {
    DVLOG(1) << "invalid warn-text";
    return false;
  }
  std::string::const_iterator text_start = tok->current();
  tok->Skip();
  for (; !tok->EndOfInput(); tok->Skip()) {
    if (*tok->current() == '\\') {
      tok->Skip();
      continue;
    }
    if (net::HttpUtil::IsQuote(*tok->current()))
      break;
  }
  if (tok->EndOfInput()) {
    DVLOG(1) << "unclosed quoted-string";
    return false;
  }
  std::string text(text_start, tok->Skip());
  text = net::HttpUtil::Unquote(text);
  builder(header, static_cast<unsigned>(code), agent, text);
  return true;
}

template<class HeaderType, typename Builder>
bool ParseVia(Tokenizer* tok, std::unique_ptr<HeaderType>* header,
    Builder builder) {
  std::string::const_iterator version_start = tok->Skip(SIP_LWS);
  if ((tok->end() - tok->current() < 3)
      || !LowerCaseEqualsASCII(
          base::StringPiece(tok->current(), tok->current() + 3), "sip")) {
    DVLOG(1) << "unknown SIP-version";
    return false;
  }
  tok->SkipTo('/');
  tok->Skip();
  if (tok->EndOfInput()) {
    DVLOG(1) << "missing SIP-version";
    return false;
  }
  Version version = ParseVersion(version_start, tok->SkipTo('/'));
  if (version < Version(2, 0)) {
    DVLOG(1) << "invalid SIP-version";
    return false;
  }
  std::string::const_iterator protocol_start = tok->Skip();
  if (tok->EndOfInput()) {
    DVLOG(1) << "missing sent-protocol";
    return false;
  }
  std::string protocol(protocol_start, tok->SkipNotIn(SIP_LWS));
  protocol = base::ToUpperASCII(protocol);
  std::string::const_iterator sentby_start = tok->Skip(SIP_LWS);
  if (tok->EndOfInput()) {
    DVLOG(1) << "missing sent-by";
    return false;
  }
  std::string sentby_string(sentby_start, tok->SkipTo(';'));
  base::TrimString(sentby_string, SIP_LWS, &sentby_string);
  if (sentby_string.empty()) {
    DVLOG(1) << "missing sent-by";
    return false;
  }
  std::string host;
  int port;
  if (!net::ParseHostAndPort(sentby_string, &host, &port)) {
    DVLOG(1) << "invalid sent-by";
    return false;
  }
  if (port == -1) {
    if (protocol == "UDP" || protocol == "TCP")
      port = 5060;
    else if (protocol == "TLS")
      port = 5061;
    else
      port = 0;
  }
  if (host[0] == '[')  // remove brackets from IPv6 addresses
    host = host.substr(1, host.size()-2);
  net::HostPortPair sentby(host, port);
  builder(header, version, protocol, sentby);
  return true;
}
#endif

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

#if 0
template<class HeaderType>
std::unique_ptr<Header> ParseMultipleUriParams(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval(new HeaderType);
  net::HttpUtil::ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    if (!ParseUri(&tok, &retval)
        || !ParseParameters(&tok, &retval, MultipleParamSetter<HeaderType>()))
      return std::unique_ptr<Header>();
  }
  return std::move(retval);
}
#endif

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
  return enif_make_tuple2(env, scheme, parameters);
}

#if 0
template<class HeaderType>
std::unique_ptr<Header> ParseSingleContactParams(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval;
  Tokenizer tok(values_begin, values_end);
  if (!ParseContact(&tok, &retval, SingleBuilder<HeaderType>())
      || !ParseParameters(&tok, &retval, SingleParamSetter<HeaderType>()))
    return std::unique_ptr<Header>();
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseMultipleContactParams(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval(new HeaderType);
  net::HttpUtil::ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    if (!ParseContact(&tok, &retval, MultipleBuilder<HeaderType>())
        || !ParseParameters(&tok, &retval, MultipleParamSetter<HeaderType>()))
      return std::unique_ptr<Header>();
  }
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseStarOrMultipleContactParams(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval(new HeaderType);
  net::HttpUtil::ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    if (!ParseStar(&tok, &retval)) {
      if (!ParseContact(&tok, &retval, MultipleBuilder<HeaderType>())
          || !ParseParameters(&tok, &retval, MultipleParamSetter<HeaderType>()))
        return std::unique_ptr<Header>();
    }
  }
  return std::move(retval);
}
#endif

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
  ERL_NIF_TERM method_term;
  if (!MakeLowerCaseExistingAtom(env, method_name, &method_term))
    return enif_make_atom(env, "unknown_method");
  return enif_make_tuple2(env, enif_make_int(env, sequence),
      method_term);
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

  ERL_NIF_TERM result = enif_make_new_map(env);
  enif_make_map_put(env, result, enif_make_atom(env, "__struct__"),
      enif_make_atom(env, "Elixir.DateTime"), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "calendar"),
      enif_make_atom(env, "Elixir.Calendar.ISO"), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "year"),
      enif_make_int(env, result_time.tm_year), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "month"),
      enif_make_int(env, result_time.tm_month + 1), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "day"),
      enif_make_int(env, result_time.tm_mday), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "hour"),
      enif_make_int(env, result_time.tm_hour), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "minute"),
      enif_make_int(env, result_time.tm_min), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "second"),
      enif_make_int(env, result_time.tm_sec), &result);
  if (result_time.tm_usec == 0) {
    enif_make_map_put(env, result, enif_make_atom(env, "microsecond"),
        enif_make_tuple2(env, enif_make_int(env, 0), enif_make_int(env, 0)),
        &result);
  } else {
    enif_make_map_put(env, result, enif_make_atom(env, "microsecond"),
        enif_make_tuple2(env,
          enif_make_int(env, result_time.tm_usec),
          enif_make_int(env, 5)),
        &result);
  }
  enif_make_map_put(env, result, enif_make_atom(env, "std_offset"),
      enif_make_int(env, 0), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "utc_offset"),
      enif_make_int(env, result_time.tm_params.tp_gmt_offset), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "time_zone"),
      MakeString(env, "Etc/UTC"), &result);
  enif_make_map_put(env, result, enif_make_atom(env, "zone_abbr"),
      MakeString(env, "UTC"), &result);
  return result;
}

#if 0
template<class HeaderType>
std::unique_ptr<Header> ParseTimestamp(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval;
  Tokenizer tok(values_begin, values_end);
  do {
    std::string::const_iterator timestamp_start = tok.Skip(SIP_LWS);
    if (tok.EndOfInput()) {
      DVLOG(1) << "missing timestamp";
      break;
    }
    std::string timestamp_string(timestamp_start, tok.SkipNotIn(SIP_LWS));
    double timestamp = .0;
    if (!base::StringToDouble(timestamp_string, &timestamp)) {
      DVLOG(1) << "invalid timestamp";
      break;
    }
    // delay is optional
    double delay = .0;
    std::string::const_iterator delay_start = tok.Skip(SIP_LWS);
    if (!tok.EndOfInput()) {
      std::string delay_string(delay_start, tok.SkipNotIn(SIP_LWS));
      base::StringToDouble(delay_string, &delay);
      // ignore errors parsing the optional delay
    }
    retval.reset(new HeaderType(timestamp, delay));
  } while (false);
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseMimeVersion(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval;
  Tokenizer tok(values_begin, values_end);
  do {
    std::string::const_iterator major_start = tok.Skip(SIP_LWS);
    if (tok.EndOfInput()) {
      DVLOG(1) << "missing major";
      break;
    }
    std::string major_string(major_start, tok.SkipTo('.'));
    int major = 0;
    if (major_string.empty()
        || !base::StringToInt(major_string, &major)) {
      DVLOG(1) << "missing or invalid major";
      break;
    }
    tok.Skip();
    std::string::const_iterator minor_start = tok.Skip(SIP_LWS);
    std::string minor_string(minor_start, tok.end());
    int minor = 0;
    if (minor_string.empty()
        || !base::StringToInt(minor_string, &minor)) {
      DVLOG(1) << "invalid minor";
      break;
    }
    retval.reset(new HeaderType(static_cast<unsigned>(major),
                                static_cast<unsigned>(minor)));
  } while (false);
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseRetryAfter(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval;
  Tokenizer tok(values_begin, values_end);
  do {
    std::string::const_iterator delta_start = tok.Skip(SIP_LWS);
    if (tok.EndOfInput()) {
      DVLOG(1) << "missing delta-seconds";
      break;
    }
    std::string delta_string(delta_start, tok.SkipNotIn(SIP_LWS "(;"));
    int delta_seconds = 0;
    if (delta_string.empty()
        || !base::StringToInt(delta_string, &delta_seconds)) {
      DVLOG(1) << "missing or invalid delta-seconds";
      break;
    }
    retval.reset(new HeaderType(static_cast<unsigned>(delta_seconds)));
    // ignoring comments
    tok.SkipTo(';');
    if (!tok.EndOfInput()) {
      ParseParameters(&tok, &retval, SingleParamSetter<HeaderType>());
    }
  } while (false);
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseMultipleWarnings(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval(new HeaderType);
  net::HttpUtil::ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    if (!ParseWarning(&tok, &retval, MultipleBuilder<HeaderType>())) {
      return std::unique_ptr<Header>();
    }
  }
  return std::move(retval);
}

template<class HeaderType>
std::unique_ptr<Header> ParseMultipleVias(
    std::string::const_iterator values_begin,
    std::string::const_iterator values_end) {
  std::unique_ptr<HeaderType> retval(new HeaderType);
  net::HttpUtil::ValuesIterator it(values_begin, values_end, ',');
  while (it.GetNext()) {
    Tokenizer tok(it.value_begin(), it.value_end());
    if (!ParseVia(&tok, &retval, MultipleBuilder<HeaderType>())
        || !ParseParameters(&tok, &retval, MultipleParamSetter<HeaderType>())) {
      return std::unique_ptr<Header>();
    }
  }
  return std::move(retval);
}
#endif

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
  } else {
    header_name_term = MakeString(env, header_name);
    header_values_term = enif_make_list1(env, MakeString(env, header_values));
  }
  return enif_make_tuple2(env, header_name_term, header_values_term);
}

bool AssembleRawHeaders(const std::string &input, std::string *output) {
  Tokenizer tok(input.begin(), input.end());
  std::string::const_iterator line_start, line_end;

  output->reserve(input.size());
  for (;;) {
    line_start = tok.current();
    line_end = tok.SkipNotIn("\r\n");
    if (line_start != line_end)
      output->append(line_start, line_end);
    if (tok.EndOfInput())
      break;
    if (*tok.current() == '\n') {
      tok.Skip();  // accept single LF
    } else if (*tok.current() == '\r') {
      tok.Skip();
      if (*tok.current() == '\n')
        tok.Skip();  // default CRLF sequence
      else
        return false;  // invalid CRLF sequence
    }
    if (tok.EndOfInput())
      break;
    if (!IsLWS(*tok.current()))
      output->append(1, '\n');  // not line folding
  }

  return true;
}

ERL_NIF_TERM Parse(ErlNifEnv* env, const std::string& raw_message) {
  std::string input;
  if (!AssembleRawHeaders(raw_message, &input)) {
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
        enif_make_atom(env, "invalid_line_break"));
  }

  ERL_NIF_TERM message = enif_make_new_map(env);
  std::string::const_iterator i = input.begin();
  std::string::const_iterator end = input.end();
  std::string::const_iterator start = i;

  i = FindLineEnd(start, end);
  if (IsStatusLine(start, i)) {
    ERL_NIF_TERM status_line = ParseStatusLine(env, start, i);
    if (enif_is_atom(env, status_line))
      return status_line;
    enif_make_map_put(env, message, enif_make_atom(env, "status_line"),
        status_line, &message);
  } else {
    ERL_NIF_TERM request_line = ParseRequestLine(env, start, i);
    if (enif_is_atom(env, request_line))
      return request_line;
    enif_make_map_put(env, message, enif_make_atom(env, "request_line"),
        request_line, &message);
  }

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
#define X(class_name, compact_name, header_name, enum_name, format) \
  atom = enif_make_atom(env, ToLowerASCII(#enum_name).c_str()); \
  g_parsers.insert(std::make_pair(atom, &Parse##format)); \
  if (compact_name != 0) \
    g_aliases.insert(std::make_pair(compact_name, atom));
#include "header_list.h"
#undef X
}

void LoadMessageAtoms(ErlNifEnv* env) {
  enif_make_existing_atom(env, "Elixir.Sippet.Message.RequestLine",
      &kRequestLineTerm, ERL_NIF_LATIN1);
  enif_make_existing_atom(env, "Elixir.Sippet.Message.StatusLine",
      &kStatusLineTerm, ERL_NIF_LATIN1);
}

}  // namespace

extern "C" {

static ERL_NIF_TERM parse_wrapper(ErlNifEnv* env, int argc,
    const ERL_NIF_TERM argv[]) {
  unsigned int length;
  if (!enif_get_list_length(env, argv[0], &length)) {
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
        enif_make_atom(env, "bad_arg"));
  }

  std::string raw_message;
  raw_message.resize(length + 1);
  if (enif_get_string(env, argv[0], &(*raw_message.begin()),
        raw_message.size(), ERL_NIF_LATIN1) < 1) {
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
        enif_make_atom(env, "bad_arg"));
  }
  raw_message.resize(length);

  return Parse(env, raw_message);
}

int on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
  LoadMethodAtoms(env);
  LoadHeaderNameAtoms(env);
  LoadMessageAtoms(env);
  return 0;
}

static ErlNifFunc nif_funcs[] = {
  {"parse", 1, parse_wrapper},
};

ERL_NIF_INIT(Elixir.Sippet.Parser, nif_funcs, on_load, NULL, NULL, NULL)

}  // extern "C"

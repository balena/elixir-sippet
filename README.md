![Sippet](http://sippet.github.io/sippet/public/apple-touch-icon-144-precomposed.png)
=========

[![Build Status](https://travis-ci.org/balena/elixir-sippet.svg)](https://travis-ci.org/balena/elixir-sippet)
[![Coverage Status](https://coveralls.io/repos/github/balena/elixir-sippet/badge.svg?branch=master)](https://coveralls.io/github/balena/elixir-sippet?branch=master)
[![Docs Status](https://inch-ci.org/github/balena/elixir-sippet.svg?branch=master)](http://inch-ci.org/github/balena/elixir-sippet)
[![Hex version](https://img.shields.io/hexpm/v/sippet.svg "Hex version")](https://hex.pm/packages/sippet)
[![Hex.pm](https://img.shields.io/hexpm/l/sippet.svg "BSD Licensed")](https://github.com/balena/elixir-sippet/blob/master/LICENSE)
[![Code Triagers Badge](https://www.codetriage.com/balena/elixir-sippet/badges/users.svg)](https://www.codetriage.com/balena/elixir-sippet)

An Elixir library designed to write Session Initiation Protocol middleware.


# Introduction

[SIP](https://tools.ietf.org/html/rfc3261) is a very flexible protocol that has
great depth. It was designed to be a general-purpose way to set up real-time
multimedia sessions between groups of participants. It is a text-based protocol
modeled on the request/response model used in HTTP. This makes it easy to debug
because the messages are relatively easy to construct and easy to see.

Sippet is designed as a simple SIP middleware library, aiming the developer to
write any kind of function required to register users, get their availability,
check capabilities, setup and manage sessions. On the other hand, Sippet does
not intend to provide any feature available in a fully functional SIP UAC/UAS,
proxy server, B2BUA, SBC or application; instead, it has only the essential
building blocks to build any kind of SIP middleware.


## Overview

One of the most central parts of Sippet is the `Sippet.Message`. Instead of
many headers that you end up having to parse by yourself, there's an internal
parser written in C++ (an Erlang NIF) that does all the hard work for you. This
way, the `Sippet.Message.headers` is a key-value simple `Map` where the key is
the header name, and the value varies accordingly the header type. For
instance, the header `:cseq` has the form `{sequence :: integer, method}` where
the `method` is an atom with the method name (like `:invite`).

Message routing is performed just manipulating `Sippet.Message` headers;
everything else is performed by these layers in a very standard way. That means
you may not be able to build some non-standard behaviors, like routing the
message to a given host that wasn't correctly added to the topmost Via header.

As Sippet is a simple SIP library, the developer has to understand the protocol
very well before writing a middleware. This design decision came up because all
attempts to hide any inherent SIP complexity by other frameworks have failed.

There is no support for plugins or hooks, these case be implemented easily with
Elixir behaviors and macros, and the developer may custom as he likes. Incoming
messages and transport errors are directed to a `Sippet.Core` module behavior.

Finally, there is no support for many different transport protocols; a simple
`Sippet.Transports.UDP` implementation is provided, which is enough for general
purpose SIP middleware. Transport protocols can be implemented quite easily
using the same logic of `Sippet.Transport.UDP`.


## Installation

The package can be installed from [Hex](https://hex.pm/docs/publish) as:

  1. Add `sippet` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:sippet, "~> 1.0"}]
end
```

  2. Give a name to your stack and build it:

```elixir
# Creates a :mystack Sippet instance
Sippet.start_link(name: :mystack)

# The below will create a default UDP transport listening on 0.0.0.0:5060/udp
Sippet.Transports.UDP.start_link(name: :mystack)
```

  4. Create a `Sippet.Core` and register it:

```elixir
defmodule MyCore do
  use Sippet.Core

  def receive_request(incoming_request, server_key) do
    # route the request to your UA or proxy process
  end

  def receive_response(incoming_response, client_key) do
    # route the response to your UA or proxy process
  end

  def receive_error(reason, client_or_server_key) do
    # route the error to your UA or proxy process
  end
end

Sippet.register_core(:mystack, MyCore)
```

Voilà! The SIP stack will be listening on the indicated address and port, and
your `MyCore` module will receive callbacks from it whenever a SIP message
arrives on it.

You may send messages this way:

```elixir
request = %Message{
  start_line: RequestLine.new(:options, "sip:sip.example.com"),
  headers: %{
    via: [
      {{2, 0}, :udp, {"localhost", 5060}, %{"branch" => Message.create_branch()}}
    ],
    from: {"", URI.parse!("sip:localhost"), %{"tag" => Message.create_tag()}},
    to: {"", URI.parse!("sip:sip.example.com"), %{}},
    cseq: {1, :options},
    user_agent: "Sippet/1.0",
    call_id: Message.create_call_id()
  }
}

Sippet.send(:sippet, request)
```

If you prefer to specify messages directly in wire format, here you go:

```elixir
request =
  """
  OPTIONS sip:sip.example.com SIP/2.0
  Via: SIP/2.0/UDP localhost:5060;branch=#{Message.create_branch()}
  From: sip:localhost;tag=#{Message.create_tag()}
  To: sip:sip.example.com
  CSeq: 1 OPTIONS
  User-Agent: Sippet/1.0
  Call-ID: #{Message.create_call_id()}
  """ |> Message.parse!()

Sippet.send(:sippet, request)
```

Further documentation can found at
[https://hexdocs.pm/sippet](https://hexdocs.pm/sippet).


## Headers format

```elixir
# Definitions
# ======================================================================================
@type type :: String.t
@type subtype :: String.t
@type token :: String.t
@type name :: String.t
@type scheme :: String.t
@type parameters :: %{String.t => String.t}
@type uri :: Sippet.URI.t
@type major :: integer
@type minor :: integer
@type display_name :: String.t
@type string :: String.t
@type timestamp :: double
@type delay :: double
@type protocol :: atom | String.t
@type method :: atom | String.t


# Header Name             Type
# ======================================================================================
@type headers :: %{
  :accept              => [{{type, subtype}, parameters}, ...],
  :accept_encoding     => [{token, parameters}, ...],
  :accept_language     => [{token, parameters}, ...],
  :alert_info          => [{uri, parameters}, ...],
  :allow               => [token, ...],
  :authentication_info => %{name => value},
  :authorization       => [{scheme, parameters}, ...],
  :call_id             => token,
  :call_info           => [{uri, parameters}, ...],
  :contact             => "*" | [{display_name, uri, parameters}, ...],
  :content_disposition => {token, parameters},
  :content_encoding    => [token, ...],
  :content_language    => [token, ...],
  :content_length      => integer,
  :content_type        => {{type, subtype}, parameters},
  :cseq                => {integer, method},
  :date                => NaiveDateTime.t,
  :error_info          => [{uri, parameters}, ...],
  :expires             => integer,
  :from                => {display_name, uri, parameters},
  :in_reply_to         => [token, ...],
  :max_forwards        => integer,
  :mime_version        => {major, minor},
  :min_expires         => integer,
  :organization        => string,
  :priority            => token,
  :proxy_authenticate  => [{scheme, parameters}, ...],
  :proxy_authorization => [{scheme, parameters}, ...],
  :proxy_require       => [token, ...],
  :reason              => {token, parameters},
  :record_route        => [{display_name, uri, parameters}, ...],
  :reply_to            => {display_name, uri, parameters},
  :require             => [token, ...],
  :retry_after         => {integer, comment, parameters},
  :route               => [{display_name, uri, parameters}, ...],
  :server              => string,
  :subject             => string,
  :supported           => [token, ...],
  :timestamp           => {timestamp, delay},
  :to                  => {display_name, uri, parameters},
  :unsupported         => [token, ...],
  :user_agent          => string,
  :via                 => [{{major, minor}, protocol, {address, port}, parameters}, ...],
  :warning             => [{integer, agent, text}, ...],
  :www_authenticate    => [{scheme, parameters}, ...],
  String.t             => [String.t, ...]
}
```


## Copyright

Copyright (c) 2016-2020 Guilherme Balena Versiani. See [LICENSE](LICENSE) for
further details.

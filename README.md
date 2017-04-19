![Sippet](http://sippet.github.io/sippet/public/apple-touch-icon-144-precomposed.png)
=========

[![Hex.pm](https://img.shields.io/hexpm/l/sippet.svg "BSD Licensed")](https://github.com/balena/elixir-sippet/blob/master/LICENSE)
[![Hex version](https://img.shields.io/hexpm/v/sippet.svg "Hex version")](https://hex.pm/packages/sippet)
[![Build Status](https://travis-ci.org/balena/elixir-sippet.svg)](https://travis-ci.org/balena/elixir-sippet)

An Elixir library designed to write Session Initiation Protocol middleware.


# Introduction

SIP is a very flexible protocol that has great depth. It was designed to be a
general-purpose way to set up real-time multimedia sessions between groups of
participants. It is a text-based protocol modeled on the request/response model
used in HTTP. This makes it easy to debug because the messages are relatively
easy to construct and easy to see.

Sippet is designed as a simple SIP middleware library, aiming the developer to
write any kind of function required to register users, get their availability,
check capabilities, setup and manage sessions. On the other hand, Sippet does
not intend to provide any feature available in a fully functional SIP UAC/UAS,
proxy server, B2BUA, SBC or application; instead, it has only the essential
building blocks to build any kind of SIP middleware.

One of the most central parts of Sippet is the `Sippet.Message`. Instead of
many headers that you end up having to parse by yourself, there's an internal
parser written in C++ (an Erlang NIF) that does all the hard work for you. This
way, the `Sippet.Message.headers` is a key-value simple `Map` where the key is
the header name, and the value varies accordingly the header type. For
instance, the header `:cseq` has the form `{sequence :: integer, method}` where
the `method` is an atom with the method name (like `:invite`).

Other than the `Sippet.Message`, you will find the `Sippet.Transport` and the
`Sippet.Transaction` modules, which implement the two standard SIP layers.
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
`Sippet.Transport.UDP` (but still performatic) implementation is provided,
which is enough for several SIP middleware apps. Transport protocols can be
implemented quite easily using the `Sippet.Transport.Plug` behavior. In order
to optimize the message processing, there's a `Sippet.Transport.Queue` which
receives datagrams, case the transport protocol is datagram-based, or a
`Sippet.Message.t` message, generally performed by stream-based protocols.


## Installation

The package can be installed from [Hex](https://hex.pm/docs/publish) as:

  1. Add `sippet` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:sippet, "~> 0.1.8"}]
    end
    ```

  2. Ensure `sippet` is started before your application:

    ```elixir
    def application do
      [applications: [:sippet, :logger, :gen_state_machine, :socket, :poolboy]]
    end
    ```

## Copyright

Copyright (c) 2016-2017 Guilherme Balena Versiani. See [LICENSE](LICENSE) for
further details.

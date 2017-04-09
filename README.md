![Sippet](http://sippet.github.io/sippet/public/apple-touch-icon-144-precomposed.png)
=========

An Elixir library designed to write SIP protocol middleware.

# Introduction

Sippet is not intended to be a fully functional SIP UAC/UAS, proxy server,
B2BUA, SBC or application; instead, it has only the very basic to build any
kind of SIP middleware.

One of the most central parts of Sippet is the `Sippet.Message`. Instead of
many headers that you end up having to parse by yourself, there's an internal
parser written in C++ (an Erlang NIF) that does all the hard work for you. This
way, the `Sippet.Message.headers` is a simple `Map` where the key is the header
name, and the value varies accordingly the header type. For instance, the
header `:cseq` has the form `{sequence :: integer, method}` where the
`method`is an atom with the method name (like `:invite`), and `:via` is a list
of tuples `{version, protocol, sent_by, parameters}`, where `version` is of the
form `{major, minor}`, `protocol` is an atom representing the Via header
protocol (such as `:udp`), `sent_by` is a tuple `{host :: binary, port}` and
parameters is always a `Map` of the form `%{name => value}` where `name` and
`value` are `String.t`.

Other than the `Sippet.Message`, you will find the `Sippet.Transport` and the
`Sippet.Transaction` modules, which implement the two standard SIP layers.

As Sippet is a simple SIP library, the developer has to understand the protocol
very well before writing a middleware. This design decision came up because all
attempts to hide any inherent SIP complexity by other frameworks have failed.

There is no support for plugins or hooks, all just have to be done from a
`Sippet.Core` module implementation. Also there is no support for fancy
protocols; a simple `Sippet.Transport.UDP` (but still performatic)
implementation is provided, which is enough for several SIP middleware apps.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `sippet` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:sippet, "~> 0.1.0"}]
    end
    ```

  2. Ensure `sippet` is started before your application:

    ```elixir
    def application do
      [applications: [:sippet]]
    end
    ```


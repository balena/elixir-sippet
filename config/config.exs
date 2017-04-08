# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# Configures the sippet core
#config :sippet, core_module: Sippet.Proxy


config :sippet, Sippet.Transport.Supervisor, [
  {Sippet.Transport.UDP.Plug, Sippet.Transport.UDP.Conn}
]

config :sippet, Sippet.Transport.UDP.Plug, port: 5060

config :sippet, Sippet.Transport,
  udp: Sippet.Transport.UDP.Conn

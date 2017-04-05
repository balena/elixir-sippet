# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# Configures the sippet core
#config :sippet, core_module: Sippet.Proxy

config :sippet, Sippet.Transport.Registry,
  udp: {{Sippet.Transport.UDP.Plug, Sippet.Transport.UDP.Conn},
        [5060, [local: [address: "0.0.0.0"]]]}

import Config

# Configures the sippet core
#config :sippet, core_module: Sippet.Proxy

# Sets the UDP plug settings:
#
# * `:port` is the UDP port to listen (required).
# * `:address` is the local address to bind (optional, defaults to "0.0.0.0")
config :sippet, Sippet.Transports.UDP.Plug,
  port: 5060,
  address: "127.0.0.1"

# Sets the message processing pool settings:
#
# * `:size` is the pool size (optional, defaults to
#   `System.schedulers_online/1`).
# * `:max_overflow` is the acceptable number of extra workers under high load
#   (optional, defaults to 0, or no overflow).
config :sippet, Sippet.Transports.Pool,
  size: System.schedulers_online(),
  max_overflow: 0

# Sets the transport plugs, or the supported SIP transport protocols.
config :sippet, Sippet.Transports,
  udp: Sippet.Transports.UDP.Plug

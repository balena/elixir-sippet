defmodule Sippet.Transport.Pool do

  def check_out(), do: :poolboy.checkout(__MODULE__)

  def check_in(worker), do: :poolboy.checkin(__MODULE__, worker)
end

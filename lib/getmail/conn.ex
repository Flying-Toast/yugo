defmodule Getmail.Conn do
  @enforce_keys [:tls, :socket]
  defstruct [:tls, :socket]
end

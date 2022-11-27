defmodule Getmail.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket]
  defstruct [:tls, :socket, next_tag: 0]
end

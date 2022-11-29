defmodule UgotMail.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket]
  defstruct [:tls, :socket]
end

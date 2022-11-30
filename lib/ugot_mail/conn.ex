defmodule UgotMail.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket]
  defstruct [:tls, :socket, next_cmd_tag: 0, capabilities: [], got_server_greeting: false]
end

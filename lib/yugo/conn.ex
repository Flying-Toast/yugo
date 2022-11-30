defmodule Yugo.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket, :username, :password]
  defstruct [
    :tls,
    :socket,
    :username,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
    next_cmd_tag: 0,
    capabilities: [],
    got_server_greeting: false,
    state: :not_authenticated,
    login_tag: nil,
    tag_cmd_map: %{}
  ]
end

defmodule Yugo.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket, :username, :password, :server]
  defstruct [
    :tls,
    :socket,
    :server,
    :username,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
    next_cmd_tag: 0,
    capabilities: [],
    have_authed_capabilities: false,
    got_server_greeting: false,
    state: :not_authenticated,
    login_tag: nil,
    starttls_tag: nil,
    tag_cmd_map: %{}
  ]
end

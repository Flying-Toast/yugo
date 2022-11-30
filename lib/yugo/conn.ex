defmodule Yugo.Conn do
  @moduledoc false

  @enforce_keys [:tls, :socket, :username, :password, :server, :mailbox]
  defstruct [
    :tls,
    :socket,
    :server,
    :username,
    :mailbox,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
    next_cmd_tag: 0,
    capabilities: [],
    got_server_greeting: false,
    state: :not_authenticated,
    tag_map: %{},
    applicable_flags: [],
    num_exists: nil,
    num_recent: nil,
    first_unseen: nil
  ]
end

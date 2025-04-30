defmodule Yugo.Conn do
  @moduledoc false

  @type t :: %__MODULE__{
          my_name: Yugo.Client.name(),
          tls: boolean,
          socket: :gen_tcp.socket() | :ssl.sslsocket(),
          server: String.t(),
          username: String.t(),
          mailbox: String.t(),
          password: String.t(),
          next_cmd_tag: integer,
          capabilities: [String.t()],
          got_server_greeting: boolean,
          state: :not_authenticated | :authenticated | :selected,
          tag_map: %{
            String.t() => %{
              command: String.t(),
              on_response: (__MODULE__.t(), :ok | :no | :bad -> __MODULE__.t())
            }
          },
          applicable_flags: [String.t()],
          permanent_flags: [String.t()],
          num_exists: nil | integer,
          num_recent: nil | integer,
          first_unseen: nil | integer,
          uid_validity: nil | integer,
          uid_next: nil | integer,
          mailbox_mutability: :read_only | :read_write,
          idling: boolean,
          idle_timer: reference | nil,
          idle_timed_out: boolean,
          filters: [{Yugo.Filter.t(), pid}],
          unprocessed_messages: %{integer: %{}},
          attrs_needed_by_filters: String.t(),
          ssl_verify: :verify_none | :verify_peer,
          list_response_acc: [%{flags: [String.t()], delimiter: String.t(), name: String.t()}],
          fetch_queue: [integer]
        }

  @derive {Inspect, except: [:password]}
  @enforce_keys [:my_name, :tls, :socket, :username, :password, :server, :mailbox, :ssl_verify]
  defstruct [
    :my_name,
    :tls,
    :socket,
    :server,
    :username,
    :mailbox,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
    :ssl_verify,
    next_cmd_tag: 0,
    capabilities: [],
    got_server_greeting: false,
    state: :not_authenticated,
    tag_map: %{},
    applicable_flags: [],
    permanent_flags: [],
    num_exists: nil,
    num_recent: nil,
    first_unseen: nil,
    uid_validity: nil,
    uid_next: nil,
    mailbox_mutability: nil,
    idling: false,
    idle_timer: nil,
    idle_timed_out: false,
    filters: [],
    unprocessed_messages: %{},
    attrs_needed_by_filters: "",
    list_response_acc: [],
    fetch_queue: []
  ]
end

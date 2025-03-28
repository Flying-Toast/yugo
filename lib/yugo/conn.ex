defmodule Yugo.Conn do
  @moduledoc false

  @type t :: %__MODULE__{
          my_name: Yugo.Client.name(),
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
          attrs_needed_by_filters: String.t()
        }

  @derive {Inspect, except: [:password]}
  @enforce_keys [
    :my_name,
    :transport,
    :server_options,
    :socket,
    :username,
    :password,
    :server,
    :mailbox
  ]
  defstruct [
    :my_name,
    :socket,
    :server,
    :username,
    :mailbox,
    :transport,
    :server_options,
    # only stored temporarily; gets cleared from memory after sending LOGIN
    :password,
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
    attrs_needed_by_filters: ""
  ]

  alias Yugo.Transport.Ssl, as: SslTransport
  alias Yugo.Filter
  alias Yugo.Command
  alias Yugo.Transport
  alias Yugo.Conn

  require Logger

  def init(args) do
    transport = Transport.init(args)
    server_options = Keyword.take(args, [:server, :port, :ssl_verify])

    {:ok, socket} = Transport.connect(transport)

    %Conn{
      my_name: args[:name],
      transport: transport,
      socket: socket,
      server: args[:server],
      username: args[:username],
      password: args[:password],
      mailbox: args[:mailbox],
      server_options: server_options
    }
  end

  def greet(%Conn{} = conn) do
    %Conn{conn | got_server_greeting: true}
  end

  def clear_password(%Conn{} = conn) do
    %Conn{conn | password: ""}
  end

  def recv(%Conn{transport: transport, socket: socket}, length \\ 0) do
    Transport.recv(transport, socket, length)
  end

  def send_command(conn, command, options \\ [])

  def send_command(%Conn{} = conn, command, options) when is_binary(command) do
    if Keyword.get(options, :tagged?, true) do
      {current_tag, conn} = next_tag(conn)
      tagged_command = "#{current_tag} #{command}"

      conn
      |> send_raw(tagged_command)
      |> put_tag_map(current_tag, tagged_command, options)
    else
      send_raw(conn, command)
    end
  end

  def send_command(%Conn{} = conn, command, options) do
    send_command(conn, Command.to_string(command), options)
  end

  defp send_raw(%Conn{transport: transport, socket: socket} = conn, command) do
    transport_key =
      case transport do
        SslTransport -> "ssl"
        _ -> "tcp"
      end

    Logger.debug("[#{inspect(Yugo.Client)}] [#{transport_key}] C: #{command}")
    Transport.send(transport, socket, command <> "\r\n")
    conn
  end

  defp put_tag_map(%Conn{tag_map: tag_map} = conn, current_tag, command, options) do
    on_response = Keyword.get(options, :on_response, fn conn, _, _ -> conn end)
    updated_tag_map = Map.put(tag_map, current_tag, %{command: command, on_response: on_response})

    %Conn{conn | tag_map: updated_tag_map}
  end

  defp next_tag(%Conn{next_cmd_tag: next_cmd_tag} = conn) do
    {next_cmd_tag, %Conn{conn | next_cmd_tag: next_cmd_tag + 1}}
  end

  def pop_tag_map(%Conn{tag_map: tag_map} = conn, tag) do
    {tag_options, new_tag_map} = Map.pop!(tag_map, tag)

    {tag_options, %Conn{conn | tag_map: new_tag_map}}
  end

  @filters [
    {"FLAGS", &Filter.needs_flags?/1},
    {"ENVELOPE", &Filter.needs_envelope?/1}
  ]
  def filter_attributes(%Conn{filters: filters}) do
    Enum.reduce(@filters, [], fn {attribute, filter_function}, acc ->
      if Enum.any?(filters, fn {filter, _pid} -> filter_function.(filter) end) do
        [attribute | acc]
      else
        acc
      end
    end)
  end

  def map_num_exists(%Conn{num_exists: num_exists} = conn, function) do
    %Conn{conn | num_exists: function.(num_exists)}
  end

  def expunge_messages(%Conn{} = conn, expunge_number) do
    map_unprocessed_messages(conn, fn unprocessed_messages ->
      Enum.reduce(unprocessed_messages, %{}, fn
        {^expunge_number, _}, acc ->
          acc

        {tag_number, message}, acc when expunge_number < tag_number ->
          Map.put(acc, tag_number - 1, message)

        {tag_number, message}, acc when expunge_number > tag_number ->
          Map.put(acc, tag_number, message)
      end)
    end)
  end

  def has_unprocessed_message?(%Conn{unprocessed_messages: unprocessed_messages}, sequence_number) do
    Map.has_key?(unprocessed_messages, sequence_number)
  end

  def map_unprocessed_message(%Conn{} = conn, sequence_number, value) do
    map_unprocessed_messages(conn, fn unprocessed_messages ->
      Map.update(unprocessed_messages, sequence_number, value, &Map.merge(&1, value))
    end)
  end

  def map_unprocessed_messages(%Conn{unprocessed_messages: unprocessed_messages} = conn, function) do
    new_unprocessed_messages = function.(unprocessed_messages)
    %Conn{conn | unprocessed_messages: new_unprocessed_messages}
  end

  def earliest_unprocessed_message(%Conn{unprocessed_messages: unprocessed_messages}) do
    Enum.min_by(unprocessed_messages, fn {sequence_number, _} -> sequence_number end)
  end

  def pop_unprocessed_messages(
        %Conn{unprocessed_messages: unprocessed_messages} = conn,
        sequence_number
      ) do
    {message, other_unprocessed_messages} = Map.pop!(unprocessed_messages, sequence_number)

    conn =
      map_unprocessed_messages(conn, fn _ ->
        other_unprocessed_messages
      end)

    {message, conn}
  end

  def command_in_progress?(%Conn{tag_map: tag_map}) do
    tag_map != %{}
  end

  def idle_timed_out(%Conn{} = conn) do
    cancel_idle_timer(%Conn{conn | idle_timed_out: true})
  end

  def cancel_idle_timer(%Conn{idle_timer: idle_timer} = conn) do
    if is_reference(idle_timer), do: Process.cancel_timer(idle_timer)

    updated_conn = %Conn{conn | idle_timer: nil, idling: false}

    send_raw(updated_conn, Command.to_string(:done))
  end

  def subscribe(%Conn{} = conn, pid, filter) do
    map_filters(conn, &[{filter, pid} | &1])
  end

  def unsubscribe(%Conn{} = conn, calling_pid) do
    map_filters(conn, fn filters ->
      Enum.reject(filters, fn {pid, _} -> pid == calling_pid end)
    end)
  end

  defp map_filters(%Conn{filters: filters} = conn, function) do
    %Conn{conn | filters: function.(filters)}
  end

  def set_socket_options(%Conn{transport: transport}, socket, options) do
    Transport.set_socket_options(transport, socket, options)
  end

  def using_tls?(%Conn{transport: %SslTransport{}}), do: true
  def using_tls?(%Conn{}), do: false

  def has_capability?(%Conn{capabilities: capabilities}, capability) do
    capability in capabilities
  end

  def switch_to_tls(%Conn{socket: socket, server_options: server_options} = conn) do
    ssl_transport = SslTransport.init(server_options)

    {:ok, socket} = SslTransport.connect_to_socket(ssl_transport, socket)

    %Conn{conn | transport: ssl_transport, socket: socket}
  end

  def put_state(%Conn{} = conn, state) do
    %Conn{conn | state: state}
  end

  def put_mailbox_mutability(%Conn{} = conn, mailbox_mutability) do
    %Conn{conn | mailbox_mutability: mailbox_mutability}
  end

  @idle_timeout 1000 * 60 * 27
  def set_idling(%Conn{} = conn, destination_pid) do
    timer = Process.send_after(destination_pid, :idle_timeout, @idle_timeout)
    %Conn{conn | idling: true, idle_timer: timer, idle_timed_out: false}
  end
end

defmodule Yugo do
  @moduledoc """
  Auxiliary functions for Yugo.
  """

  alias Yugo.{Filter, Client}

  @type address :: String.t()

  @typedoc """
  e.g. `"text/html"`, `"image/png"`, `"text/plain"`, etc.

  For more, see this [list of MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types).
  """
  @type mime_type :: String.t()

  @typedoc """
  A body consists of a list of "parts".
  Each part has a mime type (e.g. `"text/html"`) and associated data stored as a string/binary.

  Note that an email can contain multiple *bodies*, which can each contain multiple *parts*.
  """
  @type body :: [{mime_type, binary}]

  @type flag :: :seen | :answered | :flagged | :draft | :deleted

  @typedoc """
  An email message sent to a subscribed process.

  ## A note on "bodies"

  A single email can have multiple [bodies](`t:Yugo.body/0`). A common example is an email with an attachment:
  The "text" of the email would be contained in one body, and the attached file would be in the second body.
  A body can itself have multiple *parts*.
  """
  @type email :: %{
          bcc: [address],
          bodies: [body],
          cc: [address],
          date: DateTime.t(),
          flags: [flag],
          in_reply_to: nil | String.t(),
          message_id: nil | String.t(),
          reply_to: [address],
          sender: [address],
          subject: nil | String.t(),
          to: [address]
        }

  @doc """
  Subscribes the calling process to the [`Client`](`Yugo.Client`) named by `client_name`.

  When you subscribe to a client, your process will be notified about new emails via a message
  in the form `{:email, client, message}`, where `client` is the name of the client that is notifying you,
  and `message` is the email. See the [`email`](`t:Yugo.email/0`) type for the structure of the `message` field.

  You may also pass an optional [`Filter`](`Yugo.Filter`) as the second argument to match what
  emails you want to be notified about. If you do not pass a filter, it defaults to [`Filter.all`](`Yugo.Filter.all/0`),
  which allows all emails to pass through.
  """
  @spec subscribe(Client.name(), Filter.t()) :: :ok
  def subscribe(client_name, filter \\ Filter.all()) do
    GenServer.cast({:via, Registry, {Yugo.Registry, client_name}}, {:subscribe, self(), filter})
  end

  @doc """
  Unsubscribes the calling process from the specified [`Client`](`Yugo.Client`).

  This will unsubscribe the calling process from all messages from the client,
  regardless of how many separate times you [`subscribe`d](`subscribe/2`)
  """
  @spec unsubscribe(Client.name()) :: :ok
  def unsubscribe(client_name) do
    GenServer.cast({:via, Registry, {Yugo.Registry, client_name}}, {:unsubscribe, self()})
  end
end

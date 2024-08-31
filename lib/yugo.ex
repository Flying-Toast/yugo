defmodule Yugo do
  @moduledoc """
  Auxiliary functions for Yugo.
  """

  alias Yugo.{Filter, Client}

  @typedoc """
  The first field is the name associated with the address, and the second field is the address itself.

  e.g. `{"Bart", "bart@simpsons.family"}`
  """
  @type address :: {nil | String.t(), String.t()}

  @typedoc """
  e.g. `"text/html"`, `"image/png"`, `"text/plain"`, etc.

  For more, see this [list of MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types).
  """
  @type mime_type :: String.t()

  @typedoc """
  A body can be either "onepart" or "multipart".

  A "onepart" body is a tuple in the form `{mime_type, params, content}`, where `mime_type` is a [`mime_type`](`t:mime_type/0`),
  `params` is a string->string map, and `content` is a [`binary`](`t:binary/0`).

  A "multipart" body consists of a *list* of [`body`s](`t:body/0`), which can themselves be either onepart or multipart.
  """
  @type body :: {mime_type, %{optional(String.t()) => String.t()}, binary} | [body]

  @type flag :: :seen | :answered | :flagged | :draft | :deleted

  @typedoc """
  An email message sent to a subscribed process.

  # Difference between `sender` and `from`
  Both "sender" and "from" are fields used by IMAP to indicate the origin of the email.
  They are *usually* the same, but they can be different and they have different meanings:
  - `from` - the author who physically wrote the email. `From` is typically the address you see when viewing the message in an email client.
  - `sender` - the person who sent the email, potentially different than `from` if someone else sent the email on behalf of the author.
  """
  @type email :: %{
          bcc: [address],
          body: body,
          cc: [address],
          date: DateTime.t(),
          flags: [flag],
          in_reply_to: nil | String.t(),
          message_id: nil | String.t(),
          reply_to: [address],
          sender: [address],
          from: [address],
          subject: nil | String.t(),
          to: [address],
          seqnum: integer()
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

  @doc """
  Lists mailboxes matching the given reference and mailbox pattern.

  This function sends a LIST command to the IMAP server and returns the names of
  the mailboxes that match the given reference and mailbox pattern.

  ## Parameters

    * `client_name` - The name of the [`Client`](`Yugo.Client`) to use.
    * `reference` - The reference name, typically an empty string. Defaults to "".
    * `mailbox` - The mailbox name with possible wildcards. Defaults to "%", which matches all mailboxes.

  ## Returns

  A list of mailbox names.

  ## Example

      iex> Yugo.list(:my_client)
      ["INBOX", "Sent", "Drafts"]

  """
  @spec list(Client.name(), reference :: String.t(), mailbox :: String.t()) :: [
          {:name, String.t()} | {:delimiter, String.t()} | {:attributes, [String.t()]}
        ]
  def list(client_name, reference \\ "", mailbox \\ "%") do
    GenServer.call({:via, Registry, {Yugo.Registry, client_name}}, {:list, reference, mailbox})
  end

  @doc """
  Retrieves the capabilities of the IMAP server.

  This function sends a CAPABILITY command to the IMAP server and returns a list
  of capabilities supported by the server.

  ## Parameters

    * `client_name` - The name of the [`Client`](`Yugo.Client`) to use.

  ## Returns

  A list of capability strings.

  ## Example

      iex> Yugo.capabilities(:my_client)
      ["IMAP4rev1", "STARTTLS", "AUTH=PLAIN", "LOGINDISABLED"]

  """
  @spec capabilities(Client.name()) :: [String.t()]
  def capabilities(client_name) do
    GenServer.call({:via, Registry, {Yugo.Registry, client_name}}, {:capabilities})
  end

  @doc """
  Checks if the IMAP server supports a specific capability.

  This function uses the `capabilities/1` function to retrieve the server's capabilities
  and checks if the specified capability is present in the list.

  ## Parameters

    * `client_name` - The name of the [`Client`](`Yugo.Client`) to use.
    * `capability` - The capability string to check for.

  ## Returns

  A boolean indicating whether the server supports the specified capability.

  ## Example

      iex> Yugo.has_capability?(:my_client, "IMAP4rev1")
      true

  """
  @spec has_capability?(Client.name(), String.t()) :: boolean()
  def has_capability?(client_name, capability) do
    capabilities(client_name)
    |> Enum.any?(fn cap -> cap == capability end)
  end

  @doc """
  Moves messages from the current mailbox to another mailbox.

  This function sends a MOVE command to the IMAP server to move messages from the current
  mailbox to the specified destination mailbox.

  ## Parameters

    * `client_name` - The name of the [`Client`](`Yugo.Client`) to use.
    * `sequence_set` - A string representing the sequence set of messages to move.
    * `destination` - The name of the destination mailbox.
    * `return_uids` - (Optional) A boolean indicating whether to return the UIDs of the moved messages. Defaults to `false`.

  ## Returns

    * `:ok` if `return_uids` is `false`.
    * `{:ok, {[source_uids], [destination_uids]}}` if `return_uids` is `true`, where `source_uids` are the UIDs of the messages in the source mailbox, and `destination_uids` are the corresponding UIDs in the destination mailbox.
    * `{:error, reason}` if the operation fails.

  ## Example

      iex> Yugo.move(:my_client, "1:3", "Archive")
      :ok

      iex> Yugo.move(:my_client, "1:3", "Archive", true)
      {:ok, {[1, 2, 3], [101, 102, 103]}}

  """
  @spec move(
          Client.name(),
          sequence_set :: String.t(),
          destination :: String.t(),
          return_uids :: boolean()
        ) :: :ok | {:ok, {[integer()], [integer()]}} | {:error, String.t()}
  def move(client_name, sequence_set, destination, return_uids \\ false) do
    GenServer.call(
      {:via, Registry, {Yugo.Registry, client_name}},
      {:move, sequence_set, destination, return_uids}
    )
  end

  @doc """
    Creates a new mailbox (aka folder) with the given name.

    ## Parameters

    * `client_name` - The name of the [`Client`](`Yugo.Client`) to use.
    * `mailbox_name` - The name of the mailbox (aka folder) to create. Nested folders can be created by using a "/" delimiter.

    ## Returns

    * `:ok` if the mailbox was created successfully.
    * `{:error, reason}` if the operation fails.

    ## Example

      iex> Yugo.create(:my_client, "Work/Projects")
      :ok

  """
  @spec create(Client.name(), String.t()) :: :ok | {:error, String.t()}
  def create(client_name, mailbox_name) do
    GenServer.call(
      {:via, Registry, {Yugo.Registry, client_name}},
      {:create, mailbox_name}
    )
  end
end

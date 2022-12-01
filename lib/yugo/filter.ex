defmodule Yugo.Filter do
  @moduledoc """
  A [`Filter`](`Yugo.Filter`) is a construct that enables you to specify
  which emails you would like a [`Client`](`Yugo.Client`) to notify you about.

  ## Example

  To create a filter that only accepts emails that have been read and not replied to, and whose subject contains "Order Information":

      alias Yugo.Filter

      my_filter =
        Filter.all()
        |> Filter.has_flag(:seen)
        |> Filter.lacks_flag(:answered)
        |> Filter.subject_matches(~r/Order Information/)
  """

  # :recent is purposely omitted because it is too low-level
  @legal_flag_atoms [:seen, :answered, :flagged, :draft, :deleted]

  @type flag :: :seen | :answered | :flagged | :draft | :deleted

  @type t :: %__MODULE__{
          has_flags: [flag],
          lacks_flags: [flag],
          subject_regex: nil | Regex.t(),
          sender_regex: nil | Regex.t()
        }

  defstruct has_flags: [],
            lacks_flags: [],
            subject_regex: nil,
            sender_regex: nil

  @doc false
  def needs_envelope?(%__MODULE__{} = filter) do
    filter.subject_regex != nil || filter.sender_regex != nil
  end

  @doc false
  def needs_flags?(%__MODULE__{} = filter) do
    filter.has_flags != [] || filter.lacks_flags != []
  end

  @doc """
  Returns a [`Filter`](`Yugo.Filter`) that accepts all emails.
  """
  @spec all() :: __MODULE__.t()
  def all(), do: %__MODULE__{}

  @doc """
  Only accepts emails that have the specified flag.

  "Flags" are tags that are associated with an email message.

  ## Flags

  IMAP defines several flags that can be set by clients. Possible flags are:

    * `:seen` - Message has been read.

    * `:answered` - Message has been answered.

    * `:flagged` - Message is "flagged" for urgent/special attention.

    * `:draft` - Message has not completed composition (marked as a draft).

    * `:deleted` - Message is "deleted". In most email clients, this means it was moved to the trash folder.

  ## Example

      alias Filter

      # build a filter that only allows messages that have been seen.
      Filter.all()
      |> Filter.has_flag(:seen)
  """
  @spec has_flag(__MODULE__.t(), flag) :: __MODULE__.t()
  def has_flag(%__MODULE__{} = filter, flag) when flag in @legal_flag_atoms do
    flag not in filter.lacks_flags ||
      raise "Cannot enforce a has_flag constraint for \"#{inspect(flag)}\" because this filter already has a lacks_flag constraint for the same flag."

    if flag in filter.has_flags do
      filter
    else
      %{filter | has_flags: [flag | filter.has_flags]}
    end
  end

  @doc """
  Only accepts emails that do not have the specified flag.
  See `has_flag/2` for more information about flags.

  ## Example

      alias Filter

      # build a filter that allows all messages that do not have the :deleted flag
      Filter.all()
      |> Filter.lacks_flag(:deleted)
  """
  @spec lacks_flag(__MODULE__.t(), flag) :: __MODULE__.t()
  def lacks_flag(%__MODULE__{} = filter, flag) when flag in @legal_flag_atoms do
    flag not in filter.has_flags ||
      raise "Cannot enforce a lacks_flag constraint for \"#{inspect(flag)}\" because this filter already has a has_flag constraint for the same flag."

    if flag in filter.lacks_flags do
      filter
    else
      %{filter | lacks_flags: [flag | filter.lacks_flags]}
    end
  end

  @doc """
  Accepts emails whose "subject" line matches the given `Regex`.
  """
  @spec subject_matches(__MODULE__.t(), Regex.t()) :: __MODULE__.t()
  def subject_matches(%__MODULE__{} = filter, pattern) when is_struct(pattern, Regex) do
    filter.subject_regex == nil ||
      raise "This filter already has a subject match constraint. Filters can only have one of these constraints - to match multiple things, use regex OR patterns."

    %{filter | subject_regex: pattern}
  end

  @doc """
  Accepts emails where the email address of the sender matches the given `Regex`.

  ## Example


      alias Yugo.Filter

      # make a filter that only accepts emails sent from "peter@example.com" or "alex@example.com"
      Filter.all()
      |> Filter.sender_matches(~r/(peter|alex)@example.com/i)
  """
  @spec sender_matches(__MODULE__.t(), Regex.t()) :: __MODULE__.t()
  def sender_matches(%__MODULE__{} = filter, pattern) when is_struct(pattern, Regex) do
    filter.sender_regex == nil ||
      raise "This filter already has a sender match constraint. Filters can only have one of these constraints - to match multiple things, use regex OR patterns."

    %{filter | sender_regex: pattern}
  end
end

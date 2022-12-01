defmodule Yugo.Filter do
  @moduledoc """
  A [`Filter`](`Yugo.Filter`) is a construct that enables you to specify
  which emails you would like a [`Client`](`Yugo.Client`) to notify you about.

  ## Example

  To create a filter that only accepts emails that have been read but not replied to:

      alias Yugo.Filter

      my_filter =
        Filter.all()
        |> Filter.has_flag(:seen)
        |> Filter.lacks_flag(:answered)
  """

  # :deleted and :recent are purposely omitted because they are too low-level
  @legal_flag_atoms [:seen, :answered, :flagged, :draft]

  @type flag :: :seen | :answered | :flagged | :draft

  @type t :: %__MODULE__{
          has_flags: [flag],
          lacks_flags: [flag]
        }

  defstruct has_flags: [],
            lacks_flags: []

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
end

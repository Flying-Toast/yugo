defmodule Yugo.Filter do
  @moduledoc """
  """

  @type flag :: String.t() | :seen | :answered | :flagged | :deleted | :draft | :recent

  @type t :: %__MODULE__{
          has_flags: [flag],
          lacks_flags: [flag]
        }

  defstruct has_flags: [],
            lacks_flags: []

  @doc """
  Returns a `Filter` that accepts all emails.
  """
  @spec all() :: __MODULE__.t()
  def all(), do: %__MODULE__{}

  @doc """
  Only accepts emails that have the specified flag
  """
  @spec has_flag(__MODULE__.t(), flag) :: __MODULE__.t()
  def has_flag(%__MODULE__{} = filter, flag) when is_binary(flag) or is_atom(flag) do
    flag not in filter.lacks_flags ||
      raise "Cannot enforce a has_flag constraint for \"#{inspect(flag)}\" because this filter already has a lacks_flag constraint for the same flag."

    if flag in filter.has_flags do
      filter
    else
      %{filter | has_flags: [flag | filter.has_flags]}
    end
  end

  @doc """
  Only accepts emails that do not have the specified flag
  """
  @spec lacks_flag(__MODULE__.t(), flag) :: __MODULE__.t()
  def lacks_flag(%__MODULE__{} = filter, flag) when is_binary(flag) or is_atom(flag) do
    flag not in filter.has_flags ||
      raise "Cannot enforce a lacks_flag constraint for \"#{inspect(flag)}\" because this filter already has a has_flag constraint for the same flag."

    if flag in filter.lacks_flags do
      filter
    else
      %{filter | lacks_flags: [flag | filter.lacks_flags]}
    end
  end
end

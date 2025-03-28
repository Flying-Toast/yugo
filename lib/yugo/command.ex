defmodule Yugo.Command do
  @moduledoc """
  Commands supported by the client
  """
  @type t ::
          :logout
          | {:fetch, integer(), [String.t()]}
          | :done
          | :capability
          | :starttls
          | :idle
          | :noop
          | {:login, String.t(), String.t()}
          | {:select, String.t()}

  @doc """
  Converts a command to string
  """
  @spec to_string(t()) :: String.t()
  def to_string(:logout) do
    "LOGOUT"
  end

  def to_string({:fetch, sequence_number, parts}) do
    "FETCH #{sequence_number} (#{Enum.join(parts, " ")})"
  end

  def to_string(:done) do
    "DONE"
  end

  def to_string(:capability) do
    "CAPABILITY"
  end

  def to_string(:starttls) do
    "STARTTLS"
  end

  def to_string(:idle) do
    "IDLE"
  end

  def to_string(:noop) do
    "NOOP"
  end

  def to_string({:login, username, password}) do
    "LOGIN #{quote_string(username)} #{quote_string(password)}"
  end

  def to_string({:select, mailbox}) do
    "SELECT #{quote_string(mailbox)}"
  end

  defp quote_string(string) do
    if Regex.match?(~r/[\r\n]/, string) do
      raise "string passed to quote_string contains a CR or LF. TODO: support literals"
    end

    string
    |> String.replace("\\", "\\\\")
    |> String.replace(~S("), ~S(\"))
    |> then(&~s("#{&1}"))
  end
end

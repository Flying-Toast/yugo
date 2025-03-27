defmodule Yugo.Command do
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
end

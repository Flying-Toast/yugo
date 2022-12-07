defmodule Yugo.ClientTest do
  use ExUnit.Case, asnc: true
  doctest Yugo.Client
  import Helpers.Client

  test "Upgrades insecure connections via STARTTLS" do
    accept_gen_tcp()
    |> do_hello()
    |> do_starttls()
    |> do_select_bootstrap(1)
  end

  test "cancels IDLE" do
    ssl_server()
    |> assert_comms(
      ~S"""
      S: * 1 EXISTS
      C: DONE
      """
    )
  end
end

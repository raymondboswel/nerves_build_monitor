defmodule HelloNetwork do
  @moduledoc """
  Example of setting up wired and wireless networking on a Nerves device.
  """

  require Logger

  alias Nerves.Network
  alias ElixirALE.GPIO

  @interface Application.get_env(:hello_network, :interface, :eth0)

  @doc "Main entry point into the program. This is an OTP callback."
  def start(_type, _args) do
    GenServer.start_link(__MODULE__, to_string(@interface), name: __MODULE__)
  end

  def display_repo_status(output_pid) do
    repo_status = get_repo_status()

    if repo_status == :passing do
      Logger.debug("Turning pin ON")
      GPIO.write(output_pid, 1)
    else
      Logger.debug("Turning pin OFF")
      GPIO.write(output_pid, 0)
    end
  end

  def get_repo_status() do
    IO.puts("Getting build status...")
    response = HTTPoison.get("https://api.travis-ci.org/repos/raymondboswel/amnesia_api/builds")
    IO.inspect(response)

    build_res =
      case response do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          body
          |> Poison.decode!()
          |> List.first()
          |> Map.fetch!("result")

        {:ok, %HTTPoison.Response{status_code: 404}} ->
          IO.puts("Not found :(")
          1

        {:error, %HTTPoison.Error{reason: reason}} ->
          IO.inspect(reason)
          1
      end

    IO.inspect(build_res)

    # Not idiomatic, but too lazy to find the right way now.
    result =
      if build_res == 0 do
        :passing
      else
        :failing
      end

    result
  end

  @doc "Are we connected to the internet?"
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  @doc "Returns the current ip address"
  def ip_addr, do: GenServer.call(__MODULE__, :ip_addr)

  @doc """
  Attempts to perform a DNS lookup to test connectivity.

  ## Examples

    iex> HelloNetwork.test_dns()
    {:ok,
     {:hostent, 'nerves-project.org', [], :inet, 4,
      [{192, 30, 252, 154}, {192, 30, 252, 153}]}}
  """
  def test_dns(hostname \\ 'nerves-project.org') do
    :inet_res.gethostbyname(hostname)
  end

  ## GenServer callbacks

  def init(interface) do
    Network.setup(interface)
    HTTPoison.start()
    SystemRegistry.register()
    schedule_work()
    {:ok, output_pid} = GPIO.start_link(26, :output)
    {:ok, %{interface: interface, ip_address: nil, connected: false, output_pid: output_pid}}
  end

  def handle_info(:work, state) do
    # Do the desired work here
    # Reschedule once more
    IO.puts("Doing work")
    IO.inspect(state)
    display_repo_status(state.output_pid)
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    # In 20 seconds
    Process.send_after(self(), :work, 10 * 1000)
  end

  def handle_info({:system_registry, :global, registry}, state) do
    ip = get_in(registry, [:state, :network_interface, state.interface, :ipv4_address])

    if ip != state.ip_address do
      Logger.info("IP ADDRESS CHANGED: #{ip}")
    end

    connected = match?({:ok, {:hostent, 'nerves-project.org', [], :inet, 4, _}}, test_dns())
    {:noreply, %{state | ip_address: ip, connected: connected || false}}
  end

  def handle_info(_, state), do: {:noreply, state}

  def handle_call(:connected?, _from, state), do: {:reply, state.connected, state}
  def handle_call(:ip_addr, _from, state), do: {:reply, state.ip_address, state}
end

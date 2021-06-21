defmodule Extg do
  @moduledoc """
  Documentation for `Extg`.
  """

  use GenServer

  require Logger

  @wait_interval 100

  def new do
    {:ok, wg} = GenServer.start(__MODULE__, [])
    wg
  end

  def add(wg, fun) when is_pid(wg) do
    GenServer.cast(wg, {:add, fun})
    wg
  end

  def wait(wg) when is_pid(wg) do
    GenServer.call(wg, :wait, :infinity)
  end

  def close(wg) when is_pid(wg) do
    Process.exit(wg, :by_caller)
  end

  @impl GenServer
  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{tasks: [], exit: nil}}
  end

  @impl GenServer
  def handle_info({:EXIT, _from, :normal}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _from, :others_fail}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, from, reason}, state) do
    for t <- Enum.reject(state.tasks, fn t -> t.pid == from end) do
      Process.exit(t.pid, :others_fail)
    end

    {:noreply, %{state | exit: reason}}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:add, fun}, state) do
    t =
      Task.async(fn ->
        try do
          fun.()
        catch
          _, reason ->
            Process.exit(self(), reason)
        end
      end)

    t_list = [t | state.tasks]
    {:noreply, %{state | tasks: t_list}}
  end

  @impl GenServer
  def handle_call(:wait, _from, state) do
    do_wait(state, [])
  end

  defp do_wait(%{exit: reason} = state, acc) when is_nil(reason) do
    yield_results =
      state.tasks
      |> Enum.map(fn task ->
        case Task.yield(task, @wait_interval) do
          {:ok, res} ->
            {:ok, res}

          {:exit, r} ->
            throw(r)

          nil ->
            nil
        end
      end)

    res =
      yield_results
      |> Enum.filter(fn
        {:ok, _res} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, res} -> res end)

    if length(acc) + length(res) < length(state.tasks) do
      do_wait(state, acc ++ res)
    else
      {:reply, acc ++ res, state}
    end
  catch
    :throw, r ->
      {:reply, {:error, r}, state}
  end

  defp do_wait(%{exit: reason} = state, _) do
    {:reply, {:error, reason}, state}
  end
end

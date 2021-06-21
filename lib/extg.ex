defmodule Extg do
  @moduledoc """
  Task Group that expects all tasks to succeed or fail fast due to one fails.

  ## Example

  Normal case:

      res =
        Extg.new()
        |> Extg.add(fn -> :ok end)
        |> Extg.add(fn -> :ok end)
        |> Extg.wait()

      res # => [:ok, :ok]

  If one of tasks fails:

      res =
        Extg.new()
        |> Extg.add(fn ->
          :timer.sleep(5_000)
          :ok
        end)
        |> Extg.add(fn ->
          :timer.sleep(1_000)
          raise "something wrong"
          :ok
        end)
        |> Extg.wait()

      res # => {:error, %RuntimeError{message: "something wrong"}}

  In this case, `wait()` will stop as soon as error raised in the 2nd task. The first task was sent a `:exit`.

  For more details please see the test cases or document for each functions.
  """

  use GenServer

  require Logger

  @wait_interval 100

  @doc """
  Create a new task group process, returning a pid of it if succeeds.
  """
  @spec new() :: pid()
  def new do
    {:ok, tg} = GenServer.start(__MODULE__, [])
    tg
  end

  @doc """
  Add a task (in the form of an anonymous function) to the task group.
  Returning pid of task group.
  """
  @spec add(pid(), function()) :: pid()
  def add(tg, fun) when is_pid(tg) do
    GenServer.cast(tg, {:add, fun})
    tg
  end

  @doc """
  Wait for all tasks in task group to complete. It blocks.
  If `timeout` is `:infinity` (default), this would block ad infinite.
  """
  @spec wait(pid(), timeout :: atom() | integer()) :: [any] | {:error, term()}
  def wait(tg, timeout \\ :infinity)
      when is_pid(tg) and (timeout == :infinity or is_integer(timeout)) do
    GenServer.call(tg, {:wait, timeout}, :infinity)
  end

  @doc """
  Manually exit the task group process, letting all tasks exit too.
  """
  @spec close(pid()) :: true
  def close(tg) when is_pid(tg) do
    Process.exit(tg, :by_caller)
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
  def handle_call({:wait, timeout}, _from, state) do
    if timeout == :infinity do
      do_wait(state, [])
    else
      do_wait_with_timeout(state, [], timeout)
    end
  end

  defp do_wait(%{exit: reason} = state, _acc) when not is_nil(reason) do
    {:reply, {:error, reason}, state}
  end

  defp do_wait(state, acc) do
    res = yield_tasks!(state.tasks)

    if length(acc) + length(res) < length(state.tasks) do
      do_wait(state, acc ++ res)
    else
      {:reply, acc ++ res, state}
    end
  catch
    :throw, r ->
      {:reply, {:error, r}, state}
  end

  defp do_wait_with_timeout(%{exit: reason} = state, _acc, _time)
       when not is_nil(reason) do
    {:reply, {:error, reason}, state}
  end

  defp do_wait_with_timeout(state, _acc, time)
       when time < 0 do
    for t <- state.tasks do
      Process.exit(t.pid, :by_caller)
    end

    {:reply, {:error, :timeout}, state}
  end

  defp do_wait_with_timeout(state, acc, time) do
    {elapsed, res} =
      :timer.tc(fn ->
        yield_tasks!(state.tasks)
      end)

    if length(acc) + length(res) < length(state.tasks) do
      do_wait_with_timeout(state, acc ++ res, time - elapsed / 1_000)
    else
      {:reply, acc ++ res, state}
    end
  catch
    :throw, r ->
      {:reply, {:error, r}, state}
  end

  defp yield_tasks!(tasks) do
    tasks
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
    |> Enum.filter(fn
      {:ok, _res} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, res} -> res end)
  end
end

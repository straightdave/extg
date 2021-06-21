defmodule ExtgTest do
  use ExUnit.Case

  test "simple use of APIs" do
    res =
      Extg.new()
      |> Extg.add(fn -> :ok end)
      |> Extg.add(fn -> :ok end)
      |> Extg.wait()

    assert res == [:ok, :ok]
  end

  test "can close without error" do
    tg = Extg.new()
    Extg.close(tg)
  end

  test "all tasks complete normally" do
    tg = Extg.new()

    [
      {1_000, nil, "Task 1"},
      {1_100, nil, "Task 2"},
      {1_200, nil, "Task 3"}
    ]
    |> Enum.each(fn {duration, fail_time, name} ->
      Extg.add(tg, fn ->
        if fail_time do
          :timer.sleep(fail_time)
          raise "raised in #{name}"
        end

        :timer.sleep(duration - (fail_time || 0))
        :ok
      end)
    end)

    res = Extg.wait(tg)
    assert [:ok, :ok, :ok] == res
  end

  test "one of tasks fails" do
    tg = Extg.new()

    {dur, _} =
      :timer.tc(fn ->
        [
          {1_000, nil, "Task 1"},
          {3_200, 2_100, "Task 2"},
          {8_000, nil, "Task 3"}
        ]
        |> Enum.each(fn {duration, fail_time, name} ->
          Extg.add(tg, fn ->
            if fail_time do
              :timer.sleep(fail_time)
              raise "raised in #{name}"
            end

            :timer.sleep(duration - (fail_time || 0))
            :ok
          end)
        end)

        res = Extg.wait(tg)
        assert {:error, %RuntimeError{message: "raised in Task 2"}} == res
      end)

    assert dur / 1_000 < 8_000, "duration #{inspect(dur)} should be less than 8s"
  end

  test "very long task" do
    tg = Extg.new()

    [
      {1_000, nil, "Task 1"},
      {20_000, nil, "Task 2"}
    ]
    |> Enum.each(fn {duration, fail_time, name} ->
      Extg.add(tg, fn ->
        if fail_time do
          :timer.sleep(fail_time)
          raise "raised in #{name}"
        end

        :timer.sleep(duration - (fail_time || 0))
        :ok
      end)
    end)

    res = Extg.wait(tg)
    assert [:ok, :ok] == res
  end
end

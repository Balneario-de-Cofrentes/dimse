defmodule Dimse.TelemetryTest do
  use ExUnit.Case, async: true

  alias Dimse.Telemetry

  describe "span/3" do
    test "executes the function and returns its result" do
      result = Telemetry.span(:test_span, %{id: "x"}, fn -> {"return_value", %{}} end)
      assert result == "return_value"
    end

    test "propagates the result through the span" do
      result = Telemetry.span(:noop, %{}, fn -> {42, %{count: 1}} end)
      assert result == 42
    end
  end

  describe "emit/3" do
    test "emits a telemetry event (3-arg form)" do
      assert :ok = Telemetry.emit(:test_event, %{size: 42}, %{id: "y"})
    end

    test "emit/1 uses default measurements and metadata" do
      assert :ok = Telemetry.emit(:test_event)
    end

    test "emit/2 uses default metadata" do
      assert :ok = Telemetry.emit(:test_event, %{size: 1})
    end
  end

  describe "emit_event/3" do
    test "emits a multi-segment telemetry event" do
      assert :ok = Telemetry.emit_event([:negotiation, :start], %{system_time: 1}, %{id: "z"})
    end

    test "emit_event/1 uses default measurements and metadata" do
      assert :ok = Telemetry.emit_event([:tls, :handshake])
    end

    test "emit_event/2 uses default metadata" do
      assert :ok = Telemetry.emit_event([:handler, :stop], %{duration: 5})
    end

    test "events are prefixed with [:dimse | ...]" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-emit-event-prefix-#{inspect(ref)}",
        [:dimse, :handler, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.emit_event([:handler, :start], %{system_time: 42}, %{callback: :handle_echo})

      assert_receive {:telemetry_event, [:dimse, :handler, :start], %{system_time: 42},
                      %{callback: :handle_echo}}

      :telemetry.detach("test-emit-event-prefix-#{inspect(ref)}")
    end
  end
end

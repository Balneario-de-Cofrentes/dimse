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
end

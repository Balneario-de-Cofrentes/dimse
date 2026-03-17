defmodule Dimse.MessageTest do
  use ExUnit.Case, async: true

  alias Dimse.Message

  describe "Message struct" do
    test "has correct default fields" do
      msg = %Message{}
      assert msg.context_id == nil
      assert msg.command == nil
      assert msg.data == nil
    end

    test "can be constructed with fields" do
      msg = %Message{context_id: 1, command: %{}, data: <<1, 2, 3>>}
      assert msg.context_id == 1
      assert msg.command == %{}
      assert msg.data == <<1, 2, 3>>
    end
  end
end

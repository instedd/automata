defmodule Aida.Expr.EvalTest do
  use ExUnit.Case
  alias Aida.Expr
  alias Aida.Expr.Context

  describe "eval" do
    test "literals" do
      assert eval("123") == 123
      assert eval("'foo'") == "foo"
    end

    test "arithmetic operations" do
      assert eval("1 + 2") == 3
      assert eval("3 - 2") == 1
      assert eval("2 * 3") == 6
      assert eval("8 div 4") == 2
      assert eval("5 mod 2") == 1
    end

    test "number comparisons" do
      assert eval("1 = 2") == false
      assert eval("1 != 2") == true
      assert eval("1 < 2") == true
      assert eval("1 <= 2") == true
      assert eval("1 > 2") == false
      assert eval("1 >= 2") == false
    end

    test "boolean operations" do
      assert eval("1 = 1 and 1 = 2") == false
      assert eval("1 = 1 and 2 = 2") == true
      assert eval("1 = 3 or 1 = 2") == false
      assert eval("1 = 1 or 1 = 2") == true
    end

    test "self" do
      assert eval(".", %Context{self: 42}) == 42
    end

    test "variables" do
      lookup_fn = fn ("foo") -> 42 end
      assert eval("${foo}", %Context{lookup: lookup_fn}) == 42
    end

    test "function calls" do
      assert eval("true()") == true
      assert eval("false()") == false

      lookup_fn = fn ("foo") -> [1, 2, 3] end
      context = %Context{lookup: lookup_fn}
      assert eval("selected(${foo}, 1)", context) == true
      assert eval("selected(${foo}, 'bar')", context) == false
    end
  end

  defp eval(code, context \\ %Context{}) do
    Expr.parse(code) |> Expr.eval(context)
  end
end

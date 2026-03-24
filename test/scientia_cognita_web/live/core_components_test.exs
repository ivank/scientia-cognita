# test/scientia_cognita_web/live/core_components_test.exs
defmodule ScientiaCognitaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1]

  describe "user_initials/1" do
    test "splits on dot — ivan.kerin@example.com → IK" do
      assert user_initials("ivan.kerin@example.com") == "IK"
    end

    test "splits on underscore — ivan_kerin@example.com → IK" do
      assert user_initials("ivan_kerin@example.com") == "IK"
    end

    test "no separator — ivantest@example.com → IV" do
      assert user_initials("ivantest@example.com") == "IV"
    end

    test "three segments — a.b.c@example.com → AB (only first two)" do
      assert user_initials("a.b.c@example.com") == "AB"
    end

    test "single character local part — a@example.com → AA" do
      assert user_initials("a@example.com") == "AA"
    end

    test "uppercases result" do
      assert user_initials("anna.brown@example.com") == "AB"
    end
  end
end

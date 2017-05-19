defmodule Sippet.URI.Test do
  use ExUnit.Case, async: true

  alias Sippet.URI

  doctest Sippet.URI

  test "equivalent" do
    a = URI.parse!("sip:%61lice@atlanta.com;transport=TCP")
    b = URI.parse!("sip:alice@AtLanTa.CoM;Transport=tcp")
    assert URI.equivalent(a, b)

    a = URI.parse!("sip:carol@chicago.com")
    b = URI.parse!("sip:carol@chicago.com;newparam=5")
    assert URI.equivalent(a, b)

    a = URI.parse!("sip:carol@chicago.com;security=on")
    b = URI.parse!("sip:carol@chicago.com;newparam=5")
    assert URI.equivalent(a, b)

    a =
      "sip:biloxi.com;transport=tcp;method=REGISTER?to=sip:bob%40biloxi.com"
      |> URI.parse!()
    b =
      "sip:biloxi.com;method=REGISTER;transport=tcp?to=sip:bob%40biloxi.com"
      |> URI.parse!()
    assert URI.equivalent(a, b)

    a = URI.parse!("sip:alice@atlanta.com?subject=project%20x&priority=urgent")
    b = URI.parse!("sip:alice@atlanta.com?priority=urgent&subject=project%20x")
    assert URI.equivalent(a, b)
  end

  test "not equivalent" do
    a = URI.parse!("SIP:ALICE@AtLanTa.CoM;Transport=udp")
    b = URI.parse!("sip:alice@AtLanTa.CoM;Transport=UDP")
    assert not URI.equivalent(a, b)

    a = URI.parse!("sip:bob@biloxi.com")
    b = URI.parse!("sip:bob@biloxi.com:5060")
    assert not URI.equivalent(a, b)

    a = URI.parse!("sip:bob@biloxi.com")
    b = URI.parse!("sip:bob@biloxi.com;transport=udp")
    assert not URI.equivalent(a, b)

    a = URI.parse!("sip:carol@chicago.com")
    b = URI.parse!("sip:carol@chicago.com?Subject=next%20meeting")
    assert not URI.equivalent(a, b)

    a = URI.parse!("sip:carol@chicago.com;security=on")
    b = URI.parse!("sip:carol@chicago.com;security=off")
    assert not URI.equivalent(a, b)
  end

  test "lazy equivalent" do
    a = URI.parse!("sip:bob@biloxi.com")
    b = URI.parse!("sip:bob@biloxi.com:5060")
    assert URI.lazy_equivalent(a, b)

    a = URI.parse!("sip:bob@biloxi.com;transport=UDP")
    b = URI.parse!("sip:bob@biloxi.com")
    assert URI.lazy_equivalent(a, b)

    a = URI.parse!("sip:bob@biloxi.com;transport=UDP")
    b = URI.parse!("sip:bob@biloxi.com:5060")
    assert URI.lazy_equivalent(a, b)
  end
end

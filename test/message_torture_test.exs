defmodule Sippet.Message.TortureTest do
  use ExUnit.Case, async: true

  alias Sippet.Message, as: Message
  alias Sippet.URI, as: URI

  test "tortuous invite" do
    message = """
    INVITE sip:vivekg@chair-dnrc.example.com;unknownparam SIP/2.0
    TO :
     sip:vivekg@chair-dnrc.example.com ;   tag    = 1918181833n
    from   : "J Rosenberg \\\\\\""       <sip:jdrosen@example.com>
      ;
      tag = 98asjd8
    MaX-fOrWaRdS: 0068
    Call-ID: wsinv.ndaksdj@192.0.2.1
    Content-Length   : 150
    cseq: 0009
      INVITE
    Via  : SIP  /   2.0
     /UDP
        192.0.2.2;branch=390skdjuw
    s :
    NewFangledHeader:   newfangled value
     continued newfangled value
    UnknownHeaderWithUnusualValue: ;;,,;;,;
    Content-Type: application/sdp
    Route:
     <sip:services.example.com;lr;unknownwith=value;unknown-no-value>
    v:  SIP  / 2.0  / TCP     spindle.example.com   ;
      branch  =   z9hG4bK9ikj8  ,
     SIP  /    2.0   / UDP  192.168.255.111   ; branch=
     z9hG4bK30239
    m:"Quoted string \\"\\"" <sip:jdrosen@example.com> ; newparam =
          newvalue ;
      secondparam ; q = 0.33

    """
    request = Message.parse!(message)

    assert Message.request?(request)

    assert request.start_line.method == :invite
    assert request.start_line.request_uri ==
      URI.parse("sip:vivekg@chair-dnrc.example.com;unknownparam")
    assert request.start_line.version == {2, 0}

    assert elem(request.headers.to, 0) == ""
    assert elem(request.headers.to, 1)
      URI.parse("sip:vivekg@chair-dnrc.example.com")
    assert elem(request.headers.to, 2) ==
      %{"tag" => "1918181833n"}

    assert elem(request.headers.from, 0) == "J Rosenberg \\\""
    assert elem(request.headers.from, 1) ==
      URI.parse("sip:jdrosen@example.com")
    assert elem(request.headers.from, 2) ==
      %{"tag" => "98asjd8"}

    assert request.headers.max_forwards == 68

    assert request.headers.call_id == "wsinv.ndaksdj@192.0.2.1"

    assert request.headers.content_length == 150

    assert request.headers.cseq == {9, :invite}

    [first_via|rest] = request.headers.via
    assert first_via ==
      {{2, 0}, :udp, {"192.0.2.2", 5060}, %{"branch" => "390skdjuw"}}
    
    [second_via|rest] = rest
    assert second_via ==
      {{2, 0}, :tcp, {"spindle.example.com", 5060}, %{"branch" => "z9hG4bK9ikj8"}}

    [third_via] = rest
    assert third_via ==
      {{2, 0}, :udp, {"192.168.255.111", 5060}, %{"branch" => "z9hG4bK30239"}}

    assert request.headers.subject == ""

    assert request.headers["NewFangledHeader"] ==
      ["newfangled value continued newfangled value"]

    assert request.headers["UnknownHeaderWithUnusualValue"] ==
      [";;,,;;,;"]

    assert request.headers.content_type == {{"application", "sdp"}, %{}}

    assert List.first(request.headers.route) ==
      {"", URI.parse("sip:services.example.com;lr;unknownwith=value;unknown-no-value"), %{}}

    assert List.first(request.headers.contact) ==
      {"Quoted string \"\"", URI.parse("sip:jdrosen@example.com"),
          %{"newparam" => "newvalue", "secondparam" => "", "q" => "0.33"}}
  end
end

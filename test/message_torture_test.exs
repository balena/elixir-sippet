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
             URI.parse!("sip:vivekg@chair-dnrc.example.com;unknownparam")

    assert request.start_line.version == {2, 0}

    assert elem(request.headers.to, 0) == ""
    assert elem(request.headers.to, 1)
    URI.parse!("sip:vivekg@chair-dnrc.example.com")
    assert elem(request.headers.to, 2) == %{"tag" => "1918181833n"}

    assert elem(request.headers.from, 0) == "J Rosenberg \\\""
    assert elem(request.headers.from, 1) == URI.parse!("sip:jdrosen@example.com")
    assert elem(request.headers.from, 2) == %{"tag" => "98asjd8"}

    assert request.headers.max_forwards == 68

    assert request.headers.call_id == "wsinv.ndaksdj@192.0.2.1"

    assert request.headers.content_length == 150

    assert request.headers.cseq == {9, :invite}

    [first_via | rest] = request.headers.via
    assert first_via == {{2, 0}, :udp, {"192.0.2.2", 5060}, %{"branch" => "390skdjuw"}}

    [second_via | rest] = rest

    assert second_via ==
             {{2, 0}, :tcp, {"spindle.example.com", 5060}, %{"branch" => "z9hG4bK9ikj8"}}

    [third_via] = rest
    assert third_via == {{2, 0}, :udp, {"192.168.255.111", 5060}, %{"branch" => "z9hG4bK30239"}}

    assert request.headers.subject == ""

    assert request.headers["NewFangledHeader"] == ["newfangled value continued newfangled value"]

    assert request.headers["UnknownHeaderWithUnusualValue"] == [";;,,;;,;"]

    assert request.headers.content_type == {{"application", "sdp"}, %{}}

    assert List.first(request.headers.route) ==
             {"", URI.parse!("sip:services.example.com;lr;unknownwith=value;unknown-no-value"),
              %{}}

    assert List.first(request.headers.contact) ==
             {"Quoted string \"\"", URI.parse!("sip:jdrosen@example.com"),
              %{"newparam" => "newvalue", "secondparam" => "", "q" => "0.33"}}
  end

  test "wide range of characters" do
    message = """
    !interesting-Method0123456789_*+`.%indeed'~ sip:1_unusual.URI~(to-be!sure)&isn't+it$/crazy?,/;;*:&it+has=1,weird!*pas$wo~d_too.(doesn't-it)@example.com SIP/2.0
    Via: SIP/2.0/TCP host1.example.com;branch=z9hG4bK-.!%66*_+`'~
    To: "BEL: NUL:\u{0000} DEL:" <sip:1_unusual.URI~(to-be!sure)&isn't+it$/crazy?,/;;*@example.com>
    From: token1~` token2'+_ token3*%!.- <sip:mundane@example.com>;fromParam''~+*_!.-%="Ñ\u{20AC}Ð°Ð±Ð¾Ñ\u{2012}Ð°Ñ×ÑÐ¸Ð¹";tag=_token~1'+`*%!-.
    Call-ID: intmeth.word%ZK-!.*_+'@word`~)(><:\/"][?}{
    CSeq: 139122385 !interesting-Method0123456789_*+`.%indeed'~
    Max-Forwards: 255
    extensionHeader-!.%*+_`'~: ï»¿å¤§åé»
    Content-Length: 0

    """

    request = Message.parse!(message)

    assert Message.request?(request)

    assert request.start_line.method == "!interesting-Method0123456789_*+`.%indeed'~"

    assert request.start_line.request_uri ==
             URI.parse!(
               "sip:1_unusual.URI~(to-be!sure)&isn't+it$/crazy?,/;;*:&it+has=1,weird!*pas$wo~d_too.(doesn't-it)@example.com"
             )

    assert request.start_line.version == {2, 0}

    assert List.first(request.headers.via) ==
             {{2, 0}, :tcp, {"host1.example.com", 5060}, %{"branch" => "z9hG4bK-.!%66*_+`'~"}}

    assert request.headers.to ==
             {"BEL: NUL:\u{0000} DEL:",
              URI.parse!("sip:1_unusual.URI~(to-be!sure)&isn't+it$/crazy?,/;;*@example.com"), %{}}

    # Note that the parser will transform parameters into lowercase strings
    assert request.headers.from ==
             {"token1~` token2'+_ token3*%!.-", URI.parse!("sip:mundane@example.com"),
              %{
                "fromparam''~+*_!.-%" => "Ñ\u{20AC}Ð°Ð±Ð¾Ñ\u{2012}Ð°Ñ×ÑÐ¸Ð¹",
                "tag" => "_token~1'+`*%!-."
              }}

    assert request.headers.call_id == "intmeth.word%ZK-!.*_+'@word`~)(><:\/\"][?}{"

    assert request.headers.cseq == {139_122_385, "!interesting-Method0123456789_*+`.%indeed'~"}

    assert request.headers.max_forwards == 255

    assert request.headers["extensionHeader-!.%*+_`'~"] == ["ï»¿å¤§åé»"]

    assert request.headers.content_length == 0
  end

  test "use of % when it is not an escape" do
    message = """
    RE%47IST%45R sip:registrar.example.com SIP/2.0
    To: "%Z%45" <sip:resource@example.com>
    From: "%Z%45" <sip:resource@example.com>;tag=f232jadfj23
    Call-ID: esc02.asdfnqwo34rq23i34jrjasdcnl23nrlknsdf
    Via: SIP/2.0/TCP host.example.com;branch=z9hG4bK209%fzsnel234
    CSeq: 29344 RE%47IST%45R
    Max-Forwards: 70
    Contact: <sip:alias1@host1.example.com>
    C%6Fntact: <sip:alias2@host2.example.com>
    Contact: <sip:alias3@host3.example.com>
    l: 0

    """

    request = Message.parse!(message)

    assert Message.request?(request)

    assert request.start_line.method == "RE%47IST%45R"

    assert elem(request.headers.to, 0) == "%Z%45"

    assert elem(List.first(request.headers.via), 3)["branch"] == "z9hG4bK209%fzsnel234"

    assert elem(request.headers.cseq, 1) == "RE%47IST%45R"

    assert Map.has_key?(request.headers, "C%6Fntact")

    assert length(request.headers.contact) == 2
  end

  test "message with no LWS between display name and <" do
    message = """
    OPTIONS sip:user@example.com SIP/2.0
    To: sip:user@example.com
    From: caller<sip:caller@example.com>;tag=323
    Max-Forwards: 70
    Call-ID: lwsdisp.1234abcd@funky.example.com
    CSeq: 60 OPTIONS
    Via: SIP/2.0/UDP funky.example.com;branch=z9hG4bKkdjuw
    l: 0

    """

    request = Message.parse!(message)

    assert elem(request.headers.from, 0) == "caller"
  end

  test "long values in header fields" do
    message = """
    INVITE sip:user@example.com SIP/2.0
    To: "I have a user name of extremeextremeextremeextremeextremeextremeextremeextremeextremeextreme proportion"<sip:user@example.com:6000;unknownparam1=verylonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglongvalue;longparamnamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamename=shortvalue;verylonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglongParameterNameWithNoValue>
    F: sip:amazinglylongcallernameamazinglylongcallernameamazinglylongcallernameamazinglylongcallernameamazinglylongcallername@example.net;tag=12982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982982424;unknownheaderparamnamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamenamename=unknowheaderparamvaluevaluevaluevaluevaluevaluevaluevaluevaluevaluevaluevaluevaluevaluevalue;unknownValuelessparamnameparamnameparamnameparamnameparamnameparamnameparamnameparamnameparamnameparamname
    Call-ID: longreq.onereallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallylongcallid
    CSeq: 3882340 INVITE
    Unknown-LongLongLongLongLongLongLongLongLongLongLongLongLongLongLongLongLongLongLongLong-Name: unknown-longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglong-value; unknown-longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglong-parameter-name = unknown-longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglong-parameter-value
    Via: SIP/2.0/TCP sip33.example.com
    v: SIP/2.0/TCP sip32.example.com
    V: SIP/2.0/TCP sip31.example.com
    Via: SIP/2.0/TCP sip30.example.com
    ViA: SIP/2.0/TCP sip29.example.com
    VIa: SIP/2.0/TCP sip28.example.com
    VIA: SIP/2.0/TCP sip27.example.com
    via: SIP/2.0/TCP sip26.example.com
    viA: SIP/2.0/TCP sip25.example.com
    vIa: SIP/2.0/TCP sip24.example.com
    vIA: SIP/2.0/TCP sip23.example.com
    V :  SIP/2.0/TCP sip22.example.com
    v :  SIP/2.0/TCP sip21.example.com
    V  : SIP/2.0/TCP sip20.example.com
    v  : SIP/2.0/TCP sip19.example.com
    Via : SIP/2.0/TCP sip18.example.com
    Via  : SIP/2.0/TCP sip17.example.com
    Via: SIP/2.0/TCP sip16.example.com
    Via: SIP/2.0/TCP sip15.example.com
    Via: SIP/2.0/TCP sip14.example.com
    Via: SIP/2.0/TCP sip13.example.com
    Via: SIP/2.0/TCP sip12.example.com
    Via: SIP/2.0/TCP sip11.example.com
    Via: SIP/2.0/TCP sip10.example.com
    Via: SIP/2.0/TCP sip9.example.com
    Via: SIP/2.0/TCP sip8.example.com
    Via: SIP/2.0/TCP sip7.example.com
    Via: SIP/2.0/TCP sip6.example.com
    Via: SIP/2.0/TCP sip5.example.com
    Via: SIP/2.0/TCP sip4.example.com
    Via: SIP/2.0/TCP sip3.example.com
    Via: SIP/2.0/TCP sip2.example.com
    Via: SIP/2.0/TCP sip1.example.com
    Via: SIP/2.0/TCP host.example.com;received=192.0.2.5;branch=verylonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglonglongbranchvalue
    Max-Forwards: 70
    Contact: <sip:amazinglylongcallernameamazinglylongcallernameamazinglylongcallernameamazinglylongcallernameamazinglylongcallername@host5.example.net>
    Content-Type: application/sdp
    l: 150

    """

    request = Message.parse!(message)

    assert length(request.headers.via) == 34

    assert request.headers.call_id ==
             "longreq.onereallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallyreallylongcallid"
  end
end

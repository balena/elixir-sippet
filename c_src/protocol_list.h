// Copyright (c) 2013 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file intentionally does not have header guards, it's included inside
// a macro to generate enum.
//
// This file contains the list of SIP protocols. Taken from IANA Session
// Initiation Protocol (SIP) Parameters.
// http://www.iana.org/assignments/sip-parameters/sip-parameters.xhtml

#ifndef SIP_PROTOCOL
#error "SIP_PROTOCOL should be defined before including this file"
#endif

// All supported protocols must be kept in lexicographical order
// of their header names.

SIP_PROTOCOL(AMQP)
SIP_PROTOCOL(DCCP)
SIP_PROTOCOL(DTLS)
SIP_PROTOCOL(SCTP)
SIP_PROTOCOL(STOMP)
SIP_PROTOCOL(TCP)
SIP_PROTOCOL(TLS)
SIP_PROTOCOL(UDP)
SIP_PROTOCOL(WS)
SIP_PROTOCOL(WSS)


// Copyright (c) 2017 The Sippet Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file intentionally does not have header guards, it's included inside
// a macro to generate enum.
//
// This file contains the list of SIP methods. Taken from IANA Session
// Initiation Protocol (SIP) Parameters.
// http://www.iana.org/assignments/sip-parameters/sip-parameters.xhtml

#ifndef SIP_METHOD
#error "SIP_METHOD should be defined before including this file"
#endif

// All supported methods must be kept in lexicographical order
// of their header names.

SIP_METHOD(ACK)
SIP_METHOD(BYE)
SIP_METHOD(CANCEL)
SIP_METHOD(INFO)
SIP_METHOD(INVITE)
SIP_METHOD(MESSAGE)
SIP_METHOD(NOTIFY)
SIP_METHOD(OPTIONS)
SIP_METHOD(PRACK)
SIP_METHOD(PUBLISH)
SIP_METHOD(PULL)
SIP_METHOD(PUSH)
SIP_METHOD(REFER)
SIP_METHOD(REGISTER)
SIP_METHOD(STORE)
SIP_METHOD(SUBSCRIBE)
SIP_METHOD(UPDATE)

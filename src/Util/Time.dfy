// Copyright Amazon.com Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

include "../StandardLibrary/StandardLibrary.dfy"
include "../StandardLibrary/UInt.dfy"

module Time {
  import opened StandardLibrary
  import opened UInt = StandardLibrary.UInt

  // Returns the number of seconds since some fixed-as-long-as-this-program-is-running moment in the past
  method {:extern "TimeUtil.Time", "CurrentRelativeTime"} GetCurrent() returns (seconds: uint64)
}

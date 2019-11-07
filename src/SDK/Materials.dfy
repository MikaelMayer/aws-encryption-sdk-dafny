include "../StandardLibrary/StandardLibrary.dfy"
include "../StandardLibrary/UInt.dfy"
include "./AlgorithmSuite.dfy"
include "../Util/UTF8.dfy"


module Materials {
  import opened StandardLibrary
  import opened UInt = StandardLibrary.UInt
  import UTF8
  import AlgorithmSuite

  type EncryptionContext = seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>

  function method GetKeysFromEncryptionContext(encryptionContext: EncryptionContext): set<UTF8.ValidUTF8Bytes> {
    set i | 0 <= i < |encryptionContext| :: encryptionContext[i].0
  }

  const EC_PUBLIC_KEY_FIELD := UTF8.Encode("aws-crypto-public-key").value
  ghost const ReservedKeyValues := { EC_PUBLIC_KEY_FIELD }

  datatype EncryptedDataKey = EncryptedDataKey(providerID : UTF8.ValidUTF8Bytes,
                                               providerInfo : seq<uint8>,
                                               ciphertext : seq<uint8>)
  {
    predicate Valid() {
      |providerID| < UINT16_LIMIT &&
      |providerInfo| < UINT16_LIMIT &&
      |ciphertext| < UINT16_LIMIT
    }
  }

  // TODO: Add keyring trace
  class EncryptionMaterials {
    var algorithmSuiteID: AlgorithmSuite.ID
    var encryptedDataKeys: seq<EncryptedDataKey>
    var encryptionContext: EncryptionContext
    var plaintextDataKey: Option<seq<uint8>>
    var signingKey: Option<seq<uint8>>

    predicate Valid()
      reads this
    {
      && (|encryptedDataKeys| != 0 ==> plaintextDataKey.Some?)
      && (plaintextDataKey.None? || ValidPlaintextDataKey(plaintextDataKey.get))
      && (forall i :: 0 <= i < |encryptedDataKeys| ==> encryptedDataKeys[i].Valid())
    }

    predicate ValidPlaintextDataKey(pdk: seq<uint8>)
      reads this
    {
      |pdk| == this.algorithmSuiteID.KDFInputKeyLength()
    }

    constructor(algorithmSuiteID: AlgorithmSuite.ID,
                encryptedDataKeys: seq<EncryptedDataKey>,
                encryptionContext: EncryptionContext,
                plaintextDataKey: Option<seq<uint8>>,
                signingKey: Option<seq<uint8>>)
      requires |encryptedDataKeys| > 0 ==> plaintextDataKey.Some?
      requires forall i :: 0 <= i < |encryptedDataKeys| ==> encryptedDataKeys[i].Valid()
      requires plaintextDataKey.None? || |plaintextDataKey.get| == algorithmSuiteID.KDFInputKeyLength()
      ensures Valid()
      ensures this.algorithmSuiteID == algorithmSuiteID
      ensures this.encryptedDataKeys == encryptedDataKeys
      ensures this.encryptionContext == encryptionContext
      ensures this.plaintextDataKey == plaintextDataKey
      ensures this.signingKey == signingKey
    {
      this.algorithmSuiteID := algorithmSuiteID;
      this.encryptedDataKeys := encryptedDataKeys;
      this.encryptionContext := encryptionContext;
      this.plaintextDataKey := plaintextDataKey;
      this.signingKey := signingKey;
    }

    method SetPlaintextDataKey(dataKey: seq<uint8>)
      requires Valid()
      requires plaintextDataKey.None?
      requires |dataKey| == algorithmSuiteID.KDFInputKeyLength()
      modifies `plaintextDataKey
      ensures Valid()
      ensures plaintextDataKey == Some(dataKey)
    {
      plaintextDataKey := Some(dataKey);
    }

    method AppendEncryptedDataKey(edk: EncryptedDataKey)
      requires Valid() && edk.Valid()
      requires plaintextDataKey.Some?
      modifies `encryptedDataKeys
      ensures Valid()
      ensures encryptedDataKeys == old(encryptedDataKeys) + [edk]
    {
      encryptedDataKeys := encryptedDataKeys + [edk]; // TODO: Determine if this is a performance issue
    }
  }

  // TODO: Add keyring trace
  class DecryptionMaterials {
    var algorithmSuiteID: AlgorithmSuite.ID
    var encryptionContext: EncryptionContext
    var plaintextDataKey: Option<seq<uint8>>
    var verificationKey: Option<seq<uint8>>

    predicate Valid()
      reads this
    {
      plaintextDataKey.None? || ValidPlaintextDataKey(plaintextDataKey.get)
    }

    predicate ValidPlaintextDataKey(pdk: seq<uint8>)
      reads this
    {
      |pdk| == this.algorithmSuiteID.KDFInputKeyLength()
    }

    constructor(algorithmSuiteID: AlgorithmSuite.ID,
                encryptionContext: EncryptionContext,
                plaintextDataKey: Option<seq<uint8>>,
                verificationKey: Option<seq<uint8>>)
      requires plaintextDataKey.None? || |plaintextDataKey.get| == algorithmSuiteID.KDFInputKeyLength()
      ensures Valid()
      ensures this.algorithmSuiteID == algorithmSuiteID
      ensures this.encryptionContext == encryptionContext
      ensures this.plaintextDataKey == plaintextDataKey
      ensures this.verificationKey == verificationKey
    {
      this.algorithmSuiteID := algorithmSuiteID;
      this.encryptionContext := encryptionContext;
      this.plaintextDataKey := plaintextDataKey;
      this.verificationKey := verificationKey;
    }

    method setPlaintextDataKey(dataKey: seq<uint8>)
      requires Valid()
      requires plaintextDataKey.None?
      requires |dataKey| == algorithmSuiteID.KDFInputKeyLength()
      modifies `plaintextDataKey
      ensures Valid()
      ensures plaintextDataKey == Some(dataKey)
    {
      plaintextDataKey := Some(dataKey);
    }

    method setVerificationKey(verifKey: seq<uint8>)
    requires Valid()
    requires verificationKey.None?
    modifies `verificationKey
    ensures Valid()
    ensures verificationKey == Some(verifKey) {
      verificationKey := Some(verifKey);
    }
  }

    //TODO: Review this code.
    function method naive_merge<T> (x : seq<T>, y : seq<T>, lt : (T, T) -> bool) : seq<T>
    {
        if |x| == 0 then y
        else if |y| == 0 then x
        else if lt(x[0], y[0]) then [x[0]] + naive_merge(x[1..], y, lt)
        else [y[0]] + naive_merge(x, y[1..], lt)
    }

    function method naive_merge_sort<T> (x : seq<T>, lt : (T, T) -> bool) : seq<T>
    {
        if |x| < 2 then x else
        var t := |x| / 2; naive_merge(naive_merge_sort(x[..t], lt), naive_merge_sort(x[t..], lt), lt)

    }

    function method memcmp_le (a : seq<uint8>, b : seq<uint8>, len : nat) : (res : Option<bool>)
        requires |a| >= len
        requires |b| >= len {
        if len == 0 then None else if a[0] != b[0] then Some(a[0] < b[0]) else memcmp_le (a[1..], b[1..], len - 1)
    }

    predicate method lex_lt(b : seq<uint8>, a : seq<uint8>)
    {
        match memcmp_le(a,b, if |a| < |b| then |a| else |b|) {
        case Some(b) => !b
        case None => !(|a| <= |b|)
        }
    }

    predicate method lt_keys(b : (seq<uint8>, seq<uint8>), a : (seq<uint8>, seq<uint8>)) {
        lex_lt(b.0, a.0)
    }

    function method EncCtxFlatten (x : seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>): UTF8.ValidUTF8Bytes {
        if x == [] then [] else
        x[0].0 + x[0].1 + EncCtxFlatten(x[1..])
    }

    function method FlattenSortEncCtx(x : seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>): UTF8.ValidUTF8Bytes
    {
        EncCtxFlatten(naive_merge_sort(x, lt_keys))
    }

    function method EncCtxLookup(x : seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>, k : UTF8.ValidUTF8Bytes): Option<UTF8.ValidUTF8Bytes>
    {
        if |x| == 0 then None else
        if x[0].0 == k then Some(x[0].1) else EncCtxLookup(x[1..], k)
    }

    function method EncCtxOfStrings(x : seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>): seq<(UTF8.ValidUTF8Bytes, UTF8.ValidUTF8Bytes)>  {
        if x == [] then [] else
        [(x[0].0, x[0].1)] + EncCtxOfStrings(x[1..])
    }
}

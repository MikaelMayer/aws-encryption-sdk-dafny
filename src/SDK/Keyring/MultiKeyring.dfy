include "../../StandardLibrary/StandardLibrary.dfy"
include "../../StandardLibrary/UInt.dfy"
include "../AlgorithmSuite.dfy"
include "./Defs.dfy"
include "../../Crypto/Cipher.dfy"
include "../../Crypto/Random.dfy"
include "../../Crypto/RSAEncryption.dfy"
include "../Materials.dfy"

module MultiKeyringDef {
    import opened KeyringDefs
    import opened StandardLibrary
    import opened UInt = StandardLibrary.UInt
    import opened Cipher
    import AlgorithmSuite
    import RSA = RSAEncryption
    import Mat = Materials

    function childrenRepr (xs : seq<Keyring>) : (res : set<object>) reads (set i | 0 <= i < |xs| :: xs[i])
        ensures forall i :: i in xs ==> i in res && i.Repr <= res
        decreases |xs|
    {
        if xs == [] then {} else
        childrenRepr(xs[1..]) + {xs[0]} + xs[0].Repr
    }

    class MultiKeyring extends Keyring {
        const generator : Keyring?
        const children : seq<Keyring>
        constructor (g : Keyring?, c : seq<Keyring>) ensures generator == g ensures children == c
            requires g != null ==> g.Valid()
            requires forall i :: 0 <= i < |c| ==> c[i].Valid()
            requires DisjointReprsRec({}, ChildKeyrings(g, c))
            ensures Valid()
        {
            generator := g;
            children := c;
            new;
            Repr := ReprDefn();
        }

        predicate Valid() reads this, Repr {
            (generator != null ==> generator in Repr  && generator.Repr <= Repr && generator.Valid())  &&
            (forall j :: 0 <= j < |children| ==> children[j] in Repr && children[j].Repr <= Repr && children[j].Valid()) &&
            Repr == ReprDefn() &&
            DisjointReprsRec({}, ChildKeyrings(generator, children))
        }

        static function ChildKeyrings(g: Keyring?, c: seq<Keyring>): seq<Keyring> {
            (if g != null then [g] else []) + c
        }

        function ReprDefn(): set<object> reads this, generator, children {
            {this} + (if generator != null then {generator} + generator.Repr else {}) + childrenRepr(children[..])
        }

        static predicate DisjointReprsRec(r: set<object>, s: seq<Keyring>) 
                reads r, s, set i,o | 0 <= i < |s| && o in s[i].Repr :: o
                decreases |s|
        {
            if |s| == 0 then
                true
            else
                (r !! s[0].Repr) && DisjointReprsRec(r + s[0].Repr, s[1..])
        }

        method OnEncryptRec(input: Mat.ValidEncryptionMaterialsInput, output: Mat.ValidDataKey, i: int) returns (res: Result<Mat.ValidDataKey>)
            requires Valid()
            requires 0 <= i <= |children|
            requires Mat.ValidOnEncryptResult(input, output)
            requires input.plaintextDataKey.Some? && input.plaintextDataKey.get == output.plaintextDataKey
            ensures Valid()
            ensures forall i :: 0 <= i < |children| ==> children[i].Valid()
            ensures res.Success? ==> Mat.ValidOnEncryptResult(input, res.value)
            decreases |children| - i
        {
            if i == |children| {
                return Success(output);
            }
            else {
                var r :- children[i].OnEncrypt(input);
                if r.Some? {
                    Materials.ValidOnEncryptResultImpliesSameAlgorithmSuiteID(input, r.get);
                }
                var newOutput := if r.Some? then
                        Mat.MergingResults(input, output, r.get);
                        Mat.MergeDataKeys(output, r.get) 
                    else output;
                var a := OnEncryptRec(input, newOutput, i + 1);
                return a;
            }
        }

        method OnEncrypt(encMat : Mat.ValidEncryptionMaterialsInput) returns (res: Result<Option<Mat.ValidDataKey>>)
            requires Valid()
            ensures Valid()
            ensures res.Success? && res.value.Some? ==> Materials.ValidOnEncryptResult(encMat, res.value.get)
        {
            var initialDataKey: Option<Mat.ValidDataKey> := None;
            if encMat.plaintextDataKey.Some? {
                initialDataKey := Some(Mat.DataKey(encMat.algorithmSuiteID, encMat.plaintextDataKey.get, []));
            }
            
            if generator != null {
                initialDataKey :- generator.OnEncrypt(encMat);
                if initialDataKey.Some? {
                    Materials.ValidOnEncryptResultImpliesSameAlgorithmSuiteID(encMat, initialDataKey.get);
                }
            }
            if initialDataKey.None? {
                return Failure("Bad state: data key not found");
            }
            var input := Mat.EncryptionMaterialsInput(encMat.algorithmSuiteID, encMat.encryptionContext, Some(initialDataKey.get.plaintextDataKey));
            var result :- OnEncryptRec(input, initialDataKey.get, 0);
            res := Success(Some(result));
        }

        method OnDecryptRec(algorithmSuiteID: AlgorithmSuite.ID, encryptionContext: Materials.EncryptionContext, edks: seq<Materials.EncryptedDataKey>, i : int)
            returns (res: Result<Option<Materials.ValidDataKey>>)
            requires 0 <= i <= |children|
            requires Valid()
            ensures Valid()
            ensures |edks| == 0 ==> res.Success? && res.value.None?
            ensures res.Success? && res.value.Some? ==> res.value.get.encryptedDataKeys == edks
            decreases |children| - i
        {
            if i == |children| {
                return Success(None);
            }
            else {
                var y :- children[i].OnDecrypt(algorithmSuiteID, encryptionContext, edks);
                match y {
                    case Some(r) => {
                        return Success(Some(r));
                    }
                    case None => {
                        res := OnDecryptRec(algorithmSuiteID, encryptionContext, edks, i + 1);
                    }
                }

            }
        }

        method OnDecrypt(algorithmSuiteID: AlgorithmSuite.ID, encryptionContext: Materials.EncryptionContext, edks: seq<Materials.EncryptedDataKey>)
            returns (res: Result<Option<Materials.ValidDataKey>>)
            requires Valid()
            ensures Valid()
            ensures |edks| == 0 ==> res.Success? && res.value.None?
            ensures res.Success? && res.value.Some? ==> res.value.get.encryptedDataKeys == edks
        {
            if generator != null {
                var result :- generator.OnDecrypt(algorithmSuiteID, encryptionContext, edks);
                if result.Some? {
                    return Success(result);
                }
            }
            res := OnDecryptRec(algorithmSuiteID, encryptionContext, edks, 0);
        }
    }
}

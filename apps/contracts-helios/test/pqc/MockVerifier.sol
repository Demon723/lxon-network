// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// Stands in for the Plan 5 ML-DSA verifier contract. Deliberately able to answer in every
/// shape a real dependency can: a true bool, a false bool, nothing at all, a reversion, and
/// a short/invalid word. The point is not to verify lattice signatures -- it is to prove the
/// bridge treats those five differently, and specifically that "it returned something" is
/// never read as "it accepted".
///
/// `view` and stateless on purpose: the bridge reaches this with STATICCALL (that is what
/// makes a verifier unable to move money), so a counter here would turn every behaviour into
/// a static-context revert and the tests would pass for the wrong reason. Call counting,
/// where it is needed, happens on the registry mock.
contract MockVerifier {
    enum Behaviour { Accept, Reject, EmptyReturn, Revert, ShortReturn }

    Behaviour public behaviour;

    function setBehaviour(Behaviour b) external {
        behaviour = b;
    }

    function verify(address pkBlob, bytes calldata message, bytes calldata signature)
        external view returns (bool accepted)
    {
        pkBlob; message; signature;   // the mock's answer does not depend on them
        if (behaviour == Behaviour.Accept) return true;
        if (behaviour == Behaviour.Reject) return false;
        if (behaviour == Behaviour.Revert) revert("verifier exploded");
        if (behaviour == Behaviour.ShortReturn) {
            // 3 bytes of return data: a payload nobody can decode as a bool word.
            assembly {
                mstore(0, 0x112233)
                return(0, 3)
            }
        }
        // EmptyReturn: return nothing at all. A classifier that treats this as success is the
        // codeless-target bug again -- an empty account answers 0x and looks like a pass.
        assembly {
            return(0, 0)
        }
    }
}

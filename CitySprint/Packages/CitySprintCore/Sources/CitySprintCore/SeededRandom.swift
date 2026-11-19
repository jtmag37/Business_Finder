import Foundation

/// Deterministic, platform-independent PRNG (SplitMix64).
///
/// Swift's standard `random(in:using:)` algorithms are not guaranteed to stay the
/// same across OS/toolchain releases. The daily challenge must be identical for
/// every player, so all level generation uses only the helpers below, whose
/// output depends solely on the seed.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform double in [lo, hi).
    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    public mutating func range(_ r: ClosedRange<Double>) -> Double {
        range(r.lowerBound, r.upperBound)
    }

    /// Uniform integer in [0, upperBound). `upperBound` must be > 0.
    public mutating func int(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Deterministic Fisher–Yates shuffle.
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = int(i + 1)
            array.swapAt(i, j)
        }
    }
}

/// Stable 64-bit FNV-1a hash. `String.hashValue` is randomized per process, so it
/// must never be used for seeds.
public enum StableHash {
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

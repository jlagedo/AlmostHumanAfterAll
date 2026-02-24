import Foundation
import CryptoKit

enum LastFmSigning {
    /// Generate an API signature for Last.fm API calls.
    ///
    /// Algorithm: sort parameters alphabetically by key, concatenate as key+value pairs
    /// (no separators), append the shared secret, then MD5 hash the result.
    static func sign(params: [String: String], secret: String) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let concatenated = sorted.map { "\($0.key)\($0.value)" }.joined() + secret
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

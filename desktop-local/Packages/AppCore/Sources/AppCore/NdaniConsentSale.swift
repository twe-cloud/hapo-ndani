import Foundation
import CryptoKit

public enum NdaniConsentSaleError: Error { case invalidSummary, invalidConsent, invalidOffer }

/// A per-use user signing key is supplied by the caller. This creates no
/// production credential, stores no key, and proves no buyer identity or KYC.
public struct NdaniConsentEnvelope: Sendable {
    public let participant: String
    public let payload: String
    public let signature: String

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func make(key: Curve25519.Signing.PrivateKey, offerID: String,
                            termsSHA256: String, summary: String,
                            explicitConsent: Bool, userAuthored: Bool,
                            timestamp: Int, retentionUntil: Int, nonce: String) throws -> Self {
        guard (1...1200).contains(summary.unicodeScalars.count) else { throw NdaniConsentSaleError.invalidSummary }
        guard explicitConsent, userAuthored, !offerID.isEmpty, termsSHA256.count == 64,
              nonce.count >= 16, retentionUntil > timestamp else { throw NdaniConsentSaleError.invalidConsent }
        let participant = base64url(key.publicKey.rawRepresentation)
        let fields: [String: Any] = ["participant": participant, "offer_id": offerID,
            "terms_sha256": termsSHA256, "summary": summary, "explicit_consent": true,
            "user_authored": true, "timestamp": timestamp, "retention_until": retentionUntil, "nonce": nonce]
        // Sign the exact transmitted bytes. Server verifies those bytes and
        // rejects duplicate JSON keys rather than signing a reserialized object.
        let raw = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        return Self(participant: participant, payload: base64url(raw), signature: base64url(try key.signature(for: raw)))
    }

    public var json: [String: String] { ["participant": participant, "payload": payload, "signature": signature] }
    public var requestSHA256: String? {
        guard let raw = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - payload.count % 4) % 4)) else { return nil }
        return SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
    }

    public func matches(participantID: String, offerID: String, summary: String) -> Bool {
        guard participant == participantID,
              let raw = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - payload.count % 4) % 4)),
              let fields = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        else { return false }
        return fields["offer_id"] as? String == offerID && fields["summary"] as? String == summary
    }
}

public enum NdaniOfferSchema {
    /// Explicit schema failure rather than silently dropping offers.
    public static func normalize(_ input: [String: Any]) throws -> [String: Any] {
        var result = input
        for (snake, camel) in [("payout_usd", "payoutUSD"), ("data_type", "dataType"),
                                ("buyer_verified", "buyerVerified"), ("spots_left", "spotsLeft"), ("expires_at", "expiresAt")] {
            if let a = input[snake], let b = input[camel], !NSDictionary(dictionary: ["v": a]).isEqual(to: ["v": b]) {
                throw NdaniConsentSaleError.invalidOffer
            }
            if result[snake] == nil { result[snake] = input[camel] }
        }
        guard let payout = result["payout_usd"] as? Double, payout.isFinite, payout >= 0 else { throw NdaniConsentSaleError.invalidOffer }
        for key in ["id", "buyer", "title", "description", "data_type"] {
            guard let value = result[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NdaniConsentSaleError.invalidOffer }
        }
        guard ["writing-style", "topic-interests", "work-patterns", "language-use"].contains(result["data_type"] as! String) else { throw NdaniConsentSaleError.invalidOffer }
        return result
    }
}

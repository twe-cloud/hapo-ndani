import Foundation
import CryptoKit
import Testing
@testable import AppCore

struct NdaniConsentSaleTests {
    @Test func signsExactBytesAndMatchesSource() throws {
        let key = Curve25519.Signing.PrivateKey()
        let e = try NdaniConsentEnvelope.make(key: key, offerID: "fixture", termsSHA256: String(repeating: "a", count: 64), summary: "synthetic", explicitConsent: true, userAuthored: true, timestamp: 1000, retentionUntil: 1500, nonce: "fixture-nonce-0001")
        #expect(e.matches(participantID: e.participant, offerID: "fixture", summary: "synthetic"))
        #expect(!e.matches(participantID: e.participant, offerID: "fixture", summary: "tampered"))
        func decode(_ s: String) -> Data { Data(base64Encoded: s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4-s.count%4)%4))! }
        #expect(key.publicKey.isValidSignature(decode(e.signature), for: decode(e.payload)))
    }
    @Test func scalarLimitAndExplicitConsent() throws {
        let key = Curve25519.Signing.PrivateKey()
        func make(_ text: String, _ consent: Bool = true) throws -> NdaniConsentEnvelope {
            try NdaniConsentEnvelope.make(key: key, offerID: "fixture", termsSHA256: String(repeating: "a", count: 64), summary: text, explicitConsent: consent, userAuthored: true, timestamp: 1000, retentionUntil: 1500, nonce: "fixture-nonce-0001")
        }
        _ = try make(String(repeating: "🙂", count: 1200))
        #expect(throws: NdaniConsentSaleError.self) { try make(String(repeating: "🙂", count: 1201)) }
        #expect(throws: NdaniConsentSaleError.self) { try make("synthetic", false) }
    }
    @Test func schemaCompatibilityAndConflict() throws {
        let a: [String: Any] = ["id":"fixture","buyer":"fixture","title":"fixture","description":"fixture","payoutUSD":1.5,"dataType":"language-use"]
        let normalized = try NdaniOfferSchema.normalize(a)
        #expect(normalized["payout_usd"] as? Double == 1.5)
        var b=a; b["payout_usd"]=2.0
        #expect(throws: NdaniConsentSaleError.self) { try NdaniOfferSchema.normalize(b) }
        var c=a; c.removeValue(forKey:"payoutUSD")
        #expect(throws: NdaniConsentSaleError.self) { try NdaniOfferSchema.normalize(c) }
    }
    @MainActor @Test func actualClientHoldsUnsignedAndOversized() async {
        let market = NdaniMarketplace(backendBase: "https://invalid.example")
        await market.submit(participantID: "fixture", offerID: "fixture", dataType: "language-use", title: "fixture", summary: "synthetic")
        #expect(market.lastError?.contains("signed per-offer") == true)
        #expect(market.lastSubmission == nil)
        await market.submit(participantID: "fixture", offerID: "fixture", dataType: "language-use", title: "fixture", summary: String(repeating: "a", count: 1201))
        #expect(market.lastError?.contains("1200") == true)
    }
    @MainActor @Test func actualClientNormalizesOffersAndKeepsMissingBalanceUnknown() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConsentFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let market = NdaniMarketplace(backendBase: "https://invalid.example")
        await market.fetchOffers(session: session)
        #expect(market.availableOffers.count == 1)
        #expect(market.availableOffers.first?.payoutUSD == 1.5)
        await market.fetchBalance(participantID: "fixture", signature: "fixture", session: session)
        #expect(market.balance == nil)
        #expect(market.lastError?.contains("not zero") == true)
    }
    @MainActor @Test func actualSignedSubmitRequiresSuccessfulBoundMinimalReceipt() async throws {
        let e = try NdaniConsentEnvelope.make(key: Curve25519.Signing.PrivateKey(), offerID: "fixture", termsSHA256: String(repeating: "a", count:64), summary:"synthetic", explicitConsent:true, userAuthored:true, timestamp:1000, retentionUntil:1500, nonce:"fixture-nonce-0001")
        let market = NdaniMarketplace(backendBase:"https://invalid.example")
        for mode in ["success", "503", "echo", "wrong-hash", "malformed"] {
            let session = fixtureSession(mode); defer { session.invalidateAndCancel() }
            await market.submit(participantID:e.participant, offerID:"fixture", dataType:"language-use", title:"fixture", summary:"synthetic", consentEnvelope:e, session:session)
            #expect((market.lastConsentSubmissionID != nil) == (mode == "success"))
            #expect(market.lastSubmission == nil)
            #expect((market.lastError == nil) == (mode == "success"))
        }
    }
    @MainActor @Test func failedReadsClearPriorOfferAndFinancialState() async {
        let market = NdaniMarketplace(backendBase:"https://invalid.example")
        let good=fixtureSession("success"), bad=fixtureSession("503")
        defer { good.invalidateAndCancel(); bad.invalidateAndCancel() }
        await market.fetchOffers(session:good); #expect(market.availableOffers.count == 1)
        await market.fetchOffers(session:bad); #expect(market.availableOffers.isEmpty)
        await market.fetchBalance(participantID:"fixture",signature:"fixture",session:good);#expect(market.balance != nil)
        await market.fetchBalance(participantID:"fixture",signature:"fixture",session:bad);#expect(market.balance == nil)
    }
    @MainActor @Test func actualFetchRejectsMissingDatatypeAndEmptyBuyer() async {
        let market=NdaniMarketplace(backendBase:"https://invalid.example")
        for mode in ["missing-type","empty-buyer"] {
            let session=fixtureSession(mode);defer{session.invalidateAndCancel()}
            await market.fetchOffers(session:session);#expect(market.availableOffers.isEmpty);#expect(market.lastError != nil)
        }
    }
}

private func fixtureSession(_ mode: String) -> URLSession {
    let config=URLSessionConfiguration.ephemeral
    config.protocolClasses=[ConsentFixtureProtocol.self]
    config.httpAdditionalHeaders=["X-Fixture-Response":mode]
    return URLSession(configuration:config)
}

private final class ConsentFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode=request.value(forHTTPHeaderField:"X-Fixture-Response") ?? "default"
        var json:[String:Any]=[:]
        if request.url?.path == "/api/offers/available" {
            var offer:[String:Any]=["id":"fixture","buyer":"fixture","title":"fixture","description":"fixture","payoutUSD":1.5,"dataType":"language-use"]
            if mode == "missing-type" {offer.removeValue(forKey:"dataType")}
            if mode == "empty-buyer" {offer["buyer"]=" "}
            json=["offers":[offer]]
        } else if request.url?.path == "/api/balance", mode != "default" {
            json=["balance_usd":1.5,"total_earned_usd":1.5,"total_paid_out_usd":0.0,"can_withdraw":false,"stripe_connected":false]
        } else if request.url?.path == "/api/consent-sale/submit" {
            var body=request.httpBody ?? Data()
            if body.isEmpty, let stream=request.httpBodyStream {
                stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:1024)
                while body.count < 20000 {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};body.append(contentsOf:buffer.prefix(n))}
            }
            let envelope=(try? JSONSerialization.jsonObject(with:body)) as? [String:String]
            let p=envelope?["payload"] ?? ""
            let raw=Data(base64Encoded:p.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")+String(repeating:"=",count:(4-p.count%4)%4)) ?? Data()
            json=["submission_id":String(repeating:"a",count:64),"request_sha256":SHA256.hash(data:raw).map{String(format:"%02x",$0)}.joined(),"status":"consented","payout_status":"unverified","contributor_obligation_cents":NSNull(),"withdrawal_available":false]
            if mode == "echo" {json=["submission_id":"echo","payout_usd":999.0]}
            if mode == "wrong-hash" {json["request_sha256"]=String(repeating:"f",count:64)}
            if mode == "malformed" {json.removeValue(forKey:"payout_status")}
        }
        let body=try! JSONSerialization.data(withJSONObject:json)
        let response = HTTPURLResponse(url: request.url!, statusCode: mode == "503" ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

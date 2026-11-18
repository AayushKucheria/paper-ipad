import XCTest
@testable import Paper

private final class ReviewHTTPProtocol: URLProtocol, @unchecked Sendable {
    static var handle: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let(status,data)=try Self.handle(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
private extension URLRequest {
    func httpBodyStreamData() -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
        return data
    }
}
final class ReviewNetworkTests:XCTestCase {
    func session()->URLSession{let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[ReviewHTTPProtocol.self];return URLSession(configuration:c)}
    func testAnthropicDecodesStructuredTextAndRejectsTruncation() async throws {
        var truncated=false
        ReviewHTTPProtocol.handle={req in
            XCTAssertEqual(req.url?.host,"api.anthropic.com")
            XCTAssertEqual(req.value(forHTTPHeaderField:"x-api-key"),"fake-anthropic-key")
            let input = #"{"items":[{"pages":[1],"quote":"Printed words","note":"Why?","interpretation":"","kind":"handwriting"}]}"#
            return (200,try JSONSerialization.data(withJSONObject:["stop_reason":truncated ? "max_tokens":"end_turn","content":[["type":"text","text":input]]]))
        }
        let api=AnthropicMarkupAPI(key:"fake-anthropic-key",session:session())
        let items=try await api.analyze([AnalysisPage(number:2,jpeg:Data([0]),sourceText:"Printed words")])
        XCTAssertEqual(items.first?.note,"Why?");XCTAssertEqual(items.first?.pages,[2])
        truncated=true
        do{_=try await api.analyze([AnalysisPage(number:2,jpeg:Data([0]),sourceText:"")]);XCTFail("Truncated analysis must not become drafts")}catch{}
    }
    func testHaikuChoicePersistsMeasuredUsageAndCost() async throws {
        ReviewHTTPProtocol.handle = { req in
            let body = req.httpBody ?? req.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating:0,count:65536); let count=stream.read(&bytes,maxLength:bytes.count); return Data(bytes.prefix(max(0,count)))
            } ?? Data()
            let json = try JSONSerialization.jsonObject(with:body) as! [String:Any]
            XCTAssertEqual(json["model"] as? String,"claude-haiku-5-5")
            return (200,try JSONSerialization.data(withJSONObject:["model":"claude-haiku-5-5","stop_reason":"end_turn","usage":["input_tokens":10000,"output_tokens":2000],"content":[["type":"text","text":"{\"items\":[]}"]]]))
        }
        let api = AnthropicMarkupAPI(key:"fake",model:"claude-haiku-5-5",session:session())
        _ = try await api.analyze([AnalysisPage(number:1,jpeg:Data([0]),sourceText:"")])
        let usage = await api.lastUsage()
        XCTAssertEqual(usage?.inputTokens,10000)
        XCTAssertEqual(usage?.outputTokens,2000)
        XCTAssertEqual(try XCTUnwrap(usage?.estimatedDollars),0.002,accuracy:0.000001)
        let service: any MarkupAnalyzing = api
        let protocolUsage = await service.lastUsage()
        XCTAssertEqual(protocolUsage,usage,"ReviewModel reads usage through the protocol, which must dispatch to the actor implementation")
        let measured = try XCTUnwrap(usage)
        XCTAssertEqual(measured.pricingVersion,"2026-10-22")
        let encoded = try JSONEncoder().encode(measured)
        let decoded = try JSONDecoder().decode(AnalysisUsage.self,from:encoded)
        XCTAssertEqual(decoded.pricingVersion,"2026-10-22")
        XCTAssertEqual(try XCTUnwrap(decoded.estimatedDollars),0.002,accuracy:0.000001)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        historical.removeValue(forKey:"pricingVersion")
        let legacy = try JSONDecoder().decode(AnalysisUsage.self,from:JSONSerialization.data(withJSONObject:historical))
        XCTAssertNil(legacy.pricingVersion)
        XCTAssertNil(legacy.estimatedDollars,"Unversioned historical usage must not be silently priced with current rates")
        XCTAssertEqual(legacy.inputTokens,10000)
        historical["pricingVersion"] = "unknown-version"
        let unknown = try JSONDecoder().decode(AnalysisUsage.self,from:JSONSerialization.data(withJSONObject:historical))
        XCTAssertNil(unknown.estimatedDollars)
    }
    func testAnthropicSendsSimpleCaptureNumbersAndMapsPagesBackToRegionIDs() async throws {
        var sentText = ""
        ReviewHTTPProtocol.handle={req in
            let body = try JSONSerialization.jsonObject(with: req.httpBodyStreamData()) as! [String:Any]
            let messages = body["messages"] as! [[String:Any]]
            sentText = (messages[0]["content"] as! [[String:Any]]).compactMap { $0["text"] as? String }.joined(separator:"|")
            let input = #"{"items":[{"pages":[1],"quote":"a","note":"n","interpretation":"","kind":"handwriting"},{"pages":[2],"quote":"b","note":"","interpretation":"","kind":"diagram"}]}"#
            return (200,try JSONSerialization.data(withJSONObject:["stop_reason":"end_turn","content":[["type":"text","text":input]]]))
        }
        let api=AnthropicMarkupAPI(key:"fake-anthropic-key",session:session())
        let items=try await api.analyze([AnalysisPage(number:100_001,jpeg:Data([0]),sourceText:"A"),AnalysisPage(number:200_003,jpeg:Data([0]),sourceText:"B")])
        XCTAssertEqual(items.map(\.pages),[[100_001],[200_003]])
        XCTAssertTrue(sentText.contains("Capture 1.") && sentText.contains("Capture 2."))
        XCTAssertFalse(sentText.contains("100001") || sentText.contains("200003"))
    }
    func testAnthropicErrorsDoNotExposeKeyOrRawServiceBody() async throws {
        ReviewHTTPProtocol.handle={_ in(401,Data("fake-anthropic-key private-service-body".utf8))}
        do{_=try await AnthropicMarkupAPI(key:"fake-anthropic-key",session:session()).analyze([AnalysisPage(number:1,jpeg:Data([0]),sourceText:"")]);XCTFail("Expected failure")}
        catch{XCTAssertFalse(error.localizedDescription.contains("fake-anthropic-key"));XCTAssertFalse(error.localizedDescription.contains("private-service-body"))}
    }
    func testReaderCreateAndReconcileUseUniqueMarkerAndParent() async throws {
        let item=ReviewItem(pages:[1,2],quote:"Printed words",note:"Why?",interpretation:"",kind:"handwriting")
        ReviewHTTPProtocol.handle={req in
            XCTAssertEqual(req.value(forHTTPHeaderField:"Authorization"),"Token fake-reader-token")
            if req.httpMethod == "POST" {return (201,Data(#"{"id":"new-highlight"}"#.utf8))}
            let response:[String:Any]=["results":[["id":"new-highlight","parent_id":"parent","notes":item.readerNote]],"nextPageCursor":NSNull()]
            return (200,try JSONSerialization.data(withJSONObject:response))
        }
        let api=ReaderHighlightAPI(token:"fake-reader-token",session:session())
        let created=try await api.create(parentID:"parent",item:item);XCTAssertEqual(created,"new-highlight")
        let found=try await api.find(parentID:"parent",item:item);XCTAssertEqual(found,"new-highlight")
    }
    func testReaderUnmatchedPassageIsDefiniteFailureButTimeoutIsAmbiguous() async throws {
        let item=ReviewItem(pages:[1],quote:"Not found",note:"",interpretation:"",kind:"highlight")
        let api=ReaderHighlightAPI(token:"fake-reader-token",session:session())
        ReviewHTTPProtocol.handle={_ in(400,Data())}
        do{_=try await api.create(parentID:"parent",item:item);XCTFail("Unmatched passage must fail")}catch{XCTAssertEqual(error as? ReviewError,.unmatched)}
        ReviewHTTPProtocol.handle={_ in throw URLError(.timedOut)}
        do{_=try await api.create(parentID:"parent",item:item);XCTFail("Ambiguous timeout must fail")}catch{XCTAssertEqual(error as? ReviewError,.ambiguous)}
    }
}

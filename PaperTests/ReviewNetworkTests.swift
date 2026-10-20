import XCTest
@testable import Paper

private final class ReviewHTTPProtocol: URLProtocol, @unchecked Sendable {
    static var handle: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let(status,data)=try Self.handle(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
final class ReviewNetworkTests:XCTestCase {
    func session()->URLSession{let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[ReviewHTTPProtocol.self];return URLSession(configuration:c)}
    func testAnthropicDecodesStructuredTextAndRejectsTruncation() async throws {
        var truncated=false
        ReviewHTTPProtocol.handle={req in
            XCTAssertEqual(req.url?.host,"api.anthropic.com")
            XCTAssertEqual(req.value(forHTTPHeaderField:"x-api-key"),"fake-anthropic-key")
            let input = #"{"items":[{"pages":[2],"quote":"Printed words","note":"Why?","interpretation":"","kind":"handwriting"}]}"#
            return (200,try JSONSerialization.data(withJSONObject:["stop_reason":truncated ? "max_tokens":"end_turn","content":[["type":"text","text":input]]]))
        }
        let api=AnthropicMarkupAPI(key:"fake-anthropic-key",session:session())
        let items=try await api.analyze([AnalysisPage(number:2,jpeg:Data([0]),sourceText:"Printed words")])
        XCTAssertEqual(items.first?.note,"Why?")
        truncated=true
        do{_=try await api.analyze([AnalysisPage(number:2,jpeg:Data([0]),sourceText:"")]);XCTFail("Truncated analysis must not become drafts")}catch{}
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

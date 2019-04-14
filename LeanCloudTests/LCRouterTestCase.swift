//
//  LCRouterTestCase.swift
//  LeanCloudTests
//
//  Created by Tianyong Tang on 2018/9/7.
//  Copyright © 2018 LeanCloud. All rights reserved.
//

import XCTest
@testable import LeanCloud

class LCRouterTestCase: BaseTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    let cnApplication       = LCApplication(id: "S5vDI3IeCk1NLLiM1aFg3262-gzGzoHsz", key: "7g5pPsI55piz2PRLPWK5MPz0")
    let ceApplication       = LCApplication(id: "uwWkfssEBRtrxVpQWEnFtqfr-9Nh9j0Va", key: "9OaLpoW21lIQtRYzJya4WHUR")
    let usApplication       = LCApplication(id: "eX7urCufwLd6X5mHxt7V12nL-MdYXbMMI", key: "PrmzHPnRXjXezS54KryuHMG6")
    let earlyCnApplication  = LCApplication(id: "uay57kigwe0b6f5n0e1d4z4xhydsml3dor24bzwvzr57wdap", key: "kfgz7jjfsk55r5a8a3y4ttd3je1ko11bkibcikonk32oozww")

    lazy var cnRouter       = HTTPRouter(application: cnApplication, configuration: .default)
    lazy var ceRouter       = HTTPRouter(application: ceApplication, configuration: .default)
    lazy var usRouter       = HTTPRouter(application: usApplication, configuration: .default)
    lazy var earlyCnRouter  = HTTPRouter(application: earlyCnApplication, configuration: .default)

    func testAbsoluteUrl() {
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "example.com", path: "foo"),
            URL(string: "https://example.com/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "example.com:8000", path: "foo"),
            URL(string: "https://example.com:8000/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com", path: "foo"),
            URL(string: "https://example.com/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "hello://example.com", path: "foo"),
            URL(string: "hello://example.com/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com:8000", path: "foo"),
            URL(string: "https://example.com:8000/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com:8000/", path: "foo"),
            URL(string: "https://example.com:8000/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com:8000", path: "/foo"),
            URL(string: "https://example.com:8000/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com:8000/", path: "/foo"),
            URL(string: "https://example.com:8000/foo"))
        XCTAssertEqual(
            cnRouter.absoluteUrl(host: "https://example.com:8000/foo", path: "bar"),
            URL(string: "https://example.com:8000/foo/bar"))
    }

    func testFallbackUrl() {
        for item in
            [HTTPRouter.Module.api,
             HTTPRouter.Module.engine,
             HTTPRouter.Module.push,
             HTTPRouter.Module.rtm,
             HTTPRouter.Module.stats]
        {
            switch item {
            case .api:
                XCTAssertEqual("\(item)", "api")
            case .engine:
                XCTAssertEqual("\(item)", "engine")
            case .push:
                XCTAssertEqual("\(item)", "push")
            case .rtm:
                XCTAssertEqual("\(item)", "rtm")
            case .stats:
                XCTAssertEqual("\(item)", "stats")
            }
            XCTAssertEqual(
                cnRouter.fallbackUrl(path: "1.1/foo", module: item),
                URL(string: "https://s5vdi3ie.\(item).lncld.net/1.1/foo"))
            XCTAssertEqual(
                ceRouter.fallbackUrl(path: "1.1/foo", module: item),
                URL(string: "https://uwwkfsse.\(item).lncldapi.com/1.1/foo"))
            XCTAssertEqual(
                usRouter.fallbackUrl(path: "1.1/foo", module: item),
                URL(string: "https://ex7urcuf.\(item).lncldglobal.com/1.1/foo"))
            XCTAssertEqual(
                earlyCnRouter.fallbackUrl(path: "1.1/foo", module: item),
                URL(string: "https://uay57kig.\(item).lncld.net/1.1/foo"))
        }
    }

    func testCacheExpiration() {
        let host = "s5vdi3ie.api.lncld.net"
        let appRouterCache = AppRouterCache(application: cnApplication)

        do {
            try appRouterCache.cacheHostTable([.api: host], expirationDate: Date(timeIntervalSinceNow: 0.3))
        } catch let error {
            XCTFail(error.localizedDescription)
        }

        XCTAssertEqual(try appRouterCache.fetchHost(module: .api), host)
        XCTAssertEqual(try appRouterCache.fetchHost(module: .push), nil)

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try appRouterCache.fetchHost(module: .api), nil)
    }

    func testAppRouterThrottle() {
        var requestSet = Set<LCRequest>()
        var resultArray: [LCBooleanResult] = []

        let dispatchGroup = DispatchGroup()

        for _ in 0..<100 {
            dispatchGroup.enter()
            let request = cnRouter.requestAppRouter { result in
                synchronize(on: resultArray) {
                    resultArray.append(result)
                }
                dispatchGroup.leave()
            }
            requestSet.insert(request)
        }

        dispatchGroup.wait()

        XCTAssertEqual(resultArray.count, 100)
        XCTAssertEqual(requestSet.count, 1)
    }

}

//
//  TwoWayMirrorTests.swift
//  TwoWayMirrorTests
//
//  Created by John Holdsworth on 14/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//

import XCTest
@testable import TwoWayMirror

class TwoWayMirrorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        enum E {
            case one, two(str: String)
        }
        struct S {
            let i = 123
        }
        struct S2: TwoWayContainable {
            var a1 = 0, a2 = 0
        }
        class C: NSObject {
            let a = [98.0]
            let b = 199.0
            let c = "Hello"
            let d = S()
            let e = E.one
            let f = Date()
            let g = ["A", "B"]
            let h = [S2]()
            deinit {
                print("deinit")
            }
        }

        if true {
            let i = C()

            i["a", [Double].self] += [11.0]
            print(i["a", [Double].self])

            i["b", Double.self] += 100.0
            print(i.b)

            i["c", String.self] += " String"
            print(i.c)

            i["d.i", Int.self] += 345
            print(i.d.i)

            i["e", E.self] = .two(str: "FFF")
            print(i.e)

            i["f", Date.self] = Date()
            print(i["f", Date.self])
        }

        let data = try! Data(contentsOf: Bundle.main.url(forResource: "test",
                                                         withExtension: "json")!)

        for _ in 0..<10 {
            let j = C()
            try! TwoWayMirror.decode(object: j, json: data)
            dump(j)
            let json = try! TwoWayMirror.encode(object: j, options: [.prettyPrinted])
            print(String(data: json, encoding: .utf8)!)
            let k = C()
            try! TwoWayMirror.decode(object: k, json: json)
            dump(k)
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}

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
        enum ExampleEnum: TwoWayEnum {
            case one, two(str: String), three(int: Int), four(int: Int, int2: Int)
            
            static func decode(data: inout TwoWayMirror, from: [String: Any]) throws {
                let ptr = data.pointer(type: ExampleEnum.self)
                switch from["case"] as! String {
                case "one":
                    ptr.pointee = .one
                case "two":
                    ptr.pointee = .two(str: from["let"] as! String)
                case "three":
                    ptr.pointee = .three(int: from["let"] as! Int)
                case "four":
                    ptr.pointee = .four(int: from["int"] as! Int,
                                        int2: from["int2"] as! Int)
                default:
                    throw NSError(domain: "ExampleEnum", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "Invalid case in: \(from)"])
                }
            }
        }
        struct ExampleStruct {
            let i = 123
        }
        struct ContainableStruct: TwoWayContainable {
            var a1 = 0, a2 = 0
        }
        class ExampleClass: NSObject {
            let a = [98.0]
            let b = 199.0
            let c = "Hello"
            let d = ExampleStruct()
            let e = ExampleEnum.four(int: 1, int2: 9)
            let f = Date()
            let g = ["A", "B"]
            let h = [ContainableStruct]()
            let i = [Int]()
            let j: [Int]? = nil
            let k: ContainableStruct? = nil
            let l = [[123, 123], [234, 234]]
            let m = ["a": [123, 123], "b": [234, 234]]
            let n = ["a": ContainableStruct(), "b": ContainableStruct()]
            let o = [["a": [123, 123], "b": [234, 234]], ["a": [123, 123], "b": [234, 234]]]
            let p = URL(string: "https://apple.com")
            let q = "123".data(using: .utf8)!
            deinit {
                print("deinit")
            }
        }

        if true {
            let instance = ExampleClass()

            print(TwoWayMirror.reflectKeys(any: instance))
            print(TwoWayMirror.reflectKeys(any: instance, path: "d"))

            TwoWayMirror.reflect(object: instance, path: "a", type: [Double].self).pointee += [11.0]
            print(instance["a", [Double].self])

            instance["b", Double.self] += 100.0
            print(instance.b)

            instance["c", String.self] += " String"
            print(instance.c)

            instance["d.i", Int.self] += 345
            print(instance.d.i)

            print(TwoWayMirror.reflectKeys(any: instance, path: "e"))
            instance["e", ExampleEnum.self] = .two(str: "FFF")
            print(instance.e)
            print(TwoWayMirror.reflectKeys(any: instance, path: "e"))
            print(TwoWayMirror.reflectKeys(any: instance, path: "e.two"))
            print(MemoryLayout<ExampleEnum>.size)

            instance["f", Date.self] = Date()
            print(instance["f", Date.self])
        }

        let data = """
            {
            "a": [77.0, 88.0],
            "b": 999.0,
            "c": "hello",
            "d": {
                "i": 789
            },
            "f": "2018-02-14 06:39:41 +0000",
            "g": ["Hello", "World"],
            "h": [
                  {
                  "a1": 11, "a2": 22
                  },
                  {
                  "a1": 111, "a2": 222
                  }
                  ],
            "i": [12345, 67890],
            "j": [99, 101],
            "k": {
                  "a1": 1111, "a2": 2222
                  },
            "p" : "https:\\/\\/apple.com",
            }
            """.data(using: .utf8)!

        for _ in 0..<10 {
            let i1 = ExampleClass()
            try! TwoWayMirror.decode(object: i1, json: data)
            dump(i1)
            let json = try! TwoWayMirror.encode(object: i1, options: [.prettyPrinted])
            print(String(data: json, encoding: .utf8)!)
            let i2 = ExampleClass()
            try! TwoWayMirror.decode(object: i2, json: json)
            dump(i2)
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
            self.testExample()
        }
    }
    
}

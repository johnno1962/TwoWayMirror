//: Playground - noun: a place where people can play

import Foundation

enum ExampleEnum: TwoWayEnum {
    case one, two(str: String), three(int: Int), four(int: Int, int2: Int)
    static func decode(ptr: UnsafeMutableRawPointer, from dict: [String: Any]) {
        let ptr = ptr.assumingMemoryBound(to: ExampleEnum.self)
        switch dict["case"] as! String {
        case "one":
            ptr.pointee = .one
        case "two":
            ptr.pointee = .two(str: dict["two"] as! String)
        case "three":
            ptr.pointee = .three(int: dict["three"] as! Int)
        case "four":
            ptr.pointee = .four(int: dict["int"] as! Int,
                                int2: dict["int2"] as! Int)
        default:
            fatalError("Invalid case: \(dict["case"]!)")
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
    let h: [ContainableStruct]? = nil
    let i = [Int]()
    let j: [Int]? = nil
    let k: ContainableStruct? = nil
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

    instance["e", ExampleEnum.self] = .two(str: "TWO")
    print(instance.e)

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
          }
    }
    """.data(using: .utf8)!

for _ in 0..<10 {
    let i1 = ExampleClass()
    try! TwoWayMirror.decode(object: i1, json: data)
    dump(i1)
    i1["e", ExampleEnum.self] = .four(int: 99, int2: 99)
    let json = try! TwoWayMirror.encode(object: i1, options: [.prettyPrinted])
    print(String(data: json, encoding: .utf8)!)
    let i2 = ExampleClass()
    try! TwoWayMirror.decode(object: i2, json: json)
    dump(i2)
}

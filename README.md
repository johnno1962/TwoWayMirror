# TwoWayMirror - bidirectional Swift Mirror

It's a frustrating limitation of Swift reflection that the [Mirror](http://nshipster.com/mirrortype/) type
can be only used in one direction for reading values from Swift data structures. This project leverages
Swift's internal implementation to remove this limitation by falling back to the original underlying
[RefelectionLegacy.swift](https://github.com/apple/swift/blob/master/stdlib/public/core/ReflectionLegacy.swift#L86)
functionality. Think runtime typed keypaths on steroids.

The [basic api](TwoWayMirror.playground/Sources/TwoWayMirror.swift) declares the following entry point:

```Swift
public func reflect<T>(object: AnyObject, path: String, type: T.Type) -> UnsafeMutablePointer<T>
```
This will return a typed pointer to any ivar of a class object or it's containing structs, enums, collections
that can be read or assigned to as if you were using a typed keypath.
A subscript is defined on any class derived from NSObject for a Swift valueForKey: replacement.

```Swift
public protocol SubScriptReflectable: AnyObject {}
extension NSObject: SubScriptReflectable {}
public extension SubScriptReflectable {
    public subscript<T> (path: String, type: T.Type) -> T {
        get {
            return TwoWayMirror.reflect(object: self, path: path, type: T.self).pointee
        }
        set(newValue) {
            TwoWayMirror.reflect(object: self, path: path, type: T.self).pointee = newValue
        }
    }
}
```

Example usage:

```Swift
enum ExampleEnum: TwoWayEnum {
    case one, two(str: String), three(int: Int), four(int: Int, int2: Int)

    static func twDecode(data: inout TwoWayMirror, from: [String: Any]) throws {
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
    var a1 = 0, a2 = 1
}
final class ExampleClass: NSObject, TwoWayContainable {
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
    let l = [[123, 123], [234, 234]]
    let m = ["a": [123, 123], "b": [234, 234]]
    let n = ["a": ContainableStruct(), "b": ContainableStruct()]
    let o = [["a": [123, 123], "b": [234, 234]], ["a": [123, 123], "b": [234, 234]]]
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

    let data = """
    [
      {
      "a1": 11, "a2": 22
      },
      {
      "a1": 111, "a2": 222
      }
    ]
    """.data(using: .utf8)!

    let array = try! TwoWayMirror.decode([ContainableStruct].self, from: data)
    dump(array)
}
```

This has been used to produce an alternative implementation of Codable for working with JSON.

```Swift
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
    "m" : {
        "b" : [
          111,
          222
        ],
        "a" : [
          333,
          444
        ]
    },
    "n" : {
        "b" : {
          "a2" : 1,
          "a1" : 2
        },
        "a" : {
          "a2" : 3,
          "a1" : 4
        }
    },
    }
    """.data(using: .utf8)!

let start = Date.timeIntervalSinceReferenceDate
for _ in 0..<10 {
    let i1 = ExampleClass()
    try! TwoWayMirror.decode(object: i1, json: data)
    dump(i1)
    let json = try! TwoWayMirror.encode(object: i1, options: [.prettyPrinted])
    print(String(data: json, encoding: .utf8)!)
    let i2 = try! TwoWayMirror.decode(ExampleClass.self, from: json)
    dump(i2)
}
print(Date.timeIntervalSinceReferenceDate-start)
```

The JSON implementation will decode and encode composed structs and class instances,
Ints, Doubles and String along with Arrays or Optionals of these and Arrays or Optionals of
structs or class instances which implement the `TwoWayContainable` protocol (which just
requires they have an init() methhod.) For writing using reflection to work (decoding) the
top level object must be an instance of a class. Otherwise, a copy is taken when the object
is reflected and any changes will be lost.

Automatic encoding of enums is possible but for decoding you must opt-in to the `TwoWayEnum`
protocol and supply an implementation to initialise an enum from a dictionary.

While this approach bends a few rules it has proven to be robust making very few
assumptions about the Swift reflection implementation.

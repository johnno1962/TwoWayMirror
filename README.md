# TwoWayMirror - bidirectional Swift Mirror

It's a frustrating limitation of Swift reflection using the [Mirror](http://nshipster.com/mirrortype/) type
can be only used in one direction for reading values from Swift data structures. This project leverages
Swift's existing implementation to remove this limitation by falling back to the original underlying
[RefelectionLegacy.swift](https://github.com/apple/swift/blob/master/stdlib/public/core/ReflectionLegacy.swift#L86)
functionality. Think runtime typed keypaths on steroids.

The [basic api](TwoWayMirror.playground/Sources/TwoWayMirror.swift) declares the following entry point:

```Swift
public func reflect<T>(object: AnyObject, path: String, type: T.Type) -> UnsafeMutablePointer<T>
```
This will return a typed pointer to any ivar of a class object or it's containing structs, enums, collections
that can be read or assigned to as if you were using a typed keypath.
This has been used to produce an alternative implementation of Codable for working with JSON data and
a subscript is defined on any class derived from NSObject for as a Swift valueForKey: replacement.

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
    static func decode(ptr: UnsafeMutableRawPointer, from dict: NSDictionary) {
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
    let h = [ContainableStruct]()
    let i = [Int]()
    let j: Int? = nil
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
```

JSON decoding and encoding:

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
          }
    }
    """.data(using: .utf8)!

let i1 = ExampleClass()
try! TwoWayMirror.decode(object: i1, json: data)
dump(i1)
let json = try! TwoWayMirror.encode(object: i1, options: [.prettyPrinted])
print(String(data: json, encoding: .utf8)!)
let i2 = ExampleClass()
try! TwoWayMirror.decode(object: i2, json: json)
dump(i2)
```

The JSON implementation will decode and encode composed structs and class instances,
Ints, Doubles and String along with Arrays or Optionals of these and Arrays or Optionals of
structs or class instances which implement the `TwoWayContainable` protocol. For writing to
an object using reflection to work the top level object must be an instance of a class otherwise
a copy is taken when the object is reflected and any changes will be lost.

Automatic encoding of enums is possible but for decoding you must opt-in to the TwoWayEnum
protocol and supply an implementation to initialise an enum from a dictionary.

While this approach bends a few rules the approach has proven to be robust and makes very few
assumptions about the Swift reflection implementation.

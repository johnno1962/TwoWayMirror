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

```Swift
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

let i = C()

TwoWayMirror.reflect(object: i, path: "a", type: [Double].self).pointee += [11.0]
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
```

```Swift
let data = try! Data(contentsOf: Bundle.main.url(forResource: "test",
                                                 withExtension: "json")!)

let j = C()
try! TwoWayMirror.decode(object: j, json: data)
dump(j)
let json = try! TwoWayMirror.encode(object: j, options: [.prettyPrinted])
print(String(data: json, encoding: .utf8)!)
let k = C()
try! TwoWayMirror.decode(object: k, json: json)
dump(k)
```

While this approach bends a few rules the approach has proven to be robust and makes very few
assumptions about the Swift reflection implementation.

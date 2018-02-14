//: Playground - noun: a place where people can play

import Foundation

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
    let i = [Int]()
    deinit {
        print("deinit")
    }
}

if true {
    let instance = C()

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

    instance["e", E.self] = .two(str: "FFF")
    print(instance.e)

    instance["f", Date.self] = Date()
    print(instance["f", Date.self])
}

let data = try! Data(contentsOf: Bundle.main.url(forResource: "test",
                                                 withExtension: "json")!)

for _ in 0..<10 {
    let i1 = C()
    try! TwoWayMirror.decode(object: i1, json: data)
    dump(i1)
    let json = try! TwoWayMirror.encode(object: i1, options: [.prettyPrinted])
    print(String(data: json, encoding: .utf8)!)
    let i2 = C()
    try! TwoWayMirror.decode(object: i2, json: json)
    dump(i2)
}

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
    deinit {
        print("deinit")
    }
}

if true {
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
}

let data = try! Data(contentsOf: Bundle.main.url(forResource: "test",
                                                 withExtension: "json")!)

for _ in 0..<10 {
    let j = C()
    TwoWayMirror.decode(object: j, json: data)
    dump(j)
    let json = TwoWayMirror.encode(object: j, options: [.prettyPrinted])
    print(String(data: json, encoding: .utf8)!)
    let k = C()
    TwoWayMirror.decode(object: k, json: json)
    dump(k)
}

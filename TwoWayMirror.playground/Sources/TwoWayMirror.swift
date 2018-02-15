//
//  TwoWayMirror.swift
//  TwoWayMirror
//
//  Created by John Holdsworth on 13/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//
//  $Id: //depot/TwoWayMirror/TwoWayMirror.playground/Sources/TwoWayMirror.swift#23 $
//

import Foundation

// Assumptions...
// https://medium.com/@vhart/protocols-generics-and-existential-containers-wait-what-e2e698262ab1
// https://github.com/apple/swift/blob/master/stdlib/public/core/ReflectionLegacy.swift#L86

@_silgen_name("swift_reflectAny")
internal func _reflect<T>(_ x: T) -> _Mirror

@_silgen_name("swift_EnumMirror_caseName")
internal func _enumMirror_caseName(
    _ data: _MagicMirrorData) -> UnsafePointer<CChar>

// _Mirror is a protocol with concrete implementations _StructMirror, _ClassMirror etc
// which fit into the 3 slots available in the "existential" data structure representing
// the protocol so we can coerce a pointer to _Mirror to the internal "_MagicMirrorData"

@_fixed_layout
public struct TwoWayMirror {
    let owner: UnsafePointer<Any>
    let ptr: UnsafeMutableRawPointer
    let metadata: Any.Type
//    let protocolType: Any.Type
//    let protocolWitness: UnsafeMutableRawPointer

    public static func reflect(mirror: UnsafePointer<_Mirror>, path: [String]? = nil) -> TwoWayMirror {
        if var path = path, !path.isEmpty {
            let key = path.removeFirst()
            for index in 0 ..< mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if name == key {
                    return reflect(mirror: &submirror, path: path)
                }
            }
            fatalError("TwoWayMirror could not find path component: \(key)")
        }

        return mirror.withMemoryRebound(to: TwoWayMirror.self, capacity: 1) {
            $0.pointee
        }
    }

    public static func reflect<T>(object: AnyObject, path: String, type: T.Type,
            file: StaticString = #file, line: UInt = #line) -> UnsafeMutablePointer<T> {
        var mirror = _reflect(object)
        let data = reflect(mirror: &mirror, path: path.components(separatedBy: "."))
        if data.metadata != T.self {
            fatalError("TwoWayMirror type mismatch: \(data.metadata) != \(T.self) at \(file)#\(line)")
        }
        return data.ptr.assumingMemoryBound(to: T.self)
    }

    public static func reflectKeys(any: Any, path: String = "") -> [String] {
        var mirror = _reflect(any)
        if path != "" {
            for key in path.components(separatedBy: ".") {
                for index in 0 ..< mirror.count {
                    let (name, submirror) = mirror[index]
                    if name == key {
                        mirror = submirror
                        break
                    }
                }
            }
        }
        return (0 ..< mirror.count).map { mirror[$0].0 }
    }
}

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

/// JSON encoding / decoding
extension TwoWayMirror {

    public static func decode(object: AnyObject, json: Data) throws {
        try decode(object: object, any: try JSONSerialization.jsonObject(with: json))
    }

    public static func decode(object: AnyObject, any: Any) throws {
        var mirror = _reflect(object)
        try decode(mirror: &mirror, any: any)
    }

    static func cast<T>(_ any: Any?, to type: T.Type,
                        file: StaticString = #file, line: UInt = #line) throws -> T {
        if let cast = any as? T {
            return cast
        }
        throw NSError(domain: "TwoWayMirror", code: -1,
                      userInfo: [NSLocalizedDescriptionKey:
                        "Invalid cast of \(any!) to \(T.self) at \(file)#\(line)"])
    }

    static func decode(mirror: UnsafePointer<_Mirror>, any: Any?) throws {
        let data = reflect(mirror: mirror)
        if let optionalType = data.metadata as? IsOptional.Type {
            try optionalType.decode(ptr: data.ptr, any: any)
            return
        }
        else if any == nil {
            return
        }
        if data.metadata == Int.self {
            data.ptr.assumingMemoryBound(to: Int.self).pointee =
                try cast(any, to: Int.self)
        }
        else if data.metadata == [Int].self {
            let array = data.ptr.assumingMemoryBound(to: [Int].self)
            array.pointee.removeAll()
            for value in try cast(any, to: [Int].self) {
                array.pointee.append( value )
            }
        }
        else if data.metadata == Double.self {
            data.ptr.assumingMemoryBound(to: Double.self).pointee =
                try (try? cast(any, to: Double.self)) ?? Double(try cast(any, to: Int.self))
        }
        else if data.metadata == [Double].self {
            let array = data.ptr.assumingMemoryBound(to: [Double].self)
            array.pointee.removeAll()
            for value in try (try? cast(any, to: [Double].self)) ??
                    (try cast(any, to: [Int].self)).map {Double($0)} {
                array.pointee.append( value )
            }
        }
        else if data.metadata == String.self {
            data.ptr.assumingMemoryBound(to: String.self).pointee =
                try cast(any, to: String.self)
        }
        else if data.metadata == [String].self {
            let array = data.ptr.assumingMemoryBound(to: [String].self)
            array.pointee.removeAll()
            for value in try cast(any, to: [String].self) {
                array.pointee.append( value )
            }
        }
        else if let arrayType = data.metadata as? IsArray.Type {
            let elementType = arrayType.elementType
            if let containableType = elementType as? TwoWayContainable.Type {
                for value in try cast(any, to: [[String: Any]].self) {
                    try containableType.decodeElement(to: data.ptr, from: value)
                }
            }
        }
        else if data.metadata == Date.self {
            let date = TwoWayMirror.dateFormatter.date(from: try cast(any, to: String.self))!
            data.ptr.assumingMemoryBound(to: Date.self).pointee = date
        }
        else if let enumType = data.metadata as? TwoWayEnum.Type {
            enumType.decode(ptr: data.ptr, from: try cast(any, to: [String: Any].self))
        }
        else if mirror.pointee.count != 0, let dict = any as? [String: Any] {
            for index in 0 ..< mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                try decode(mirror: &submirror, any: dict[name])
            }
        }
    }

    static var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return dateFormatter
    }()

    public static func encode(object: AnyObject,
                              options: JSONSerialization.WritingOptions) throws -> Data {
        return try JSONSerialization.data(withJSONObject: encode(object: object), options: options)
    }

    public static func encode(object: AnyObject) -> Any {
        var mirror = _reflect(object)
        return encode(mirror: &mirror)
    }

    static func encode(mirror: UnsafePointer<_Mirror>) -> NSObject {
        let data = reflect(mirror: mirror)
        if data.metadata == Int.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Int.self).pointee)
        }
        else if data.metadata == [Int].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Int].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
        }
        else if data.metadata == Double.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Double.self).pointee)
        }
        else if data.metadata == [Double].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Double].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
        }
        else if data.metadata == String.self {
            return NSString(string: data.ptr.assumingMemoryBound(to: String.self).pointee)
        }
        else if data.metadata == [String].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [String].self).pointee {
                array.add( NSString(string: value) )
            }
            return array
        }
        else if let arrayType = data.metadata as? IsArray.Type {
            let array = NSMutableArray()
            let elementType = arrayType.elementType
            if let containableType = elementType as? TwoWayContainable.Type {
                containableType.encodeElements(from: data.ptr, into: array)
            }
            return array
        }
        else if data.metadata == Date.self {
            let date = data.ptr.assumingMemoryBound(to: Date.self).pointee
            return NSString(string: TwoWayMirror.dateFormatter.string(from: date))
        }
        else if let enumType = data.metadata as? IsOptional.Type {
            return enumType.encode(mirror: mirror)
        }
        else if data.metadata is TwoWayEnum.Type {
            let dict = NSMutableDictionary()
            dict[NSString(string: "case")] =
                mirror.withMemoryRebound(to: _MagicMirrorData.self, capacity: 1) {
                    String(cString: _enumMirror_caseName($0.pointee))
            }
            if mirror.pointee.count != 0 {
                var (name, submirror) = mirror.pointee[0]
                if submirror.count == 1 {
                    dict[NSString(string: name)] = encode(mirror: &submirror)
                } else {
                    for index in 0 ..< submirror.count {
                        var (name, casemirror) = submirror[index]
                        dict[NSString(string: name)] = encode(mirror: &casemirror)
                    }
                }
            }
            return dict
        }
        else {//if mirror.pointee.count != 0 {
            let dict = NSMutableDictionary()
            for index in 0 ..< mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if name == "super" { continue }
                dict[NSString(string: name)] = encode(mirror: &submirror)
            }
            return dict
        }
    }
}

/// Objects contained in Arrays
private protocol IsArray {
    static var elementType: Any.Type { get }
}
extension Array: IsArray {
    static var elementType: Any.Type {
        return Element.self
    }
}
public protocol TwoWayContainable {
    init()
}
extension Array: TwoWayContainable {}

extension TwoWayContainable {
    static func decodeElement(from: Any) throws -> Self {
        let instanceHolder = Cricible<Self>()
        var mirror = _reflect(instanceHolder)[0].1
        try TwoWayMirror.decode(mirror: &mirror, any: from)
        return instanceHolder.instance
    }
    static func decodeElement(to ptr: UnsafeMutableRawPointer?, from any: Any) throws {
        ptr?.assumingMemoryBound(to: [Self].self).pointee.append(try decodeElement(from: any))
    }
    static func encodeElements(from ptr: UnsafeMutableRawPointer, into array: NSMutableArray) {
        let values = ptr.assumingMemoryBound(to: [Self].self)
        for i in 0 ..< values.pointee.count {
            var mirror = _reflect(values.pointee[i])
            array.add(TwoWayMirror.encode(mirror: &mirror))
        }
    }
}
private class Cricible<T: TwoWayContainable> {
    var instance = T()
}

/// Optionals
private protocol IsOptional {
    static func decode(ptr: UnsafeMutableRawPointer, any: Any?) throws
    static func encode(mirror: UnsafePointer<_Mirror>) -> NSObject
}
extension Optional: IsOptional {
    static func decode(ptr: UnsafeMutableRawPointer, any: Any?) throws {
        let optionalPtr = ptr.assumingMemoryBound(to: Optional<Wrapped>.self)
        if let any = any, !(any is NSNull) {
            if let subtype = Wrapped.self as? TwoWayContainable.Type {
                let instance = try subtype.decodeElement(from: any)
                optionalPtr.pointee = .some(try TwoWayMirror.cast(instance, to: Wrapped.self))
            }
            else {
                optionalPtr.pointee = .some(try TwoWayMirror.cast(any, to: Wrapped.self))
            }
        }
        else {
            optionalPtr.pointee = nil
        }
    }
    static func encode(mirror: UnsafePointer<_Mirror>) -> NSObject {
        let data = TwoWayMirror.reflect(mirror: mirror)
        let ptr = data.ptr.assumingMemoryBound(to: Optional<Wrapped>.self)
        if ptr.pointee != nil {
            var (_, submirror) = mirror.pointee[0]
            return TwoWayMirror.encode(mirror: &submirror)
        }
        return NSNull()
    }
}

/// decoding/encoding enums
public protocol TwoWayEnum {
    static func decode(ptr: UnsafeMutableRawPointer, from dict: [String: Any])
}

//
//  TwoWayMirror.swift
//  TwoWayMirror
//
//  Created by John Holdsworth on 13/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//
//  $Id: //depot/TwoWayMirror/TwoWayMirror.playground/Sources/TwoWayMirror.swift#25 $
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
    let owner: UnsafeMutableRawPointer
    /// pointer to memory containing ivar
    public let ptr: UnsafeMutableRawPointer
    /// type represented at that memory location
    public let metadata: Any.Type
//    let protocolType: Any.Type
//    let protocolWitness: UnsafeMutableRawPointer

    /// Get TwoWayMirror information for a mirrored ivar
    ///
    /// - Parameters:
    ///   - mirror: pointer to Swift reflection information
    ///   - path: dotted keypath to ivar of interest
    /// - Returns: TwoWyayMirror information
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

    /// Reflect a typed pointer to a class instance ivar
    ///
    /// - Parameters:
    ///   - object: pointer to class instance
    ///   - path: dotted path to ivar of interest
    ///   - type: assumed type of instance
    /// - Returns: typed pointer to memory of ivar
    public static func reflect<T>(object: AnyObject, path: String, type: T.Type,
            file: StaticString = #file, line: UInt = #line) -> UnsafeMutablePointer<T> {
        var mirror = _reflect(object)
        let data = reflect(mirror: &mirror, path: path.components(separatedBy: "."))
        if data.metadata != T.self {
            fatalError("TwoWayMirror type mismatch: \(data.metadata) != \(T.self) at \(file)#\(line)")
        }
        return data.ptr.assumingMemoryBound(to: T.self)
    }

    /// List ivars of class struct of interest
    ///
    /// - Parameters:
    ///   - any: class instance/struct
    ///   - path: dotted path to ivar of interest
    /// - Returns: list of ivars in memory order
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

/// conformance for subscript equivalent of keypaths
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

    /// Decode ivar values from JSON onto object
    ///
    /// - Parameters:
    ///   - object: class instance to take values
    ///   - json: JSON Data packet
    ///   - options: JSON reading options
    /// - Throws: JSON/type conversion errors
    public static func decode(object: AnyObject, json: Data,
                              options: JSONSerialization.ReadingOptions = []) throws {
        try decode(object: object,
                   any: try JSONSerialization.jsonObject(with: json, options: options))
    }

    /// Decode ivar values from foundation class representation
    ///
    /// - Parameters:
    ///   - object: class instance to take values
    ///   - any: foundation representation of values
    /// - Throws: type conversion errors
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
        guard let any = any else {
            return
        }

        if data.metadata == Int.self {
            data.ptr.assumingMemoryBound(to: Int.self).pointee =
                try cast(any, to: Int.self)
        }
        else if data.metadata == Double.self {
            data.ptr.assumingMemoryBound(to: Double.self).pointee =
                try (try? cast(any, to: Double.self)) ?? Double(try cast(any, to: Int.self))
        }
        else if data.metadata == String.self {
            data.ptr.assumingMemoryBound(to: String.self).pointee =
                try cast(any, to: String.self)
        }
        else if data.metadata == Date.self {
            let date = TwoWayMirror.dateFormatter.date(from: try cast(any, to: String.self))!
            data.ptr.assumingMemoryBound(to: Date.self).pointee = date
        }
        else if data.metadata == [Int].self {
            let array = data.ptr.assumingMemoryBound(to: [Int].self)
            array.pointee = try cast(any, to: [Int].self)
        }
        else if data.metadata == [Double].self {
            let array = data.ptr.assumingMemoryBound(to: [Double].self)
            array.pointee = try (try? cast(any, to: [Double].self)) ??
                (try cast(any, to: [Int].self)).map {Double($0)}
        }
        else if data.metadata == [String].self {
            let array = data.ptr.assumingMemoryBound(to: [String].self)
            array.pointee = try cast(any, to: [String].self)
        }
        else if let arrayType = data.metadata as? IsArray.Type {
            if let containableType = arrayType.elementType as? TwoWayContainable.Type {
                try containableType.decodeElements(into: data.ptr, from: any)
            }
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

    /// encode a class instance/struct to JSON
    ///
    /// - Parameters:
    ///   - object: class instance/struct
    ///   - options: JSON writing options
    /// - Returns: JSON Data packet
    /// - Throws: JSON errors
    public static func encode(object: Any,
                              options: JSONSerialization.WritingOptions) throws -> Data {
        return try JSONSerialization.data(withJSONObject: encode(object: object), options: options)
    }

    /// encode class instance/struct to representation as foundation objects
    ///
    /// - Parameter object: class instance/struct
    /// - Returns: NSDictionary
    public static func encode(object: Any) -> Any {
        var mirror = _reflect(object)
        return encode(mirror: &mirror)
    }

    static func encode(mirror: UnsafePointer<_Mirror>) -> NSObject {
        let data = reflect(mirror: mirror)
        if data.metadata == Int.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Int.self).pointee)
        }
        else if data.metadata == Double.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Double.self).pointee)
        }
        else if data.metadata == String.self {
            return NSString(string: data.ptr.assumingMemoryBound(to: String.self).pointee)
        }
        else if data.metadata == Date.self {
            let date = data.ptr.assumingMemoryBound(to: Date.self).pointee
            return NSString(string: TwoWayMirror.dateFormatter.string(from: date))
        }
        else if data.metadata == [Int].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Int].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
        }
        else if data.metadata == [Double].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Double].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
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
            if let containableType = arrayType.elementType as? TwoWayContainable.Type {
                containableType.encodeElements(from: data.ptr, into: array)
            }
            return array
        }
        else if let optionalType = data.metadata as? IsOptional.Type {
            return optionalType.encode(mirror: mirror)
        }
        else if data.metadata is TwoWayEnum.Type {
            let dict = NSMutableDictionary()
            dict[NSString(string: "case")] =
                mirror.withMemoryRebound(to: _MagicMirrorData.self, capacity: 1) {
                    NSString(utf8String: _enumMirror_caseName($0.pointee))
            }
            if mirror.pointee.count != 0 {
                var (_, submirror) = mirror.pointee[0]
                if submirror.count == 1 {
                    dict[NSString(string: "let")] = encode(mirror: &submirror)
                } else {
                    for index in 0 ..< submirror.count {
                        var (name, letmirror) = submirror[index]
                        dict[NSString(string: name)] = encode(mirror: &letmirror)
                    }
                }
            }
            return dict
        }
        else {
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

/// Objects that can be created decoding arrays or optionals
public protocol TwoWayContainable {
    init()
}

extension Array: TwoWayContainable {}
extension String: TwoWayContainable {}
extension Double: TwoWayContainable {}
extension Date: TwoWayContainable {}
extension Int: TwoWayContainable {}

private class Crucible<T: TwoWayContainable> {
    var instance = T()
}
extension TwoWayContainable {
    static func decodeElement(from: Any) throws -> Self {
        let instanceHolder = Crucible<Self>()
        var (_, mirror) = _reflect(instanceHolder)[0]
        try TwoWayMirror.decode(mirror: &mirror, any: from)
        return instanceHolder.instance
    }
    static func decodeElements(into ptr: UnsafeMutableRawPointer, from any: Any) throws {
        ptr.assumingMemoryBound(to: [Self].self).pointee =
            try TwoWayMirror.cast(any, to: [Any].self).map { try decodeElement(from: $0) }
    }
    static func encodeElements(from ptr: UnsafeMutableRawPointer, into array: NSMutableArray) {
        for value in ptr.assumingMemoryBound(to: [Self].self).pointee {
            var mirror = _reflect(value)
            array.add(TwoWayMirror.encode(mirror: &mirror))
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

/// conformance for decoding/encoding enums
public protocol TwoWayEnum {
    static func decode(ptr: UnsafeMutableRawPointer, from dict: [String: Any])
}

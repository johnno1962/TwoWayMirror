//
//  TwoWayMirror.swift
//  TwoWayMirror
//
//  Created by John Holdsworth on 13/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//
//  $Id: //depot/TwoWayMirror/TwoWayMirror.playground/Sources/TwoWayMirror.swift#76 $
//

import Foundation

// MARK: Assumptions...
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

// MARK: Basic reflection API

@_fixed_layout
public struct TwoWayMirror {
    let owner: UnsafeRawPointer
    /// pointer to memory containing ivar
    public let ptr: UnsafeMutableRawPointer
    /// type represented at that memory location
    public let metadata: Any.Type
//    let protocolType: Any.Type
//    let protocolWitness: UnsafeRawPointer

    /// Cast data pointer to specific type
    ///
    /// - Parameters:
    ///   - type: assumed type of ivar
    /// - Returns: typed pointer to ivar
    public func pointer<T>(type: T.Type, file: StaticString = #file, line: UInt = #line)
                                                            -> UnsafeMutablePointer<T> {
        guard metadata == T.self else {
            fatalError("TwoWayMirror type mismatch: \(metadata) != \(T.self) at \(file)#\(line)")
        }
        return ptr.assumingMemoryBound(to: T.self)
    }

    public subscript<T>(type: T.Type) -> T {
        get {
            return pointer(type: T.self).pointee
        }
        set(newValue) {
            pointer(type: T.self).pointee = newValue
        }
    }

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
        return data.pointer(type: T.self, file: file, line: line)
    }

    /// List ivars of class struct of interest
    ///
    /// - Parameters:
    ///   - any: class instance/struct
    ///   - path: dotted path to ivar of interest
    /// - Returns: list of ivars in memory order
    public static func reflectKeys(any: Any, path: String? = nil) -> [String] {
        var mirror = _reflect(any)
        if let path = path {
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
    public subscript<T>(path: String, type: T.Type) -> T {
        get {
            return TwoWayMirror.reflect(object: self, path: path, type: T.self).pointee
        }
        set(newValue) {
            TwoWayMirror.reflect(object: self, path: path, type: T.self).pointee = newValue
        }
    }
}

public func TWError(_ string: String) -> Error {
    return NSError(domain: "TwoWayMirror", code: -1,
                   userInfo: [NSLocalizedDescriptionKey: "TwoWayMirror \(string)"])
}

// MARK: JSON encoding / decoding as reflection example

extension TwoWayMirror {

    /// Create and decode object from JSON data
    ///
    /// - Parameters:
    ///   - instanceType: Type conforming to TwoWayContainable
    ///   - json: JSON format instance Data
    ///   - options: JSON reading options
    /// - Returns: New initialised instance of instanceType
    /// - Throws: Any error encountered during encoding
    public static func decode<T: TwoWayContainable>(_ containableType: T.Type, from json: Data,
                                 options: JSONSerialization.ReadingOptions = []) throws -> T {
        let any = try JSONSerialization.jsonObject(with: json, options: options)
        return try containableType.decodeElement(from: any)
    }

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

    static func decode(mirror: UnsafePointer<_Mirror>, any: Any) throws {
        var data = reflect(mirror: mirror)
        if let codableType = data.metadata as? TwoWayCodable.Type {
            try codableType.twDecode(data: &data, any: any)
        }
        else if let enumType = data.metadata as? TwoWayEnum.Type {
            try enumType.twDecode(data: &data, from: try cast(any, to: [String: Any].self))
        }
        else if mirror.pointee.count != 0, let dict = any as? [String: Any] {
            for index in 0 ..< mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if let value = dict[name] {
                    try decode(mirror: &submirror, any: value)
                }
            }
        }
    }

    /// encode a class instance/struct to JSON
    ///
    /// - Parameters:
    ///   - object: class instance/struct
    ///   - options: JSON writing options
    /// - Returns: JSON Data packet
    /// - Throws: JSON errors
    public static func encode(object: Any,
                              options: JSONSerialization.WritingOptions) throws -> Data {
        return try JSONSerialization.data(withJSONObject: encode(object: object),
                                          options: options)
    }

    /// encode class instance/struct to representation as foundation objects
    ///
    /// - Parameter object: class instance/struct
    /// - Returns: NSDictionary
    public static func encode(object: Any) -> Any {
        var mirror = _reflect(object)
        return encode(mirror: &mirror)
    }

    static func encode(mirror: UnsafePointer<_Mirror>) -> Any {
        let data = reflect(mirror: mirror)
        if let codableType = data.metadata as? TwoWayCodable.Type {
            return codableType.twEncode(data: data)
        }
        else if data.metadata is TwoWayEnum.Type {
            var dict = [String: Any]()
            dict["case"] =
                mirror.withMemoryRebound(to: _MagicMirrorData.self, capacity: 1) {
                    String(utf8String: _enumMirror_caseName($0.pointee))
            }
            if mirror.pointee.count != 0 {
                var (_, submirror) = mirror.pointee[0]
                if submirror.count == 1 {
                    dict["let"] = encode(mirror: &submirror)
                } else {
                    for index in 0 ..< submirror.count {
                        var (name, letmirror) = submirror[index]
                        dict[name] = encode(mirror: &letmirror)
                    }
                }
            }
            return dict
        }
        else {
            var dict = [String: Any]()
            for index in 0 ..< mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if name == "super" { continue }
                dict[name] = encode(mirror: &submirror)
            }
            return dict
        }
    }

    public static func cast<T>(_ any: Any, to type: T.Type,
                        file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let cast = any as? T else {
            throw TWError("invalid cast of \(any) to \(T.self) at \(file)#\(line)")
        }
        return cast
    }

    public static var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return dateFormatter
    }()
}

// MARK: Codable conformances

/// Conform to be codable
public protocol TwoWayCodable {
    static func twDecode(data: inout TwoWayMirror, any: Any) throws
    static func twEncode(data: TwoWayMirror) -> Any
}

/// Conformance for decoding enums
public protocol TwoWayEnum {
    static func twDecode(data: inout TwoWayMirror, from dict: [String: Any]) throws
}

/// Objects that can be created decoding containers or optionals
public protocol TwoWayContainable {
    init()
}

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
}

public protocol TwoWayCastable: TwoWayContainable {}
extension TwoWayCastable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        #if os(Linux)
        if Self.self == Double.self {
            data[Double.self] = try (any as? Int).flatMap { Double($0) } ??
                                    TwoWayMirror.cast(any, to: Double.self)
            return
        }
        #endif
        data[Self.self] = try TwoWayMirror.cast(any, to: Self.self)
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        return data[Self.self]
    }
}

extension Int: TwoWayCodable, TwoWayCastable {}
extension Double: TwoWayCodable, TwoWayCastable {}
extension String: TwoWayCodable, TwoWayCastable {}

extension Date: TwoWayCodable, TwoWayContainable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let date = TwoWayMirror.dateFormatter.date(from: string) else {
            throw TWError("unable to parse date: '\(string)'")
        }
        data[Date.self] = date
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        return TwoWayMirror.dateFormatter.string(from: data[Date.self])
    }
}

extension Data: TwoWayCodable, TwoWayContainable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let base64 = Data(base64Encoded: string) else {
            throw TWError("unable to decode base64: '\(string)'")
        }
        data[Data.self] = base64
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        return data[Data.self].base64EncodedString()
    }
}

extension URL: TwoWayCodable, TwoWayContainable {
    public init() {
        self.init(string: "http://void.org")!
    }
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let url = URL(string: string) else {
            throw TWError("unable to parse url: '\(string)'")
        }
        data[URL.self] = url
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        return data[URL.self].absoluteString
    }
}

extension Array: TwoWayCodable, TwoWayContainable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        guard let containableType = Element.self as? TwoWayContainable.Type else {
            throw TWError("unable to decode array containing \(Element.self)")
        }
        data[[Element].self] =
            try TwoWayMirror.cast(any, to: [Any].self)
                .map { try containableType.decodeElement(from: $0) as! Element }
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        return data[[Element].self].map {
            (e: Element) -> Any in
            var mirror = _reflect(e)
            return TwoWayMirror.encode(mirror: &mirror)
        }
    }
}

extension Dictionary: TwoWayCodable, TwoWayContainable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        guard let containableType = Value.self as? TwoWayContainable.Type else {
            throw TWError("unable to decode dictionary containing \(Value.self)")
        }
        let dictPtr = data.pointer(type: [Key: Value].self)
        dictPtr.pointee.removeAll()
        for (key, value) in try TwoWayMirror.cast(any, to: [Key: Any].self) {
            dictPtr.pointee[key] = try containableType.decodeElement(from: value) as? Value
        }
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        var dict = [Key: Any]()
        for (key, value) in data[[Key: Value].self] {
            var mirror = _reflect(value)
            dict[key] = TwoWayMirror.encode(mirror: &mirror)
        }
        return dict
    }
}

extension Optional: TwoWayCodable {
    public static func twDecode(data: inout TwoWayMirror, any: Any) throws {
        let optionalPtr = data.pointer(type: Optional<Wrapped>.self)
        if any is NSNull {
            optionalPtr.pointee = nil
        }
        else {
            guard let subtype = Wrapped.self as? TwoWayContainable.Type else {
                throw TWError("unable to decode optional of \(Wrapped.self)")
            }
            let instance = try subtype.decodeElement(from: any)
            optionalPtr.pointee = .some(try TwoWayMirror.cast(instance, to: Wrapped.self))
        }
    }
    public static func twEncode(data: TwoWayMirror) -> Any {
        guard let some = data[Optional<Wrapped>.self] else {
            return NSNull()
        }
        var mirror = _reflect(some)
        return TwoWayMirror.encode(mirror: &mirror)
    }
}

//
//  TwoWayMirror.swift
//  TwoWayMirror
//
//  Created by John Holdsworth on 13/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//

import Foundation

// Assumptions...
// https://medium.com/@vhart/protocols-generics-and-existential-containers-wait-what-e2e698262ab1
// https://github.com/apple/swift/blob/master/stdlib/public/core/ReflectionLegacy.swift#L86

@_silgen_name("swift_reflectAny")
internal func _reflect<T>(_ x: T) -> _Mirror

// _Mirror is a protocol with concrete implementations _StructMirror, _ClassMirror etc
// which fit into the 3 slots available in the "existential" data structrue represening
// the protocol so we can coerce a pointer to _Mirror to the internal "_MagicMirrorData",

@_fixed_layout
public struct TwoWayMirror {
    let owner: UnsafePointer<Any>
    let ptr: UnsafeMutableRawPointer
    let metadata: Any.Type
//    let protocolType: Any.Type
//    let protocolWitness: UnsafeMutableRawPointer

    static public func reflect(mirror: UnsafePointer<_Mirror>, path: [String]? = nil) -> TwoWayMirror {
        if var path = path, !path.isEmpty {
            let target = path.removeFirst()
            for index in 0..<mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if name == target {
                    return reflect(mirror: &submirror, path: path)
                }
            }
            fatalError("TwoWayMirror could not find path component: \(target)")
        }

        return mirror.withMemoryRebound(to: TwoWayMirror.self, capacity: 1) {
            return $0.pointee
        }
    }

    static public func reflect<T>(object: AnyObject, path: String, type: T.Type) -> UnsafeMutablePointer<T> {
        var mirror = _reflect(object)
        let data = reflect(mirror: &mirror, path: path.components(separatedBy: "."))
        if data.metadata != T.self {
            fatalError("TwoWayMirror type mismatch: \(data.metadata) != \(T.self)")
        }
        return data.ptr.assumingMemoryBound(to: T.self)
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

extension TwoWayMirror {

    static public func decode(object: AnyObject, json: Data) {
        decode(object: object, any: try! JSONSerialization.jsonObject(with: json))
    }

    static public func decode(object: AnyObject, any: Any) {
        var mirror = _reflect(object)
        decode(mirror: &mirror, any: any)
    }

    static func decode(mirror: UnsafePointer<_Mirror>, any: Any) {
        let data = reflect(mirror: mirror)
        if data.metadata == Int.self {
            data.ptr.assumingMemoryBound(to: Int.self).pointee = (any as! NSNumber).intValue
        } else if data.metadata == [Int].self {
            let array = data.ptr.assumingMemoryBound(to: [Int].self)
            array.pointee.removeAll()
            for value in any as! NSArray {
                array.pointee.append( (value as! NSNumber).intValue )
            }
        } else if data.metadata == Double.self {
            data.ptr.assumingMemoryBound(to: Double.self).pointee = (any as! NSNumber).doubleValue
        } else if data.metadata == [Double].self {
            let array = data.ptr.assumingMemoryBound(to: [Double].self)
            array.pointee.removeAll()
            for value in any as! NSArray {
                array.pointee.append( (value as! NSNumber).doubleValue )
            }
        } else if data.metadata == String.self {
            data.ptr.assumingMemoryBound(to: String.self).pointee = (any as! String)
        } else if data.metadata == [String].self {
            let array = data.ptr.assumingMemoryBound(to: [String].self)
            array.pointee.removeAll()
            for value in any as! NSArray {
                array.pointee.append( (value as! String) )
            }
        } else if let arrayType = data.metadata as? IsArray.Type {
            let elementType = arrayType.elementType
            if let containableType = elementType as? TwoWayContainable.Type {
                for value in any as! NSArray {
                    containableType.encodeElement(to: data.ptr, from: value)
                }
            }
        } else if data.metadata == Date.self {
            let date = TwoWayMirror.dateFormatter.date(from: (any as! String))!
            data.ptr.assumingMemoryBound(to: Date.self).pointee = date
        } else if mirror.pointee.count != 0, let dict = any as? [String: Any] {
            for index in 0..<mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if let value = dict[name] {
                    decode(mirror: &submirror, any: value)
                }
            }
        }
    }

    static var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return dateFormatter
    }()

    static public func encode(object: AnyObject, options: JSONSerialization.WritingOptions) -> Data {
        return try! JSONSerialization.data(withJSONObject: encode(object: object), options: options)
    }

    static public func encode(object: AnyObject) -> Any {
        var mirror = _reflect(object)
        return encode(mirror: &mirror)
    }

    static func encode(mirror: UnsafePointer<_Mirror>) -> Any {
        let data = reflect(mirror: mirror)
        if data.metadata == Int.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Int.self).pointee)
        } else if data.metadata == [Int].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Int].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
        } else if data.metadata == Double.self {
            return NSNumber(value: data.ptr.assumingMemoryBound(to: Double.self).pointee)
        } else if data.metadata == [Double].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [Double].self).pointee {
                array.add( NSNumber(value: value) )
            }
            return array
        } else if data.metadata == String.self {
            return data.ptr.assumingMemoryBound(to: String.self).pointee as NSString
        } else if data.metadata == [String].self {
            let array = NSMutableArray()
            for value in data.ptr.assumingMemoryBound(to: [String].self).pointee {
                array.add( value as NSString )
            }
            return array
        } else if let arrayType = data.metadata as? IsArray.Type {
            let array = NSMutableArray()
            let elementType = arrayType.elementType
            if let containableType = elementType as? TwoWayContainable.Type {
                containableType.decodeElements(from: data.ptr, into: array)
            }
            return array
        } else if data.metadata == Date.self {
            let date = data.ptr.assumingMemoryBound(to: Date.self).pointee
            return TwoWayMirror.dateFormatter.string(from: date)
        } else {//if mirror.pointee.count != 0 {
            let dict = NSMutableDictionary()
            for index in 0..<mirror.pointee.count {
                var (name, submirror) = mirror.pointee[index]
                if name == "super" { continue }
                dict[name] = encode(mirror: &submirror)
            }
            return dict
        }
    }
}

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
extension TwoWayContainable {
    static func encodeElement(to ptr: UnsafeMutableRawPointer, from: Any) {
        let instanceHolder = Cricible<Self>()
        var mirror = _reflect(instanceHolder)[0].1
        TwoWayMirror.decode(mirror: &mirror, any: from)
        ptr.assumingMemoryBound(to: [Self].self).pointee.append(instanceHolder.instance)
    }
    static func decodeElements(from ptr: UnsafeMutableRawPointer, into array: NSMutableArray) {
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

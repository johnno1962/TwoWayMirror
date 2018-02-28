//
//  TwoWayMirror.swift
//  TwoWayMirror
//
//  Created by John Holdsworth on 13/02/2018.
//  Copyright © 2018 John Holdsworth. All rights reserved.
//
//  $Id: //depot/TwoWayMirror/TwoWayMirror.playground/Sources/TwoWayMirror.swift#113 $
//

import Foundation

public struct TwoWayMirror {

    public static func reflect<V,T>(object: UnsafeMutablePointer<V>, path: String? = nil, type: T.Type) -> UnsafeMutablePointer<T> {
        return TwoWayMirror(object: object, path: path).pointer(type: T.self)
    }

    public static func reflectAny<V>(object: UnsafeMutablePointer<V>, path: String? = nil) -> Any {
        return encode(mirror: TwoWayMirror(object: object, path: path))
    }

    public static func reflectKeys<V>(object: UnsafeMutablePointer<V>, path: String? = nil) -> [String] {
        return TwoWayMirror(object: object, path: path).names
    }

    public var ptr: UnsafeMutablePointer<Int8>
    var typeInfo: TwoWayTypeInfo

    public var type: Any.Type { return typeInfo.type }
    public var count: Int { return typeInfo.count }
    public var names: [String] { return typeInfo.names }
    public var types: [Any.Type] { return typeInfo.fieldTypes }

    static var infoCache = [ObjectIdentifier: TwoWayTypeInfo]()

    public init<V>(object: UnsafeMutablePointer<V>, path: String? = nil, type: Any.Type? = nil) {
        self.ptr = object.withMemoryRebound(to: Int8.self, capacity: 1) { $0 }
        let type = type ?? V.self

        typeInfo = TwoWayMirror.infoCache[ObjectIdentifier(type)] ?? {
            let typeInfo = TwoWayTypeInfo(type: type)
            TwoWayMirror.infoCache[ObjectIdentifier(type)] = typeInfo
            return typeInfo
        }()

        if typeInfo.description != nil && typeInfo.fieldOffsets[0] != 0 {
            ptr = ptr.withMemoryRebound(to: UnsafeMutablePointer<Int8>?.self, capacity: 1) { $0.pointee! }
        }

        if let path = path?.components(separatedBy: ".") {
            for key in path {
                if let mirror = self[key] {
                    self = mirror
                    continue
                }
                fatalError("Unable to find path component \(key)")
            }
        }
    }

    public subscript(fieldName: String) -> TwoWayMirror? {
        if let index = (0 ..< count).first(where: { names[$0] == fieldName }) {
            return self[index].mirror
        }
        return nil
    }

    public subscript(fieldNumber: Int) -> (name: String, mirror: TwoWayMirror) {
        let fieldPointer = ptr.advanced(by: Int(typeInfo.fieldOffsets[fieldNumber]))
//        print(">>>", self.ptr, fieldPointer, fieldOffsets[0], fieldOffsets[fieldNumber])
        return (names[fieldNumber], TwoWayMirror(object: fieldPointer, type: typeInfo.fieldTypes[fieldNumber]))
    }

    public func pointer<T>(type: T.Type) -> UnsafeMutablePointer<T> {
        if typeInfo.type != type {
            fatalError("Ivar type '\(typeInfo.type)' not equal to destination type '\(type)'")
        }
        return ptr.withMemoryRebound(to: T.self, capacity: 1) { $0 }
    }

    public subscript<T>(type: T.Type) -> T {
        get {
            return pointer(type: T.self).pointee
        }
        set(newValue) {
            pointer(type: T.self).pointee = newValue
        }
    }

    class TwoWayTypeInfo {
        // extracted from https://github.com/apple/swift/blob/master/include/swift/Runtime/Metadata.h

        typealias StoredPointer = intptr_t
        typealias LocalRelativePointer = Int32
        typealias MaybeRelativePointer = intptr_t

        struct SwiftNominalTypeDescriptor {

            /// Swift 5
            var Flags: UInt32, Parent: UInt32

            /// The mangled name of the nominal type.
            var Name: LocalRelativePointer

            /// Swift 5
            var Accessor: LocalRelativePointer

            /// The number of stored properties in the class, not including its
            /// superclasses. If there is a field offset vector, this is its length.
            var NumFields: UInt32
            /// The offset of the field offset vector for this class's stored
            /// properties in its metadata, if any. 0 means there is no field offset
            /// vector.
            ///
            /// To deal with resilient superclasses correctly, this will
            /// eventually need to be relative to the start of this class's
            /// metadata area.
            var FieldOffsetVectorOffset: UInt32

            /// The field names. A doubly-null-terminated list of strings, whose
            /// length and order is consistent with that of the field offset vector.
            var FieldNames: LocalRelativePointer

            /// The field type vector accessor. Returns a pointer to an array of
            /// type metadata references whose order is consistent with that of the
            /// field offset vector.
            var GetFieldTypes: LocalRelativePointer
        }

        /**
         Layout of a class instance. Needs to be kept in sync with ~swift/include/swift/Runtime/Metadata.h
         */
        struct ClassMetadataSwift {

            public let MetaClass: uintptr_t, SuperClass: uintptr_t
            public let CacheData1: uintptr_t, CacheData2: uintptr_t

            public let Data: uintptr_t

            /// Swift-specific class flags.
            public let Flags: UInt32

            /// The address point of instances of this type.
            public let InstanceAddressPoint: UInt32

            /// The required size of instances of this type.
            /// 'InstanceAddressPoint' bytes go before the address point;
            /// 'InstanceSize - InstanceAddressPoint' bytes go after it.
            public let InstanceSize: UInt32

            /// The alignment mask of the address point of instances of this type.
            public let InstanceAlignMask: UInt16

            /// Reserved for runtime use.
            public let Reserved: UInt16

            /// The total size of the class object, including prefix and suffix
            /// extents.
            public let ClassSize: UInt32

            /// The offset of the address point within the class object.
            public let ClassAddressPoint: UInt32

            /// An out-of-line Swift-specific description of the type, or null
            /// if this is an artificial subclass.  We currently provide no
            /// supported mechanism for making a non-artificial subclass
            /// dynamically.
            public var Description: MaybeRelativePointer

            /// A function for destroying instance variables, used to clean up
            /// after an early return from a constructor.
            public var IVarDestroyer: SIMP? = nil

            // After this come the class members, laid out as follows:
            //   - class members for the superclass (recursively)
            //   - metadata reference for the parent, if applicable
            //   - generic parameters for this class
            //   - class variables (if we choose to support these)
            //   - "tabulated" virtual methods
        }

        /** pointer to a function implementing a Swift method */
        typealias SIMP = @convention(c) (_: AnyObject) -> Void

        struct SwiftStructMetadata {
            /// The kind. Only valid for non-class metadata; getKind() must be used to get
            /// the kind value.
            let Kind: StoredPointer
            /// An out-of-line description of the type.
            var Description: MaybeRelativePointer
        }

        let type: Any.Type
        var fieldTypes = [Any.Type]()
        var fieldOffsets: UnsafePointer<StoredPointer>!

        public lazy var count: Int = {
            return Int(self.description?.pointee.NumFields ?? 0)
        }()

        public var names = [String]()

        lazy var description: UnsafeMutablePointer<SwiftNominalTypeDescriptor>?  = {
            let classData = unsafeBitCast(self.type, to: UnsafeMutablePointer<ClassMetadataSwift>.self)
            if classData.pointee.MetaClass == 1 {//|| classData.pointee.MetaClass == 2 {
                var structData = unsafeBitCast(self.type, to: UnsafeMutablePointer<SwiftStructMetadata>.self)
                return self.getDescription(ptr: &structData.pointee.Description)
            }
            else if classData.pointee.MetaClass > 0x100000000 || classData.pointee.MetaClass == 0 {
                return self.getDescription(ptr: &classData.pointee.Description)
            }
            else {
                return nil
            }
        }()

        func getDescription(ptr: UnsafeMutablePointer<MaybeRelativePointer>) -> UnsafeMutablePointer<SwiftNominalTypeDescriptor> {
            if ptr.pointee < 0x100000000 {
                return ptr.withMemoryRebound(to: Int8.self, capacity: 1) { $0.advanced(by: ptr.pointee) }
                    .withMemoryRebound(to: SwiftNominalTypeDescriptor.self, capacity: 1) { $0 }
            }
            else {
                return UnsafeMutablePointer<SwiftNominalTypeDescriptor>(bitPattern: ptr.pointee)!
            }
        }

        func localRelativePointer<T>(field: UnsafePointer<LocalRelativePointer>, type: T.Type) -> UnsafePointer<T> {
            return field.withMemoryRebound(to: Int8.self, capacity: 1) {
                $0.advanced(by: Int(field.pointee)).withMemoryRebound(to: T.self, capacity: 1) { $0 }
            }
        }

        init(type: Any.Type) {
            self.type = type
            if description != nil {
                struct StringRef {
                    let data: UnsafePointer<CChar>
                    let count: Int
                }
                let callback = StdFunction({
                    (a1, a2, a3, a4, a5) in
                    let name = a1.assumingMemoryBound(to: StringRef.self).pointee
                    let fieldInfo = a2.assumingMemoryBound(to: uintptr_t.self).pointee
                    self.names.append(String(cString: name.data))
                    self.fieldTypes.append(unsafeBitCast(fieldInfo & ~0x3, to: Any.Type.self))
                })
                for field in 0 ..< description!.pointee.NumFields {
                    swift_getFieldAt(base: self.type, index: field, callback: callback)
                }
                callback.destruct()
            }
            let typeWords = unsafeBitCast(self.type, to: UnsafePointer<StoredPointer>.self)
            fieldOffsets = typeWords.advanced(by: Int(description?.pointee.FieldOffsetVectorOffset ?? 0))
        }
    }
}

/// conformance for subscript equivalent of keypaths
public protocol SubScriptReflectable: AnyObject {}
extension NSObject: SubScriptReflectable {}

public extension SubScriptReflectable {
    public subscript<T>(path: String, type: T.Type) -> T {
        get {
            var object = self
            return TwoWayMirror.reflect(object: &object, path: path, type: T.self).pointee
        }
        set(newValue) {
            var object = self
            TwoWayMirror.reflect(object: &object, path: path, type: T.self).pointee = newValue
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

    /// Decode field values from JSON onto object
    ///
    /// - Parameters:
    ///   - object: class instance to take values
    ///   - json: JSON Data packet
    ///   - options: JSON reading options
    /// - Throws: JSON/type conversion errors
    public static func decode<T>(object: UnsafeMutablePointer<T>, json: Data,
                                 options: JSONSerialization.ReadingOptions = []) throws {
        try decode(object: object,
                   any: try JSONSerialization.jsonObject(with: json, options: options))
    }

    /// Decode field values from foundation class representation
    ///
    /// - Parameters:
    ///   - object: class instance to take values
    ///   - any: foundation representation of values
    /// - Throws: type conversion errors
    public static func decode<T>(object: UnsafeMutablePointer<T>, any: Any) throws {
        var mirror = TwoWayMirror(object: object)
        try decode(mirror: &mirror, any: any)
    }

    static func decode(mirror: inout TwoWayMirror, any: Any) throws {
        if let codableType = mirror.typeInfo.type as? TwoWayCodable.Type {
            try codableType.twDecode(mirror: &mirror, any: any)
        }
        else if mirror.count != 0, let dict = any as? [String: Any] {
            for index in 0 ..< mirror.count {
                var (name, submirror) = mirror[index]
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
    public static func encode<T>(object: UnsafeMutablePointer<T>,
                                 options: JSONSerialization.WritingOptions) throws -> Data {
        return try JSONSerialization.data(withJSONObject: encode(object: object),
                                          options: options)
    }

    /// encode class instance/struct to representation as foundation objects
    ///
    /// - Parameter object: class instance/struct
    /// - Returns: NSDictionary
    public static func encode<T>(object: UnsafeMutablePointer<T>) -> Any {
        return encode(mirror: TwoWayMirror(object: object))
    }

    static func encode(mirror: TwoWayMirror) -> Any {
        if let codableType = mirror.typeInfo.type as? TwoWayCodable.Type {
            return codableType.twEncode(mirror: mirror)
        }
        else {
            var dict = [String: Any]()
            for index in 0 ..< mirror.count {
                let (name, submirror) = mirror[index]
                if name == "super" { continue }
                dict[name] = encode(mirror: submirror)
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
    static func twDecode(mirror: inout TwoWayMirror, any: Any) throws
    static func twEncode(mirror: TwoWayMirror) -> Any
}

/// Objects that can be created decoding containers or optionals
public protocol TwoWayContainable {
    init()
}

extension TwoWayContainable {
    static func decodeElement(from: Any) throws -> Self {
        var instance = Self()
        var mirror = TwoWayMirror(object: &instance, type: Self.self)
        try TwoWayMirror.decode(mirror: &mirror, any: from)
        return instance
    }
}

public protocol TwoWayCastable: TwoWayContainable {}
extension TwoWayCastable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        #if os(Linux)
        if Self.self == Double.self {
            mirror[Double.self] = try (any as? Int).flatMap { Double($0) } ??
                                    TwoWayMirror.cast(any, to: Double.self)
            return
        }
        #endif
        mirror[Self.self] = try TwoWayMirror.cast(any, to: Self.self)
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        return mirror[Self.self]
    }
}

extension Int: TwoWayCodable, TwoWayCastable {}
extension Double: TwoWayCodable, TwoWayCastable {}
extension String: TwoWayCodable, TwoWayCastable {}

extension Date: TwoWayCodable, TwoWayContainable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let date = TwoWayMirror.dateFormatter.date(from: string) else {
            throw TWError("unable to parse date: '\(string)'")
        }
        mirror[Date.self] = date
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        return TwoWayMirror.dateFormatter.string(from: mirror[Date.self])
    }
}

extension Data: TwoWayCodable, TwoWayContainable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let base64 = Data(base64Encoded: string) else {
            throw TWError("unable to decode base64: '\(string)'")
        }
        mirror[Data.self] = base64
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        return mirror[Data.self].base64EncodedString()
    }
}

extension URL: TwoWayCodable, TwoWayContainable {
    public init() {
        self.init(string: "http://void.org")!
    }
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        let string = try TwoWayMirror.cast(any, to: String.self)
        guard let url = URL(string: string) else {
            throw TWError("unable to parse url: '\(string)'")
        }
        mirror[URL.self] = url
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        return mirror[URL.self].absoluteString
    }
}

extension Array: TwoWayCodable, TwoWayContainable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        guard let containableType = Element.self as? TwoWayContainable.Type else {
            throw TWError("unable to decode array containing \(Element.self)")
        }
        mirror[[Element].self] =
            try TwoWayMirror.cast(any, to: [Any].self)
                .map { try containableType.decodeElement(from: $0) as! Element }
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        return mirror[[Element].self].map {
            (e: Element) -> Any in
            var object = e
            let mirror = TwoWayMirror(object: &object)
            return TwoWayMirror.encode(mirror: mirror)
        }
    }
}

extension Dictionary: TwoWayCodable, TwoWayContainable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        guard let containableType = Value.self as? TwoWayContainable.Type else {
            throw TWError("unable to decode dictionary containing \(Value.self)")
        }
        let dictPtr = mirror.pointer(type: [Key: Value].self)
        dictPtr.pointee.removeAll()
        for (key, value) in try TwoWayMirror.cast(any, to: [Key: Any].self) {
            dictPtr.pointee[key] = try containableType.decodeElement(from: value) as? Value
        }
    }
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        var dict = [Key: Any]()
        for (key, value) in mirror[[Key: Value].self] {
            var object = value
            let mirror = TwoWayMirror(object: &object)
            dict[key] = TwoWayMirror.encode(mirror: mirror)
        }
        return dict
    }
}

extension Optional: TwoWayCodable {
    public static func twDecode(mirror: inout TwoWayMirror, any: Any) throws {
        let optionalPtr = mirror.pointer(type: Optional<Wrapped>.self)
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
    public static func twEncode(mirror: TwoWayMirror) -> Any {
        guard var some = mirror[Optional<Wrapped>.self] else {
            return NSNull()
        }
        return TwoWayMirror.encode(mirror: TwoWayMirror(object: &some))
    }
}

// MARK: Provide C++ std::function callback from Swift

// No promises mind. Highly dependent the STL implementation.

let StdNull: UnsafeRawPointer? = nil

public struct StdFunction {

    #if os(Linux)
    typealias _Manager_type = @convention(c) () -> Void

    let __base: UnsafePointer<StdBase>
    let __blank = StdNull
    let _M_manager: NotUsed = { print("_M_manager") }
    let _M_invoker: OperatorInvoke = {
        (_M_functor, a1, a2, a3, a4, a5) -> Return in
        let __base = _M_functor.assumingMemoryBound(to: StdFunction.self).pointee.__base
        return __base.pointee.__vtable.pointee.g(__base, a1, a2, a3, a4, a5)
    }
    let slot5 = StdNull
    let slot6 = StdNull
    #else
    let slot1 = StdNull
    let slot2 = StdNull
    let slot3 = StdNull
    let slot4 = StdNull
    let __base: UnsafePointer<StdBase>
    let slot6 = StdNull
    #endif

    static var created = [UnsafePointer<StdBase>:StdRetainer]()

    public init(_ closure: @escaping Callback) {
        let retainer = StdRetainer(closure: closure)
        __base = withUnsafePointer(to: &retainer.__base) { $0 }
        StdFunction.created[__base] = retainer
    }

    public func destruct() {
        StdFunction.created.removeValue(forKey: __base)
    }

    public typealias Return = Void
    public typealias Callback = (_ a1: UnsafeRawPointer, _ a2: UnsafeRawPointer,
        _ a3: UnsafeRawPointer, _ a4: UnsafeRawPointer, _ a5: UnsafeRawPointer) -> Return
    typealias OperatorInvoke = @convention(c) (_ this: UnsafeRawPointer, _ a1: UnsafeRawPointer, _ a2: UnsafeRawPointer,
        _ a3: UnsafeRawPointer, _ a4: UnsafeRawPointer, _ a5: UnsafeRawPointer) -> Return
    typealias NotUsed = @convention(c) () -> Void

    class StdRetainer {

        var __base: StdBase

        init(closure: @escaping Callback) {
            __base = StdBase(__vtable: &StdBase.vtable, closure: closure)
        }
    }

    struct StdBase {

        struct StdVtable {
            let a: NotUsed = { print("slot a called") }
            let b: NotUsed = { print("slot b called") }
            let c: NotUsed = { print("slot c called") }
            let d: NotUsed = { print("slot d called") }
            let e: NotUsed = { print("slot e called") }
            let f: NotUsed = { print("slot f called") }
            let g: OperatorInvoke = {
                (this, a1, a2, a3, a4, a5) -> Return in
                return this.assumingMemoryBound(to: StdBase.self)
                    .pointee.closure(a1, a2, a3, a4, a5)
            }
            let h: NotUsed = { print("slot h called") }
            let i: NotUsed = { print("slot i called") }
        }

        static var vtable = StdVtable()

        let __vtable: UnsafePointer<StdVtable>
        let closure: Callback
    }
}

@_silgen_name("swift_getFieldAt")
func swift_getFieldAt(base: Any.Type, index: UInt32, callback: StdFunction)

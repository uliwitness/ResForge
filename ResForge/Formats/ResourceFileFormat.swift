import Foundation
import RFSupport

enum ResourceFormatError: LocalizedError {
    case invalidID(Int)
    case typeAttributesNotSupported
    case fileTooBig
    case valueOverflow

    var failureReason: String? {
        switch self {
        case let .invalidID(id):
            return String(format: NSLocalizedString("The ID %ld is out of range for this file format.", comment: ""), id)
        case .typeAttributesNotSupported:
            return NSLocalizedString("Type attributes are not compatible with this file format.", comment: "")
        case .fileTooBig:
            return NSLocalizedString("The maximum file size of this format was exceeded.", comment: "")
        case .valueOverflow:
            return NSLocalizedString("An internal limit of this file format was exceeded.", comment: "")
        }
    }
}

enum ResourceFileFormat {
    case classic
    case rez
    case extended
}

extension ResourceFileFormat {
    var name: String {
        switch self {
        case .classic:
            return NSLocalizedString("Resource File", comment: "")
        case .extended:
            return NSLocalizedString("Extended Resource File", comment: "")
        case .rez:
            return NSLocalizedString("Rez File", comment: "")
        }
    }
    var typeName: String {
        // We want to make the format's filename extension simply a "suggestion" and not force it in any manner, but the
        // standard behaviour makes this difficult to achieve nicely. NSSavePanel.allowsOtherFileTypes isn't sufficient as
        // it still prompts the user to confirm and only works if the user has entered an extension known by the system.
        // The current solution is to use the following system UTIs that have no extension.
        switch self {
        case .classic:
            return "public.data"
        case .extended:
            return "public.item"
        case .rez:
            return "com.resforge.rez-file"
        }
    }
    var filenameExtension: String {
        switch self {
        case .classic:
            return "rsrc"
        case .extended:
            return "rsrx"
        case .rez:
            return "rez"
        }
    }
    var minID: Int {
        self == .extended ? Int(Int32.min) : Int(Int16.min)
    }
    var maxID: Int {
        self == .extended ? Int(Int32.max) : Int(Int16.max)
    }

    init(typeName: String) {
        switch typeName {
        case Self.extended.typeName:
            self = .extended
        case Self.rez.typeName:
            self = .rez
        default:
            self = .classic
        }
    }

    func isValid(id: Int) -> Bool {
        return minID...maxID ~= id
    }
}

extension ResourceFileFormat {
    static func read(from url: URL) throws -> (Self, [ResourceType: [Resource]]) {
        let content = try Data(contentsOf: url)
        do {
            let format = try self.detectFormat(content)
            return (format, try format.read(content))
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func detectFormat(_ data: Data) throws -> Self {
        let reader = BinaryDataReader(data)

        // Rez and Extended start with specific signature
        let signature = (try reader.read() as UInt32).stringValue
        if signature == RezFormat.signature {
            return .rez
        } else if signature == ExtendedFormat.signature {
            return .extended
        } else {
            // Fallback to classic
            return .classic
        }
    }

    func read(_ data: Data) throws -> [ResourceType: [Resource]] {
        switch self {
        case .classic:
            return try ClassicFormat.read(data)
        case .rez:
            return try RezFormat.read(data)
        case .extended:
            return try ExtendedFormat.read(data)
        }
    }

    func write(_ resourcesByType: [ResourceType: [Resource]], to url: URL) throws {
        let data: Data
        switch self {
        case .classic:
            data = try ClassicFormat.write(resourcesByType)
        case .rez:
            data = try RezFormat.write(resourcesByType)
        case .extended:
            data = try ExtendedFormat.write(resourcesByType)
        }
        try data.write(to: url)
    }
}
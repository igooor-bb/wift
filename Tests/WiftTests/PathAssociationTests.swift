import Foundation
import Testing
@testable import Wift

struct PathAssociationTests {
    @Test func identifierIsDeterministicAndPathSpecific() {
        #expect(
            PathAssociation.identifier(for: "/checkout/script.swift")
                == PathAssociation.identifier(for: "/checkout/script.swift")
        )
        #expect(
            PathAssociation.identifier(for: "/checkout/script.swift")
                != PathAssociation.identifier(for: "/other/script.swift")
        )
    }

    @Test func validatesStoredCanonicalPath() throws {
        try withTemporaryDirectory { directory in
            let expected = PathAssociation(canonicalPath: "/checkout/script.swift")
            let url = directory.appendingPathComponent(expected.fileName)
            try expected.write(to: url)

            #expect(PathAssociation.read(from: url, expectedCanonicalPath: expected.canonicalPath) == expected)

            let unexpected = PathAssociation(canonicalPath: "/other/script.swift")
            let encoder = JSONEncoder()
            try encoder.encode(unexpected).write(to: url, options: .atomic)
            #expect(PathAssociation.read(from: url, expectedCanonicalPath: expected.canonicalPath) == nil)
        }
    }
}

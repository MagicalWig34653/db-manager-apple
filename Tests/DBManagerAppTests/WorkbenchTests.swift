// SPDX-License-Identifier: AGPL-3.0-only
import DBManagerCore
import Foundation
import Testing
@testable import DBManagerApp
#if os(macOS)
import AppKit
import SwiftUI
#endif

@MainActor
@Test func workbenchRunsAgainstLocalFileAndRequiresWriteConsent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = WorkbenchModel(localRoot: directory)
    model.createLocal()
    await model.operation?.value
    #expect(model.fileName != nil && model.error == nil && model.localFiles.count == 1)
    model.sql = "CREATE TABLE synthetic(value)"
    model.execute()
    await model.operation?.value
    #expect(model.error != nil && model.objects.isEmpty)
    model.allowWrites = true
    model.execute()
    await model.operation?.value
    #expect(model.error == nil && model.objects.map(\.name) == ["synthetic"])
    model.sql = "SELECT 9223372036854775807 AS value"
    model.execute()
    await model.operation?.value
    #expect(model.result?.rows[0][0].value == "9223372036854775807")
    model.close()
    await model.operation?.value
    #expect(model.fileName == nil && model.result == nil && !model.allowWrites)
}

#if os(macOS)
@MainActor
@Test func syntheticResultRendersWithoutScreenRecordingOrAccessibility() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = SQLiteDatabase()
    try await database.open(directory.appendingPathComponent("synthetic.sqlite"), create: true)
    let result = try await database.execute("SELECT 9223372036854775807 AS Ganzzahl, NULL AS Leerwert, '' AS Text, x'00FF' AS Binaer UNION ALL SELECT 2,NULL,'',x''", limits: QueryLimits(maxRows: 1))
    let renderer = ImageRenderer(content: ResultView(result: result).padding().frame(width: 950, height: 250))
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == 950 && image.size.height == 250)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(png.count > 2_000)
    await database.close()
}
#endif

@MainActor
@Test func failedFileSwitchClearsPreviousObjectsAndActiveConnection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = WorkbenchModel(localRoot: directory)
    model.createLocal()
    await model.operation?.value
    model.allowWrites = true
    model.sql = "CREATE TABLE previous_file(value)"
    model.execute()
    await model.operation?.value
    #expect(model.objects.map(\.name) == ["previous_file"])
    let corrupt = directory.appendingPathComponent("corrupt.sqlite")
    try Data("synthetic non-SQLite content".utf8).write(to: corrupt)
    model.open(corrupt)
    #expect(model.fileName == nil && model.objects.isEmpty && model.result == nil && !model.allowWrites)
    await model.operation?.value
    #expect(model.error != nil && model.fileName == nil && model.objects.isEmpty && model.result == nil && !model.allowWrites)
    await #expect(throws: DatabaseError.notOpen) { try await model.database.execute("SELECT 1") }
    #expect(try Data(contentsOf: corrupt) == Data("synthetic non-SQLite content".utf8))
}

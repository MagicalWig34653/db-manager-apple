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

@MainActor
@Test func sourceSwitchAndFailedPostgresOpenClearActiveStateAndDraftPassword() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = WorkbenchModel(localRoot: directory)
    model.createLocal(); await model.operation?.value
    model.allowWrites = true; model.sql = "CREATE TABLE old_source(value)"
    model.execute(); await model.operation?.value
    #expect(model.objects.count == 1)
    model.password = "synthetic-old-password"
    model.changeSource(.postgres)
    #expect(model.fileName == nil && model.objects.isEmpty && model.result == nil && !model.allowWrites && model.password.isEmpty)
    await model.operation?.value
    model.host = "invalid/path"; model.databaseName = "synthetic"; model.username = "synthetic"; model.password = "synthetic-draft"
    model.connectPostgres()
    #expect(model.password.isEmpty)
    await model.operation?.value
    #expect(model.error != nil && model.fileName == nil && model.objects.isEmpty && model.result == nil)
    await #expect(throws: DatabaseError.notOpen) { try await model.database.execute("SELECT 1") }
    await #expect(throws: DatabaseError.notOpen) { try await model.postgres.execute("SELECT 1") }
    model.changeSource(.sqlite); await model.operation?.value
    model.createLocal(); await model.operation?.value
    #expect(model.fileName != nil && model.error == nil)
    model.close(); await model.operation?.value
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil))
func liveWorkbenchUsesDirectPostgresThenClearsFailedReplacement() async throws {
    let env = ProcessInfo.processInfo.environment
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = WorkbenchModel(localRoot: directory)
    model.changeSource(.postgres); await model.operation?.value
    model.host = "localhost"; model.port = try #require(env["DBM_A2_TLS_PORT"])
    model.databaseName = "probe"; model.username = "native_app"; model.password = "public-a2-fixture"
    let ca = try #require(env["DBM_A2_CA_FILE"])
    model.selectCA(URL(fileURLWithPath: ca))
    model.connectPostgres(); await model.operation?.value
    #expect(model.error == nil && model.fileName != nil && model.password.isEmpty && model.objects.contains { $0.name == "synthetic_values" })
    model.sql = "SELECT amount FROM synthetic_values"
    model.execute(); await model.operation?.value
    #expect(model.result?.rows[0][0] == Cell(kind: .decimal, value: "12345678901234567890.12345678901234567890"))
    model.port = "0"; model.password = "synthetic-invalid"
    model.connectPostgres()
    #expect(model.fileName == nil && model.objects.isEmpty && model.result == nil && !model.allowWrites && model.password.isEmpty)
    await model.operation?.value
    #expect(model.error != nil && model.fileName == nil && model.objects.isEmpty && model.result == nil)
    await #expect(throws: DatabaseError.notOpen) { try await model.postgres.execute("SELECT 1") }
    model.changeSource(.sqlite); await model.operation?.value
    model.createLocal(); await model.operation?.value
    #expect(model.fileName != nil && model.error == nil)
    model.close(); await model.operation?.value
}

@MainActor
@Test func cellDisplayKeepsNullEmptyAndTruncationDistinct() {
    #expect(WorkbenchModel.displayText(Cell(kind: .null)) == "NULL")
    #expect(WorkbenchModel.displayText(Cell(kind: .text, value: "")) == "\"\"")
    let long = String(repeating: "x", count: 600)
    #expect(WorkbenchModel.displayText(Cell(kind: .text, value: long)).count == 500)
    #expect(WorkbenchModel.fullText(Cell(kind: .text, value: long)).count == 600)
    #expect(WorkbenchModel.displayNote(Cell(kind: .text, value: long)).contains("gekürzt"))
    #expect(!WorkbenchModel.displayNote(Cell(kind: .integer, value: "1")).contains("gekürzt"))
}

#if os(macOS)
@MainActor
@Test func compactResultListRendersWithoutScreenRecording() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = SQLiteDatabase()
    try await database.open(directory.appendingPathComponent("synthetic.sqlite"), create: true)
    let result = try await database.execute("SELECT 1 AS a, 'b' AS b, NULL AS c, x'00' AS d UNION ALL SELECT 2,'',NULL,x''", limits: QueryLimits(maxRows: 10))
    let renderer = ImageRenderer(content: ResultView(result: result, forceCompact: true).padding().frame(width: 360, height: 300))
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == 360 && image.size.height == 300)
    #expect(try #require(image.tiffRepresentation).count > 2_000)
    await database.close()
}
#endif

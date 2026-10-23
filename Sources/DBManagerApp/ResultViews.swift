// SPDX-License-Identifier: AGPL-3.0-only
import DBManagerCore
import SwiftUI

/// Query result: wide grid on Mac/iPad, scrollable row list with detail sheet on compact width.
struct ResultView: View {
    let result: QueryResult
    var forceCompact: Bool? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { forceCompact ?? (sizeClass == .compact) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResultSummary(result: result)
            if compact { CompactResultList(result: result) } else { ResultGrid(result: result) }
        }
    }
}

struct ResultSummary: View {
    let result: QueryResult
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { content }
            VStack(alignment: .leading, spacing: 4) { content }
        }
    }

    @ViewBuilder private var content: some View {
        Text("\(result.rows.count) Zeilen · \(result.durationMS) ms").font(.headline)
        if let affected = result.rowsAffected { Text("Änderungen: \(affected)") }
        if result.truncated { Label("Zeilengrenze erreicht", systemImage: "ellipsis.circle").foregroundStyle(.orange) }
    }
}

struct ResultGrid: View {
    let result: QueryResult
    private let columnWidth: CGFloat = 190

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
                        Text(column.name).font(.system(.caption, design: .monospaced).bold())
                            .frame(width: columnWidth, alignment: .leading).padding(8)
                            .help(column.databaseType)
                    }
                }.background(.quaternary)
                ForEach(result.rows.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(result.rows[index].indices, id: \.self) { column in
                            let cell = result.rows[index][column]
                            VStack(alignment: .leading, spacing: 3) {
                                Text(WorkbenchModel.displayText(cell))
                                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text(WorkbenchModel.displayNote(cell))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: columnWidth, alignment: .leading).padding(8)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                    .contextMenu {
                        Button("Zeile kopieren", systemImage: "doc.on.doc") {
                            Clipboard.copy(result.rows[index].map { WorkbenchModel.fullText($0) }.joined(separator: "\t"))
                        }
                    }
                    Divider()
                }
            }
        }.frame(minHeight: 120)
    }
}

struct CompactResultList: View {
    let result: QueryResult
    @State private var selectedRow: RowSelection?

    struct RowSelection: Identifiable { let id: Int }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(result.rows.indices, id: \.self) { index in
                    Button { selectedRow = RowSelection(id: index) } label: {
                        CompactRowCard(result: result, index: index)
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 120)
        .sheet(item: $selectedRow) { selection in
            RowDetailView(result: result, index: selection.id) { selectedRow = nil }
        }
    }
}

struct CompactRowCard: View {
    let result: QueryResult
    let index: Int
    private let previewColumns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zeile \(index + 1)").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(0..<min(previewColumns, result.columns.count), id: \.self) { column in
                HStack(alignment: .firstTextBaseline) {
                    Text(result.columns[column].name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                    Text(WorkbenchModel.displayText(result.rows[index][column], limit: 80))
                        .font(.system(.footnote, design: .monospaced)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if result.columns.count > previewColumns {
                Text("+ \(result.columns.count - previewColumns) weitere Spalten").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct RowDetailView: View {
    let result: QueryResult
    let index: Int
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(result.columns.indices, id: \.self) { column in
                    let cell = result.rows[index][column]
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.columns[column].name + " · " + result.columns[column].databaseType)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(WorkbenchModel.displayText(cell))
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Text(WorkbenchModel.displayNote(cell)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Wert kopieren", systemImage: "doc.on.doc") { Clipboard.copy(WorkbenchModel.fullText(cell)) }
                    }
                }
            }
            .navigationTitle("Zeile \(index + 1)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: close) } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

import SwiftUI
import BacktestKit

enum Format {
    static func number(_ value: Double, digits: Int = 2) -> String {
        guard value.isFinite else { return value.isNaN ? "–" : (value > 0 ? "∞" : "−∞") }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func price(_ value: Double) -> String {
        number(value, digits: abs(value) >= 1000 ? 2 : (abs(value) >= 1 ? 4 : 6))
    }

    static func percent(_ value: Double, digits: Int = 2) -> String {
        guard value.isFinite else { return "–" }
        return (value > 0 ? "+" : "") + number(value, digits: digits) + "%"
    }

    static func signed(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return (value > 0 ? "+" : "") + number(value)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }
}

/// Editable list of script parameters (name + default value).
struct ParameterListEditor: View {
    @Binding var parameters: [ScriptParameter]

    var body: some View {
        ForEach($parameters) { $parameter in
            HStack {
                TextField("tên", text: $parameter.name)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("=")
                    .foregroundStyle(.secondary)
                TextField("mặc định", value: $parameter.defaultValue, format: .number)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
        }
        .onDelete { parameters.remove(atOffsets: $0) }
        Button {
            parameters.append(ScriptParameter(name: "param\(parameters.count + 1)", defaultValue: 14))
        } label: {
            Label("Thêm tham số", systemImage: "plus.circle")
        }
    }
}

/// Monospaced code editor with a row of buttons for symbols that are awkward
/// to type on the iOS keyboard.
struct ScriptEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 220

    private let snippets = ["(", ")", "[1]", ",", "=", "==", ">", "<", "and", "or", "not", "?", ":",
                            "close", "high", "low", "open", "ema(close, 20)", "sma(close, 20)",
                            "rsi(close, 14)", "atr(14)", "crossover(a, b)", "crossunder(a, b)",
                            "plot(x, \"tên\")", "hline(50)", "//"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: minHeight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(snippets, id: \.self) { snippet in
                        Button(snippet) { insert(snippet) }
                            .font(.caption.monospaced())
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func insert(_ snippet: String) {
        let needsSpace = !(text.last.map { $0.isWhitespace || $0 == "(" } ?? true) && snippet.first?.isLetter == true
        text += (needsSpace ? " " : "") + snippet
    }
}

/// Error box shown under editors.
struct ErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }
}

struct DatasetPicker: View {
    let datasets: [DatasetInfo]
    @Binding var selection: UUID?
    var title = "Dữ liệu"

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Chọn…").tag(UUID?.none)
            ForEach(datasets) { dataset in
                Text("\(dataset.name) · \(dataset.intervalLabel)").tag(Optional(dataset.id))
            }
        }
    }
}

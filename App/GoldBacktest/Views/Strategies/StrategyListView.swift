import SwiftUI
import BacktestKit

struct StrategyListView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: StrategyDefinition?

    var body: some View {
        List {
            Section {
                ForEach(store.strategies) { strategy in
                    Button {
                        editing = strategy
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(strategy.name).font(.headline)
                            if !strategy.summary.isEmpty {
                                Text(strategy.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            if !strategy.parameters.isEmpty {
                                Text(strategy.parameters.map { "\($0.name)=\(Format.number($0.defaultValue, digits: 2))" }.joined(separator: "  "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .leading) {
                        Button {
                            var copy = strategy
                            copy.id = UUID()
                            copy.name += " (bản sao)"
                            store.upsert(copy)
                        } label: {
                            Label("Nhân bản", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteStrategy(store.strategies[index].id) }
                }
            } footer: {
                Text("Vuốt sang phải để nhân bản, sang trái để xoá.")
            }
        }
        .navigationTitle("Chiến lược")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = StrategyDefinition(
                        name: "Chiến lược mới",
                        parameters: [ScriptParameter(name: "length", defaultValue: 20)],
                        script: """
                        basis = ema(close, length)
                        long_entry  = crossover(close, basis)
                        long_exit   = crossunder(close, basis)
                        short_entry = crossunder(close, basis)
                        short_exit  = crossover(close, basis)
                        plot(basis, "EMA")
                        """)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { strategy in
            StrategyEditorView(strategy: strategy)
        }
    }
}

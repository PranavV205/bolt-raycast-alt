import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var coordinator: SearchCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                SearchTextField(coordinator: coordinator)
                    .frame(height: 32)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)

            if !coordinator.results.isEmpty {
                Divider().opacity(0.5)
                resultsList
            }

            footer
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(Array(coordinator.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(
                            item: item,
                            isSelected: index == coordinator.selectedIndex,
                            isArmed: coordinator.armedConfirmationId == item.id,
                            shortcutHint: index < 9 ? "⌘\(index + 1)" : nil
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.execute(at: index, modifiers: [])
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: coordinator.selectedIndex) { newIndex in
                guard coordinator.results.indices.contains(newIndex) else { return }
                proxy.scrollTo(coordinator.results[newIndex].id, anchor: nil)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("↑↓ navigate")
            Text("⏎ run")
            Text("esc close")
            Spacer()
            if !coordinator.results.isEmpty {
                Text("\(coordinator.results.count) results")
            }
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary.opacity(0.8))
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

private struct ResultRow: View {
    let item: ResultItem
    let isSelected: Bool
    let isArmed: Bool
    let shortcutHint: String?

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                if isArmed {
                    Text("Press ⏎ again to confirm")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let accessory = item.accessory {
                Text(accessory)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }

            if isSelected, let hint = shortcutHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Text(item.kind.rawValue)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 10)
        .frame(height: 45)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.icon {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
        case .emoji(let char):
            Text(char).font(.system(size: 19))
        case .none:
            Image(systemName: "circle.dashed")
                .foregroundColor(.secondary)
        }
    }
}

// Native text field so we fully control first responder + key routing.
private struct SearchTextField: NSViewRepresentable {
    let coordinator: SearchCoordinator

    func makeCoordinator() -> Delegate { Delegate(coordinator: coordinator) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: 21, weight: .regular)
        tf.placeholderString = "Search apps, files, commands..."
        tf.delegate = context.coordinator
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        coordinator.textField = tf
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    final class Delegate: NSObject, NSTextFieldDelegate {
        let coordinator: SearchCoordinator
        init(coordinator: SearchCoordinator) { self.coordinator = coordinator }

        func controlTextDidChange(_ notification: Notification) {
            guard let tf = notification.object as? NSTextField else { return }
            coordinator.queryDidChange(tf.stringValue)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

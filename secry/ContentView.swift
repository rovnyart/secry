import SwiftUI
import AppKit

/// A concrete viewport is essential for MenuBarExtra: its window measures ideal
/// size, so an unconstrained ScrollView can otherwise be offered zero height.
struct ContentView: View {
    @Bindable var vault: Vault
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editor: EditorRoute?
    @State private var deleting: SecretSet?

    private var filtered: [SecretSet] {
        vault.sets.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.fields.contains { $0.key.localizedCaseInsensitiveContains(query) } }
    }
    private var selected: SecretSet? { vault.sets.first { $0.id == selectedID } }
    private var panelHeight: CGFloat {
        let ideal: CGFloat
        if deleting != nil { ideal = 340 }
        else if editor != nil || selected != nil { ideal = 540 }
        else if vault.sets.isEmpty { ideal = 380 }
        else { ideal = min(540, max(260, CGFloat(vault.sets.count) * 64 + 170)) }
        return min(ideal, max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let deleting {
                deletionConfirmation(for: deleting)
            } else if let editor {
                SecretEditor(vault: vault, existing: editor.set) { savedID in
                    self.editor = nil
                    if let savedID { selectedID = savedID; query = "" }
                }
            } else if let selected {
                SecretDetail(vault: vault, set: selected, back: { selectedID = nil }, edit: { editor = EditorRoute(set: selected) }, delete: { confirmDeletion(of: selected) })
            } else {
                library
            }
            if let error = vault.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { vault.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.padding(12).background(.quaternary)
            }
        }
        .frame(width: 380, height: panelHeight)
        .background { PanelMaterial() }
        .onDisappear { deleting = nil }
    }

    private func confirmDeletion(of set: SecretSet) {
        deleting = set
    }

    // MenuBarExtra is a transient panel. A system alert creates a second focus
    // surface whose clicks can dismiss the panel instead of reaching its buttons.
    // Keep confirmation in the very same view/window as the rest of the app.
    private func deletionConfirmation(for set: SecretSet) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Image(systemName: "trash")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text("Delete \(set.name)?")
                .font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("This removes the set from your Keychain.\nIt won’t revoke keys at their provider.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { deleting = nil } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }.keyboardShortcut(.cancelAction).buttonStyle(.bordered)
                Button(role: .destructive) {
                    if vault.delete(set) {
                        if selectedID == set.id { selectedID = nil }
                        deleting = nil
                    }
                } label: {
                    Text("Delete").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("confirm-delete-secret")
            }.controlSize(.large).padding(.top, 4)
            Spacer(minLength: 12)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("delete-confirmation")
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Text("secry").font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Menu {
                    Button("Close all agent access", systemImage: "lock") { vault.grants.removeAll() }
                    Divider()
                    Button("Quit secry", systemImage: "power") { NSApplication.shared.terminate(nil) }
                } label: { ControlSymbol("ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
                Button { editor = EditorRoute(set: nil) } label: {
                    ControlSymbol("plus")
                }.buttonStyle(QuietGlassStyle()).help("New secret set").accessibilityLabel("New secret set").keyboardShortcut("n").disabled(!vault.ready)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 13)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search secrets", text: $query).textFieldStyle(.plain).accessibilityIdentifier("secret-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.font(.system(size: 13)).padding(.horizontal, 11).frame(height: 34)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 16).padding(.bottom, 13)
            HStack {
                Text(query.isEmpty ? "Secrets" : "Results").fontWeight(.medium)
                Spacer()
                Text("\(filtered.count)").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 21).padding(.bottom, 7)
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: vault.sets.isEmpty ? "key.horizontal" : "magnifyingglass").font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                    Text(vault.sets.isEmpty ? "A little privacy.\nAlways within reach." : "No secrets found")
                        .font(.system(size: 19, weight: .medium)).multilineTextAlignment(.center)
                    Text(vault.sets.isEmpty ? "API keys, credentials, and private notes.\nSaved on your Mac. Ready when you are." : "Try another name or variable.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
                    if vault.sets.isEmpty {
                        Button("Add a secret", systemImage: "plus") { editor = EditorRoute(set: nil) }
                            .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4).disabled(!vault.ready)
                    }
                    Spacer(); Spacer().frame(height: 12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { set in
                            SecretRow(vault: vault, set: set) { selectedID = set.id }
                                .contextMenu {
                                    Button("Open") { selectedID = set.id }
                                    Button("Edit") { editor = EditorRoute(set: set) }
                                    Button("Copy .env") { vault.copy(SecretParser.env(set.fields)) }
                                    Divider()
                                    Button("Delete", role: .destructive) { confirmDeletion(of: set) }
                                }
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }.scrollIndicators(.visible).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("secret-list")
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: vault.notice == nil ? "lock.shield" : "checkmark")
                Text(vault.notice ?? "Only on your Mac")
                Spacer(minLength: 0)
                if !vault.bridgeReady { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help("Agent connection unavailable") }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 37)
        }
    }
}

private struct EditorRoute { let set: SecretSet? }

private struct SecretRow: View {
    @Bindable var vault: Vault
    let set: SecretSet
    let open: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: set.fields.count == 1 && set.fields[0].key == "SECRET" ? "doc.text" : "key.horizontal")
                    .font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(set.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(set.fields.count == 1 ? set.fields[0].key : "\(set.fields.count) variables")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 10)) { timeline in
                    if (vault.grants[set.id] ?? .distantPast) > timeline.date {
                        Image(systemName: "lock.open.fill").font(.system(size: 10)).foregroundStyle(.green).help("Agent access is open")
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).frame(height: 62).contentShape(Rectangle())
                .background(hovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityIdentifier("secret-row-\(set.name)")
    }
}

private struct SecretDetail: View {
    @Bindable var vault: Vault
    let set: SecretSet
    let back: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var revealed = Set<String>()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: back) { ControlSymbol("chevron.left") }
                    .buttonStyle(QuietGlassStyle()).accessibilityLabel("Back to secrets")
                Text(set.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button("Edit", action: edit).buttonStyle(.borderless)
                Menu {
                    Button("Copy .env") { vault.copy(SecretParser.env(set.fields)) }
                    Button("Delete", role: .destructive, action: delete)
                } label: { ControlSymbol("ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Secret options")
            }.padding(.horizontal, 20).frame(height: 64)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.fields.count == 1 ? "1 saved value" : "\(set.fields.count) saved values").font(.system(size: 12, weight: .medium))
                        Text("Updated \(set.updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(set.fields.enumerated()), id: \.element.id) { index, field in
                            SecretValueRow(field: field, isRevealed: revealed.contains(field.key), reveal: {
                                if revealed.contains(field.key) { revealed.remove(field.key) } else { revealed.insert(field.key) }
                            }, copy: { vault.copy(field.value) })
                            if index < set.fields.count - 1 { Divider().padding(.horizontal, 16) }
                        }
                    }.background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }.padding(20)
            }.frame(maxHeight: .infinity).accessibilityIdentifier("secret-values")
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let expiry = vault.grants[set.id] ?? .distantPast
                let allowed = expiry > timeline.date
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: allowed ? "lock.open" : "lock").foregroundStyle(allowed ? Color.green : .secondary).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(allowed ? "Available to agents" : "Agent access is closed").font(.system(size: 12, weight: .medium))
                            Text(allowed ? "Closes in \(min(15, max(1, Int(ceil(expiry.timeIntervalSince(timeline.date) / 60))))) min. Local apps can use this set." : "Allow local apps to use this set for 15 minutes.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if allowed { Button("Close") { vault.grants[set.id] = nil }.buttonStyle(.borderless).font(.system(size: 11)) }
                    }
                    Button {
                        if !allowed { vault.grants[set.id] = Date().addingTimeInterval(15 * 60) }
                        vault.agentInstruction(set)
                    } label: {
                        Label(allowed ? "Copy instructions for agent" : "Allow & copy for agent", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!vault.bridgeReady)
                    Text(vault.notice ?? "Instructions never contain your secret values.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center).frame(height: 14)
                }.padding(20)
            }
        }.onDisappear { revealed.removeAll() }
    }
}

/// Equal symbol canvases and equal hit targets keep differently shaped SF Symbols
/// optically centered. Never top-align raw Image labels in a button row.
private struct ControlSymbol: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image(systemName: name).resizable().scaledToFit()
            .fontWeight(.medium).frame(width: 15, height: 15)
            .frame(width: 30, height: 30, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SymbolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SymbolButtonSurface(configuration: configuration)
    }
    private struct SymbolButtonSurface: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(hovered ? .primary : .secondary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovered ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

private struct SecretValueRow: View {
    let field: SecretField
    let isRevealed: Bool
    let reveal: () -> Void
    let copy: () -> Void
    @State private var copied = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(field.key).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isRevealed ? field.value : "••••••••••••")
                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .center, spacing: 2) {
                Button(action: reveal) { ControlSymbol(isRevealed ? "eye.slash" : "eye") }
                    .help(isRevealed ? "Hide value" : "Reveal value")
                    .accessibilityLabel(isRevealed ? "Hide \(field.key)" : "Reveal \(field.key)")
                Button { copy(); copied = true } label: { ControlSymbol(copied ? "checkmark" : "doc.on.doc") }
                    .help("Copy value").accessibilityLabel("Copy \(field.key)")
            }.buttonStyle(SymbolButtonStyle()).fixedSize()
        }.padding(16)
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { copied = false }
            }
    }
}

private struct SecretEditor: View {
    @Bindable var vault: Vault
    let existing: SecretSet?
    let close: (UUID?) -> Void
    @State private var name = ""
    @State private var input = ""
    @State private var textMode = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    private var parsed: Result<[SecretField], Error> { Result { try SecretParser.parse(input, textMode: textMode) } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(existing == nil ? "New secret" : "Edit secret").font(.system(size: 14, weight: .semibold))
                HStack {
                    Button("Cancel") { close(nil) }.buttonStyle(.borderless).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save", action: save).buttonStyle(.borderedProminent).keyboardShortcut("s")
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (try? parsed.get()) == nil)
                }
            }.padding(.horizontal, 20).frame(height: 64)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Name").font(.system(size: 12, weight: .medium))
                        TextField("e.g. sentry", text: $name).textFieldStyle(.roundedBorder).controlSize(.large).focused($nameFocused).accessibilityIdentifier("secret-name")
                        Text("A short name you can ask your agent for.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Picker("Format", selection: $textMode) { Text(".env / JSON").tag(false); Text("Private text").tag(true) }.pickerStyle(.segmented).labelsHidden()
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $input).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                                .padding(8).accessibilityIdentifier("secret-input")
                            if input.isEmpty {
                                Text(textMode ? "Paste a token or a private note…" : "API_KEY=…\nPROJECT_ID=…")
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary).padding(13).allowsHitTesting(false)
                            }
                        }.frame(height: 175).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        HStack {
                            if case .success(let fields) = parsed {
                                Label("\(fields.count) \(fields.count == 1 ? "value" : "values") found", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                            } else { Text("Everything is parsed on your Mac.").foregroundStyle(.secondary) }
                            Spacer()
                            Button("Paste") { if let value = NSPasteboard.general.string(forType: .string) { input = value } }.buttonStyle(.borderless)
                        }.font(.system(size: 11))
                    }
                    if !input.isEmpty {
                        switch parsed {
                        case .success(let fields):
                            Text(fields.prefix(4).map(\.key).joined(separator: " · ") + (fields.count > 4 ? " · and \(fields.count - 4) more" : ""))
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3)
                        case .failure(let error):
                            Label(error.localizedDescription, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(20)
            }.frame(maxHeight: .infinity).accessibilityIdentifier("secret-editor-scroll")
            Divider()
            Label("Saved in Keychain. Shared only when you allow it.", systemImage: "lock.shield")
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 37)
        }.onAppear {
            if let existing {
                name = existing.name
                textMode = existing.fields.count == 1 && existing.fields[0].key == "SECRET"
                input = textMode ? existing.fields[0].value : SecretParser.env(existing.fields)
            }
            nameFocused = true
        }
    }
    private func save() {
        do {
            try vault.save(id: existing?.id, name: name, fields: parsed.get())
            let id = vault.sets.first { $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }?.id
            input = ""; close(id)
        } catch { self.error = error.localizedDescription }
    }
}

/// Use the system's glass, not an imitation made from dark cards and borders.
private struct PanelMaterial: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle().fill(.clear).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else { Rectangle().fill(.regularMaterial) }
    }
}

private struct QuietGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            configuration.label.background(.regularMaterial, in: Circle())
        }
    }
}

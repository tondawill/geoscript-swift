import GeoEngine
import SwiftUI

enum AppMode: String, CaseIterable, Identifiable {
    case geometry, graph
    var id: String { rawValue }
}

struct ContentView: View {
    @Binding var document: GeoDocument

    @State private var store = DrawingStore()
    @State private var showProtocol = true

    private var toolSelection: Binding<Tool?> {
        Binding(get: { store.tool }, set: { if let tool = $0 { store.tool = tool } })
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if store.mode == .geometry {
                    List(Tool.allCases, selection: toolSelection) { item in
                        Label {
                            Text(store.t("tool.\(item.rawValue)"))
                        } icon: {
                            ToolIcon(tool: item)
                        }
                        .tag(item)
                    }
                } else {
                    functionList
                }
            }
            .navigationTitle(store.mode == .graph ? (store.language == .cs ? "Funkce" : "Functions") : (store.language == .cs ? "Nástroje" : "Tools"))
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            detail
                .inspector(isPresented: $showProtocol) {
                    inspector.inspectorColumnWidth(min: 340, ideal: 390, max: 520)
                }
        }
        .toolbar { toolbar }
        .focusedSceneValue(\.drawingStore, store)
        .onAppear {
            store.load(document.contents)
        }
        .onChange(of: store.revision) { _, _ in
            document.contents = FileContents(construction: store.construction, sketch: store.sketch, graphs: store.graph.rows)
            document.text = store.fileText()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(store.t("mode.label"), selection: $store.mode) {
                ForEach(AppMode.allCases) { Text(store.t("mode.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(store.t("action.undo"), systemImage: "arrow.uturn.backward") { store.undo() }
                .disabled(!store.canUndo)
            Button(store.t("action.redo"), systemImage: "arrow.uturn.forward") { store.redo() }
                .disabled(!store.canRedo)
            if store.mode == .graph {
                graphTools
            } else {
                geometryTools
            }
            Picker(store.t("lang.label"), selection: $store.language) {
                ForEach(Language.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Button(store.mode == .graph ? store.t("graph.title") : store.t("protocol.title"), systemImage: "list.number") { showProtocol.toggle() }
                .help(store.mode == .graph ? store.t("graph.toggle") : store.t("protocol.toggle"))
        }
    }

    @ViewBuilder
    private var graphTools: some View {
        Button(store.t("graph.zoomOut"), systemImage: "minus.magnifyingglass") { store.graph.zoomCentre(1 / 1.5) }
        Button(store.t("graph.zoomIn"), systemImage: "plus.magnifyingglass") { store.graph.zoomCentre(1.5) }
        Button(store.t("graph.zoomHome"), systemImage: "house") { store.graph.home() }
        Button(store.t("action.deleteAll"), systemImage: "trash") { store.graph.deleteAll() }
            .disabled(store.graph.rows.isEmpty)
    }

    /// The Graphs sidebar: Move, the function cards (a family's forms indented under it while it is
    /// being placed), the Restrict, Intersect and Fill tools, and placing sideways.
    private var functionList: some View {
        let graph = store.graph
        let placingFamily = graph.placingKind?.family
        return List(selection: Binding<String?>(get: { sidebarTag(graph.tool) }, set: { pickSidebar($0) })) {
            Label { Text(store.t("tool.move")) } icon: { ToolIcon(tool: .move) }
                .tag("move")
            Section {
                card("linear", label: "graph.fn.linear", help: "graph.fn.linearName", icon: "Linear")
                ForEach(["parabola", "cubic", "trig"], id: \.self) { family in
                    card("family.\(family)", label: "graph.fn.\(family)", help: nil, icon: family.prefix(1).uppercased() + family.dropFirst())
                    if placingFamily == family {
                        ForEach(GraphStore.forms[family] ?? [], id: \.self) { kind in
                            let form = String(kind.rawValue.dropFirst(family.count + 1))
                            Text(store.t("graph.fn.form.\(form)"))
                                .padding(.leading, 30)
                                .help(functionTemplate(kind, sideways: graph.sideways, czech: store.language == .cs))
                                .tag(kind.rawValue)
                        }
                    }
                }
                card("hyperbola", label: "graph.fn.hyperbola", help: "graph.fn.hyperbolaName", icon: "Hyperbola")
                card("circle", label: "graph.fn.circle", help: "graph.fn.circleName", icon: "Circle")
                card("ellipse", label: "graph.fn.ellipse", help: "graph.fn.ellipseName", icon: "Ellipse")
            }
            Section {
                card("cut", label: "graph.fn.cut", help: "graph.fn.cutName", icon: "Restrict")
                card("intersect", label: "graph.fn.cross", help: "graph.fn.crossName", icon: "Intersect")
                card("fill", label: "graph.fn.fill", help: "graph.fn.fillName", icon: "Fill")
            }
            Section {
                Toggle(isOn: Binding(get: { graph.sideways }, set: { graph.sideways = $0 })) {
                    Text("\(store.t("graph.tray.sideways"))  x = f(y)")
                }
                .help(store.t("graph.tray.sidewaysTitle"))
                .selectionDisabled()
            }
        }
    }

    private func card(_ tag: String, label: String, help: String?, icon: String) -> some View {
        Label {
            Text(store.t(label))
        } icon: {
            FamilyIcon(name: icon).frame(width: 22, height: 22)
        }
        .help(help.map { store.t($0) } ?? "")
        .tag(tag)
    }

    private func sidebarTag(_ tool: GraphTool) -> String? {
        switch tool {
        case .move: return "move"
        case .place(let kind): return kind.rawValue
        case .cut: return "cut"
        case .intersect: return "intersect"
        case .fill: return "fill"
        }
    }

    private func pickSidebar(_ tag: String?) {
        let graph = store.graph
        switch tag {
        case nil, "move": graph.tool = .move
        case "cut": graph.tool = .cut
        case "intersect": graph.tool = .intersect
        case "fill": graph.tool = .fill
        case let tag? where tag.hasPrefix("family."): graph.pick(graph.lastForm(String(tag.dropFirst("family.".count))))
        case let tag?: if let kind = FunctionKind(rawValue: tag) { graph.pick(kind) }
        }
    }

    @ViewBuilder
    private var geometryTools: some View {
            Toggle(store.language == .cs ? "Mřížka" : "Grid", systemImage: "grid", isOn: $store.showGrid)
            Toggle(store.t("clean.title"), systemImage: "eye", isOn: $store.clean)
                .help("\(store.t("clean.help")) (H)")
            if store.clean {
                Toggle(store.t("clean.points"), systemImage: "smallcircle.filled.circle", isOn: $store.cleanPoints)
                    .help(store.t("clean.pointsHelp"))
            }
            Toggle(store.t("sketch.title"), systemImage: "pencil.tip", isOn: $store.showSketch)
                .help(store.t("sketch.toggle"))
            Button(store.t("action.deleteAll"), systemImage: "trash") { store.deleteAll() }
                .disabled(store.construction.objects.isEmpty)
    }

    @ViewBuilder
    private var inspector: some View {
        if store.mode == .graph {
            GraphPanel(store: store)
        } else {
            geometryInspector
        }
    }

    private var geometryInspector: some View {
        VStack(spacing: 0) {
            if let selection = store.selection, let object = store.construction.object(selection) {
                // Scrolls on small screens, so the steps below always keep some room.
                ScrollView {
                    SelectionPanel(store: store, object: object)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                // While a step is typed the symbol keypad needs the room too (the screen is small).
                .frame(maxHeight: store.session == nil ? 340 : 140)
                Divider()
            }
            StepsPanel(store: store)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.mode {
        case .geometry:
            HStack(spacing: 0) {
                ConstructionCanvas(store: store)
                    .overlay(alignment: .bottom) {
                        Text(store.hint)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                if store.showSketch {
                    Divider()
                    SketchDrawer(store: store).frame(width: 320)
                }
            }
        case .graph:
            GraphCanvas(store: store)
                .overlay(alignment: .bottom) {
                    Text(store.t(store.graph.hint.key))
                        .font(.callout)
                        .foregroundStyle(store.graph.hint.warning ? Color.orange : Color.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(14)
                        .allowsHitTesting(false)
                }
        }
    }
}

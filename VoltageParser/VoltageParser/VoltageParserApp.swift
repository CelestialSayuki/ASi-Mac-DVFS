import SwiftUI
import WebKit

#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

enum Function: Hashable {
    case parseCurrentMachine
    case viewExistingDevices
}

struct ContentView: View {
    #if os(macOS)
    @State private var selectedFunction: Function? = .parseCurrentMachine
    #else
    @State private var selectedFunction: Function? = nil
    #endif

    @State private var outputText: String = ""
    @State private var isLoading: Bool = false
    @State private var isPresentingFilePicker: Bool = false
    @State private var isWebViewActive: Bool = false
    @State private var webViewURL: URL? = nil

    var body: some View {
        NavigationSplitView {
            // --- Sidebar ---
            List(selection: $selectedFunction) {
                #if os(macOS)
                NavigationLink(value: Function.parseCurrentMachine) {
                    Text("sidebar.function.parseCurrent")
                }
                #endif

                NavigationLink(value: Function.viewExistingDevices) {
                    Text("sidebar.function.viewDevices")
                }
            }
            .navigationTitle("sidebar.title")
            .listStyle(.sidebar)
            .toolbar { // Toolbar for the Sidebar
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        isPresentingFilePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("toolbar.button.addFile")
                }
                #endif
            }
            .task {
                webViewURL = URL(string: "https://github.com/CelestialSayuki/ASi-Mac-DVFS/discussions/1")
            }
            #if os(macOS)
            .sheet(isPresented: $isPresentingFilePicker) {
                Text("toolbar.function.addFile")
            }
            #endif

        } detail: {
            VStack {
                switch selectedFunction {
                case .parseCurrentMachine:
                    #if os(macOS)
                    CurrentMachineParserView(outputText: $outputText, isLoading: $isLoading)
                    #else
                    Text("detail.placeholder.macOnly")
                        .foregroundColor(.secondary)
                    #endif
                case .viewExistingDevices:
                    if isWebViewActive, let url = webViewURL {
                        WebView(url: url)
                    } else {
                        Text("detail.placeholder.viewDevices")
                            .foregroundColor(.secondary)
                    }
                case nil:
                    Text("detail.placeholder.selectFunction")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .navigationTitle(detailViewTitle)
        }
        .onChange(of: selectedFunction) { newFunction in
            if newFunction == .viewExistingDevices {
                webViewURL = URL(string: "https://github.com/CelestialSayuki/ASi-Mac-DVFS/discussions/1")
                isWebViewActive = true
            } else {
                isWebViewActive = false
                webViewURL = nil
            }
        }
        .onAppear {
            #if os(macOS)
            if selectedFunction == .parseCurrentMachine && outputText.isEmpty {
                parseCurrentMachineData()
            }
            #endif
        }
    }

    private var detailViewTitle: LocalizedStringKey {
        switch selectedFunction {
        case .parseCurrentMachine:
            return "detail.title.currentInfo"
        case .viewExistingDevices:
            return "detail.title.existingDevices"
        case .none:
            return "detail.title.output"
        }
    }

    #if os(macOS)
    private func parseCurrentMachineData() {
        guard !isLoading else { return }

        isLoading = true
        outputText = NSLocalizedString("status.parsing", comment: "解析状态提示")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VoltageParser.getVoltageDataString()

            DispatchQueue.main.async {
                outputText = result ?? NSLocalizedString("status.error.generic", comment: "通用错误信息")
                isLoading = false
            }
        }
    }
    #endif
}

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        nsView.load(request)
    }
}

#if os(macOS)
struct VoltageDataRow: Identifiable {
    let id = UUID()
    let frequency: String
    let voltage: String
}

struct CurrentMachineParserView: View {
    @Binding var outputText: String
    @Binding var isLoading: Bool

    @State private var eCoreData: [VoltageDataRow] = []
    @State private var pCoreData: [VoltageDataRow] = []
    @State private var gpuData: [VoltageDataRow] = []
    @State private var aneData: [VoltageDataRow] = []
    @State private var cpuModel: String = ""
    @State private var selection = Set<UUID>()
    @State private var isSaving: Bool = false
    @State private var isSaveSuccessful: Bool = false

    private let cornerRadius: CGFloat = 8
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]
    private let minListHeight: CGFloat = 100
    private let horizontalPadding: CGFloat = 20
    private let topPadding: CGFloat = 40
    private let buttonPadding: CGFloat = 20

    var body: some View {
        VStack(alignment: .center) {
            if isLoading {
                ProgressView("status.parsing")
                    .padding(.bottom)
            } else {
                Text("parser.toolTitle")
                    .font(.headline)
                    .padding(.bottom, 5)

                if !cpuModel.isEmpty {
                    Text("CPU 型号: \(cpuModel)")
                        .font(.subheadline)
                        .padding(.bottom, 10)
                }

                LazyVGrid(columns: gridColumns) {
                    if !eCoreData.isEmpty {
                        VStack(alignment: .leading) {
                            Text(" E-core")
                                .font(.title3)
                                .padding(.bottom, 5)
                            voltageDataListForGrid(data: eCoreData)
                                .frame(minHeight: minListHeight)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !pCoreData.isEmpty {
                        VStack(alignment: .leading) {
                            Text(" P-core")
                                .font(.title3)
                                .padding(.bottom, 5)
                            voltageDataListForGrid(data: pCoreData)
                                .frame(minHeight: minListHeight)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !gpuData.isEmpty {
                        VStack(alignment: .leading) {
                            Text(" GPU")
                                .font(.title3)
                                .padding(.bottom, 5)
                            voltageDataListForGrid(data: gpuData)
                                .frame(minHeight: minListHeight)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !aneData.isEmpty {
                        VStack(alignment: .leading) {
                            Text(" ANE")
                                .font(.title3)
                                .padding(.bottom, 5)
                            voltageDataListForGrid(data: aneData)
                                .frame(minHeight: minListHeight)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity)

                if eCoreData.isEmpty && pCoreData.isEmpty && gpuData.isEmpty && aneData.isEmpty && !isLoading && outputText.isEmpty {
                    Text("没有可显示的数据。")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, horizontalPadding)
                } else if eCoreData.isEmpty && pCoreData.isEmpty && gpuData.isEmpty && aneData.isEmpty && !isLoading {
                    ScrollView {
                        Text(outputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity)
                }
                Spacer()
            }
        }
        .padding(.top, topPadding)
        .toolbar {
            ToolbarItem {
                Button {
                    isSaving = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(outputText, forType: .string)
                        isSaving = false
                        isSaveSuccessful = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isSaveSuccessful = false
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else if isSaveSuccessful {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("button.exportText", systemImage: "doc.on.clipboard")
                    }
                }
                .help("button.exportText")
                .disabled(isSaving || isLoading)
            }
        }
        .onAppear {
            parseVoltageData(from: outputText)
        }
        .onChange(of: outputText) { newOutput in
            parseVoltageData(from: newOutput)
        }
    }

    private func voltageDataListForGrid(data: [VoltageDataRow]) -> some View {
        List(selection: $selection) {
            ForEach(data) { row in
                HStack {
                    Text(row.frequency)
                        .frame(alignment: .leading)
                    Spacer()
                    Text(row.voltage)
                        .frame(alignment: .trailing)
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(PlainListStyle())
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    func parseVoltageData(from text: String) {
        guard !text.isEmpty else {
            self.cpuModel = ""
            self.eCoreData = []
            self.pCoreData = []
            self.gpuData = []
            self.aneData = []
            return
        }

        let lines = text.components(separatedBy: .newlines)
        var cpu = ""
        var eCore: [VoltageDataRow] = []
        var pCore: [VoltageDataRow] = []
        var gpu: [VoltageDataRow] = []
        var ane: [VoltageDataRow] = []
        var currentSection: String?

        for line in lines {
            if line.contains("CPU 型号:") {
                if let range = line.range(of: ":") {
                    if let afterColon = line.index(range.upperBound, offsetBy: 1, limitedBy: line.endIndex) {
                        cpu = String(line[afterColon...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else if line == "--- 电压数据 ---" {
                continue
            } else if line == "E-core:" {
                currentSection = "E-core"
            } else if line == "P-core:" {
                currentSection = "P-core"
            } else if line == "GPU:" {
                currentSection = "GPU"
            } else if line == "ANE:" {
                currentSection = "ANE"
            } else if let section = currentSection {
                let components = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if components.count == 2 {
                    let frequency = components[0]
                    let voltage = components[1]
                    let row = VoltageDataRow(frequency: frequency, voltage: voltage)
                    switch section {
                    case "E-core":
                        eCore.append(row)
                    case "P-core":
                        pCore.append(row)
                    case "GPU":
                        gpu.append(row)
                    case "ANE":
                        ane.append(row)
                    default:
                        break
                    }
                }
            }
        }

        self.cpuModel = cpu
        self.eCoreData = eCore
        self.pCoreData = pCore
        self.gpuData = gpu
        self.aneData = ane
    }
}
#endif

@main
struct VoltageParserApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

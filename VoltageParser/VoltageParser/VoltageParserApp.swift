import SwiftUI
import WebKit
import UniformTypeIdentifiers

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
    case parsedFileContent(URL)
}

struct VoltageDataRow: Identifiable {
    let id = UUID()
    let frequency: String
    let voltage: String
}

struct VoltageDataView: View {
    let cpuModel: String
    let eCoreData: [VoltageDataRow]
    let pCoreData: [VoltageDataRow]
    let gpuData: [VoltageDataRow]
    let aneData: [VoltageDataRow]

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]
    private let minListHeight: CGFloat = 100
    private let horizontalPadding: CGFloat = 20

    var body: some View {
        VStack(alignment: .center) {
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
                    voltageDataSection(title: " E-core", data: eCoreData)
                }
                if !pCoreData.isEmpty {
                    voltageDataSection(title: " P-core", data: pCoreData)
                }
                if !gpuData.isEmpty {
                    voltageDataSection(title: " GPU", data: gpuData)
                }
                if !aneData.isEmpty {
                    voltageDataSection(title: " ANE", data: aneData)
                }
            }
            .padding(.horizontal, horizontalPadding)

            if eCoreData.isEmpty && pCoreData.isEmpty && gpuData.isEmpty && aneData.isEmpty && !cpuModel.isEmpty {
                Text("未找到电压数据。")
                    .foregroundColor(.secondary)
                    .padding()
            } else if cpuModel.isEmpty {
                Text("未找到芯片型号信息。")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    private func voltageDataSection(title: String, data: [VoltageDataRow]) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title3)
                .padding(.bottom, 5)
            voltageDataListForGrid(data: data)
                .frame(minHeight: minListHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private func voltageDataListForGrid(data: [VoltageDataRow]) -> some View {
        List {
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
    @State private var selectedFileURL: URL? = nil
    @State private var addedFiles: [URL] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedFunction) {
                #if os(macOS)
                NavigationLink(value: Function.parseCurrentMachine) {
                    Text("sidebar.function.parseCurrent")
                }
                #endif

                NavigationLink(value: Function.viewExistingDevices) {
                    Text("sidebar.function.viewDevices")
                }

                if !addedFiles.isEmpty {
                    Section(header: Text("sidebar.header.addedFiles")) {
                        ForEach(addedFiles, id: \.self) { fileURL in
                            NavigationLink(value: Function.parsedFileContent(fileURL)) {
                                Text(fileURL.lastPathComponent)
                            }
                        }
                        .onDelete(perform: removeFile)
                    }
                }
            }
            .navigationTitle("sidebar.title")
            .listStyle(.sidebar)
            .toolbar {
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
            .background(
                OpenFileTriggerView(
                    isPresenting: $isPresentingFilePicker,
                    selectedFileURL: $selectedFileURL,
                    allowedFileTypes: ["txt", "ioreg"],
                    pickerPrompt: "选择要加载的文本或 ioreg 文件",
                    onFileSelected: handleSelectedFile
                )
                .frame(width: 0, height: 0)
            )
            #endif

        } detail: {
            VStack {
                switch selectedFunction {
                case .parseCurrentMachine:
                    CurrentMachineParserView(outputText: $outputText, isLoading: $isLoading)
                case .viewExistingDevices:
                    #if os(macOS)
                    if isWebViewActive, let url = webViewURL {
                        WebView(url: url)
                    } else {
                        Text("detail.placeholder.viewDevices")
                            .foregroundColor(.secondary)
                    }
                    #endif
                case .parsedFileContent(let url):
                    ParsedFileDetailView(fileURL: url)
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
        case .parsedFileContent(let url):
            return LocalizedStringKey(url.lastPathComponent)
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

    private func handleSelectedFile(fileURL: URL?) {
        isPresentingFilePicker = false

        if let fileURL = fileURL {
            print("选定的文件 URL: \(fileURL)")
            addedFiles.append(fileURL)
            selectedFunction = .parsedFileContent(fileURL)
        }
    }

    private func removeFile(at offsets: IndexSet) {
        addedFiles.remove(atOffsets: offsets)
        if addedFiles.isEmpty {
            selectedFunction = .parseCurrentMachine // Or some default state
        } else if let current = selectedFunction, case .parsedFileContent(let url) = current, !addedFiles.contains(url) {
            selectedFunction = .parsedFileContent(addedFiles.first!) // Select the first remaining file
        }
    }
    #endif
}

#if os(macOS)
struct OpenFileTriggerView: NSViewRepresentable {
    @Binding var isPresenting: Bool
    @Binding var selectedFileURL: URL?
    let allowedFileTypes: [String]
    let pickerPrompt: String
    var onFileSelected: (URL?) -> Void

    func makeNSView(context: Context) -> NSView {
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresenting {
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true

                panel.message = pickerPrompt

                var allowedUTTypes: [UTType] = []
                for type in allowedFileTypes {
                    if let utType = UTType(filenameExtension: type) {
                        allowedUTTypes.append(utType)
                    }
                }
                if !allowedUTTypes.isEmpty {
                    panel.allowedContentTypes = allowedUTTypes
                }

                panel.begin { response in
                    DispatchQueue.main.async {
                        if response == .OK, let url = panel.url {
                            selectedFileURL = url
                            onFileSelected(url)
                        } else {
                            selectedFileURL = nil
                            onFileSelected(nil)
                        }
                        isPresenting = false
                    }
                }
            }
        }
    }
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

struct CurrentMachineParserView: View {
    @Binding var outputText: String
    @Binding var isLoading: Bool

    @State private var eCoreData: [VoltageDataRow] = []
    @State private var pCoreData: [VoltageDataRow] = []
    @State private var gpuData: [VoltageDataRow] = []
    @State private var aneData: [VoltageDataRow] = []
    @State private var cpuModel: String = ""
    @State private var isSaving: Bool = false
    @State private var isSaveSuccessful: Bool = false

    private let topPadding: CGFloat = 40
    private let buttonPadding: CGFloat = 20

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("status.parsing")
                    .padding(.bottom)
            } else if !cpuModel.isEmpty || !eCoreData.isEmpty || !pCoreData.isEmpty || !gpuData.isEmpty || !aneData.isEmpty {
                VoltageDataView(cpuModel: cpuModel, eCoreData: eCoreData, pCoreData: pCoreData, gpuData: gpuData, aneData: aneData)
            } else if !outputText.isEmpty {
                ScrollView {
                    Text(outputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            } else {
                Text("没有可显示的数据。")
                    .foregroundColor(.secondary)
                    .padding()
            }
            Spacer()
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

struct ParsedFileDetailView: View {
    let fileURL: URL
    @State private var chipModel: String?
    @State private var errorMessage: String?

    @State private var cpuModel: String = ""
    @State private var eCoreData: [VoltageDataRow] = []
    @State private var pCoreData: [VoltageDataRow] = []
    @State private var gpuData: [VoltageDataRow] = []
    @State private var aneData: [VoltageDataRow] = []

    private let topPadding: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                if let error = errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                } else if !cpuModel.isEmpty || !eCoreData.isEmpty || !pCoreData.isEmpty || !gpuData.isEmpty || !aneData.isEmpty {
                    VoltageDataView(cpuModel: cpuModel, eCoreData: eCoreData, pCoreData: pCoreData, gpuData: gpuData, aneData: aneData)
                } else if chipModel == nil && errorMessage == nil {
                    Text("未找到芯片型号信息。")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text("未找到电压数据。")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.top, topPadding)
        }
        .navigationTitle(fileURL.lastPathComponent)
        .onAppear {
            parseFileContent(from: fileURL)
        }
    }

    private func parseFileContent(from fileURL: URL) {
        do {
            let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
            parse(fileContent: fileContent)
        } catch {
            errorMessage = "读取文件失败: \(error.localizedDescription)"
        }
    }

    private func parse(fileContent: String) {
        // 1. 查找芯片型号
        let ioClassRegex = try! NSRegularExpression(pattern: #""IOClass" = "Apple([a-zA-Z0-9]+)PMGR""#)
        if let match = ioClassRegex.firstMatch(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent)) {
            if let range = Range(match.range(at: 1), in: fileContent) {
                chipModel = String(fileContent[range])
                cpuModel = chipModel ?? ""
                print("找到芯片型号: \(chipModel ?? "未知")")
            }
        }

        // 2. 查找有效的电压状态行并解析数据
        let voltageStatesRegex = try! NSRegularExpression(pattern: #""voltage-states(1-sram|5-sram|8|9)\" = <([0-9a-fA-F]+)>"#)
        let matches = voltageStatesRegex.matches(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent))

        var parsedVoltageData: [String: [VoltageDataRow]] = [:]

        for match in matches {
            if match.numberOfRanges == 3 {
                if let keyRange = Range(match.range(at: 1), in: fileContent) {
                    let key = String(fileContent[keyRange])
                    if let hexDataRange = Range(match.range(at: 2), in: fileContent) {
                        let hexString = String(fileContent[hexDataRange])

                        if let parsedRows = parseHexString(key: key, hexString: hexString, chipModel: chipModel) {
                            let coreType = getCoreType(from: key)
                            parsedVoltageData[coreType, default: []].append(contentsOf: parsedRows)
                        }
                    }
                }
            }
        }

        eCoreData = parsedVoltageData["E-core"] ?? []
        pCoreData = parsedVoltageData["P-core"] ?? []
        gpuData = parsedVoltageData["GPU"] ?? []
        aneData = parsedVoltageData["ANE"] ?? []
    }

    func getCoreType(from key: String) -> String {
        if key == "1-sram" { return "E-core" }
        if key == "5-sram" { return "P-core" }
        if key == "8" { return "ANE" }
        if key == "9" { return "GPU" }
        return "Unknown"
    }

    func parseHexString(key: String, hexString: String, chipModel: String?) -> [VoltageDataRow]? {
        guard let data = Data(hexString: hexString) else { return nil }
        var voltageRows: [VoltageDataRow] = []
        let bytes = [UInt8](data)
        let entrySize = 8

        for i in stride(from: 0, to: bytes.count, by: entrySize) {
            if i + 8 <= bytes.count {
                let freqBytes = Data(bytes[i..<i+4])
                let voltBytes = Data(bytes[i+4..<i+8])

                let frequencyRaw = freqBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                let voltageRaw = voltBytes.withUnsafeBytes { $0.load(as: UInt32.self) }

                let frequency = frequencyRaw
                let voltage = voltageRaw

                let isLegacy = chipModel?.contains("M1") == true || chipModel?.contains("M2") == true || chipModel?.contains("M3") == true
                let freqValue = Double(frequency) * (isLegacy ? 1e-6 : 1e-3)
                let voltageValue = voltage == 0xFFFFFFFF ? 0 : UInt(voltage)

                if freqValue > 0 {
                    voltageRows.append(VoltageDataRow(frequency: String(format: "%.2f MHz", freqValue), voltage: voltageValue > 0 ? String(voltageValue) : "Unsupported"))
                }
            }
        }
        return voltageRows
    }
}

extension Data {
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)
        for i in 0..<length {
            let startIndex = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let endIndex = hexString.index(startIndex, offsetBy: 2)
            guard let byte = UInt8(hexString[startIndex..<endIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
        }
        self = data
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

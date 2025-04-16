import SwiftUI
import WebKit
import UniformTypeIdentifiers
import Charts

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

struct VoltageDataPoint: Identifiable {
    let id = UUID()
    let coreType: String
    let frequency: Double
    let voltage: Double
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
                        #if os(macOS)
                        .onDelete(perform: removeFile)
                        #endif
                    }
                }
            }
            .navigationTitle("sidebar.title")
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        isPresentingFilePicker = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .help("toolbar.button.addFile")
                }
            }
            .task {
                webViewURL = URL(string: "https://github.com/CelestialSayuki/ASi-Mac-DVFS/discussions/1")
            }
            .fileImporter(
                isPresented: $isPresentingFilePicker,
                allowedContentTypes: [.text, .init(filenameExtension: "ioreg")!],
                allowsMultipleSelection: false
            ) { result in
                handleFilePickerResult(result)
            }
        } detail: {
            VStack {
                switch selectedFunction {
                case .parseCurrentMachine:
                    #if os(macOS)
                    CurrentMachineParserView(outputText: $outputText, isLoading: $isLoading)
                    #endif
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

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        isPresentingFilePicker = false
        switch result {
        case .success(let urls):
            if let fileURL = urls.first {
                let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
                print("Selected file URL: \(fileURL), Access granted: \(didStartAccessing)")
                addedFiles.append(fileURL)
                selectedFunction = .parsedFileContent(fileURL)
            }
        case .failure(let error):
            print("File picker error: \(error.localizedDescription)")
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

    private func removeFile(at offsets: IndexSet) {
        addedFiles.remove(atOffsets: offsets)
        if addedFiles.isEmpty {
            selectedFunction = .parseCurrentMachine
        } else if let current = selectedFunction, case .parsedFileContent(let url) = current, !addedFiles.contains(url) {
            selectedFunction = .parsedFileContent(addedFiles.first!)
        }
    }
    #endif
}

#if os(macOS)
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
#endif

struct VoltageChart: View {
    let dataPoints: [VoltageDataPoint]

    var body: some View {
        Chart {
            ForEach(dataPoints) { dataPoint in
                LineMark(
                    x: .value("Frequency", dataPoint.frequency),
                    y: .value("Voltage", dataPoint.voltage)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Core Type", dataPoint.coreType))
                PointMark(
                    x: .value("Frequency", dataPoint.frequency),
                    y: .value("Voltage", dataPoint.voltage)
                )
                .foregroundStyle(by: .value("Core Type", dataPoint.coreType))
                .symbolSize(8)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let location = value.location
                                if let (x, _) = proxy.value(at: location, as: (Double, Double).self) {
                                    findClosestDataPoint(x: x)
                                }
                            }
                    )
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks {
                AxisValueLabel()
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(minHeight: 200)
        .padding()
        #if os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private func findClosestDataPoint(x: Double) {
        if let closestPoint = dataPoints.min(by: {
            abs($0.frequency - x) < abs($1.frequency - x)
        }) {
            print("Hovered over: Frequency \(closestPoint.frequency), Voltage \(closestPoint.voltage), Core \(closestPoint.coreType)")
        }
    }
}

struct CombinedVoltageChartView: View {
    let allDataPoints: [VoltageDataPoint]
    @Binding var isEcoreVisible: Bool
    @Binding var isPcoreVisible: Bool
    @Binding var isGpuVisible: Bool
    @Binding var isAneVisible: Bool

    var visibleDataPoints: [VoltageDataPoint] {
        allDataPoints.filter(shouldShowDataPoint)
    }

    private func shouldShowDataPoint(_ dataPoint: VoltageDataPoint) -> Bool {
        switch dataPoint.coreType {
        case "E-core":
            return isEcoreVisible
        case "P-core":
            return isPcoreVisible
        case "GPU":
            return isGpuVisible
        case "ANE":
            return isAneVisible
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("电压数据")
                .font(.title3)
                .padding(.bottom, 5)

            if !allDataPoints.isEmpty {
                VoltageChart(dataPoints: visibleDataPoints)

                HStack {
                    Spacer()
                    Text("Frequency (MHz)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .center) {
                    Text("Voltage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(-90))
                        .offset(x: -20)
                    Spacer()
                }
                HStack {
                    Toggle("E-core", isOn: $isEcoreVisible)
                    Toggle("P-core", isOn: $isPcoreVisible)
                    Toggle("GPU", isOn: $isGpuVisible)
                    Toggle("ANE", isOn: $isAneVisible)
                }
                .padding(.horizontal)
            } else {
                Text("No voltage data available.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CurrentMachineParserView: View {
    @Binding var outputText: String
    @Binding var isLoading: Bool

    @State private var allVoltageDataPoints: [VoltageDataPoint] = []
    @State private var cpuModel: String = ""
    @State private var isSaving: Bool = false
    @State private var isSaveSuccessful: Bool = false

    @State private var isEcoreVisible: Bool = true
    @State private var isPcoreVisible: Bool = true
    @State private var isGpuVisible: Bool = true
    @State private var isAneVisible: Bool = true

    private let topPadding: CGFloat = 40
    private let buttonPadding: CGFloat = 20

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("status.parsing")
                    .padding(.bottom)
            } else if !cpuModel.isEmpty || !allVoltageDataPoints.isEmpty {
                VStack {
                    Text("parser.toolTitle")
                        .font(.headline)
                        .padding(.bottom, 5)

                    if !cpuModel.isEmpty {
                        Text("CPU 型号: \(cpuModel)")
                            .font(.subheadline)
                            .padding(.bottom, 10)
                    }

                    CombinedVoltageChartView(
                        allDataPoints: allVoltageDataPoints,
                        isEcoreVisible: $isEcoreVisible,
                        isPcoreVisible: $isPcoreVisible,
                        isGpuVisible: $isGpuVisible,
                        isAneVisible: $isAneVisible
                    )
                    .padding(.horizontal, 20)

                    if allVoltageDataPoints.isEmpty && !cpuModel.isEmpty {
                        Text("未找到电压数据。")
                            .foregroundColor(.secondary)
                            .padding()
                    } else if cpuModel.isEmpty && !allVoltageDataPoints.isEmpty {
                        Text("未找到芯片型号信息。")
                            .foregroundColor(.secondary)
                            .padding()
                    } else if cpuModel.isEmpty && allVoltageDataPoints.isEmpty {
                        Text("未找到芯片型号信息和电压数据。")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
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
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(outputText, forType: .string)
                        #else
                        UIPasteboard.general.string = outputText
                        #endif
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
            self.allVoltageDataPoints = []
            return
        }

        let lines = text.components(separatedBy: .newlines)
        var cpu = ""
        var allPoints: [VoltageDataPoint] = []
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
                    if let frequencyString = components.first, let voltageString = components.last {
                        if let frequency = Double(frequencyString.replacingOccurrences(of: " MHz", with: "")),
                           let voltage = Double(voltageString.replacingOccurrences(of: " mV", with: "").replacingOccurrences(of: "Unsupported", with: "0")) {
                            let dataPoint = VoltageDataPoint(coreType: section, frequency: frequency, voltage: voltage)
                            allPoints.append(dataPoint)
                        } else if let frequency = Double(frequencyString.replacingOccurrences(of: " MHz", with: "")), voltageString == "Unsupported" {
                            let dataPoint = VoltageDataPoint(coreType: section, frequency: frequency, voltage: 0)
                            allPoints.append(dataPoint)
                        }
                    }
                }
            }
        }

        self.cpuModel = cpu
        self.allVoltageDataPoints = allPoints
    }
}

struct ParsedFileDetailView: View {
    let fileURL: URL
    @State private var chipModel: String?
    @State private var errorMessage: String?
    @State private var allVoltageDataPoints: [VoltageDataPoint] = []
    @State private var cpuModel: String = ""
    @State private var isEcoreVisible: Bool = true
    @State private var isPcoreVisible: Bool = true
    @State private var isGpuVisible: Bool = true
    @State private var isAneVisible: Bool = true

    private let topPadding: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                if let error = errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                } else if !cpuModel.isEmpty || !allVoltageDataPoints.isEmpty {
                    VStack {
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .padding(.bottom, 5)

                        if !cpuModel.isEmpty {
                            Text("CPU 型号: \(cpuModel)")
                                .font(.subheadline)
                                .padding(.bottom, 10)
                        }

                        CombinedVoltageChartView(
                            allDataPoints: allVoltageDataPoints,
                            isEcoreVisible: $isEcoreVisible,
                            isPcoreVisible: $isPcoreVisible,
                            isGpuVisible: $isGpuVisible,
                            isAneVisible: $isAneVisible
                        )
                        .padding(.horizontal, 20)

                        if allVoltageDataPoints.isEmpty && !cpuModel.isEmpty {
                            Text("未找到电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if cpuModel.isEmpty && !allVoltageDataPoints.isEmpty {
                            Text("未找到芯片型号信息。")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if cpuModel.isEmpty && allVoltageDataPoints.isEmpty {
                            Text("未找到芯片型号信息和电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
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
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
            parse(fileContent: fileContent)
        } catch {
            errorMessage = "读取文件失败: \(error.localizedDescription)"
        }
    }

    private func parse(fileContent: String) {
        let ioClassRegex = try! NSRegularExpression(pattern: #""IOClass" = "Apple([a-zA-Z0-9]+)PMGR""#)
        if let match = ioClassRegex.firstMatch(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent)) {
            if let range = Range(match.range(at: 1), in: fileContent) {
                chipModel = String(fileContent[range])
                cpuModel = chipModel ?? ""
                print("找到芯片型号: \(chipModel ?? "未知")")
            }
        }

        let voltageStatesRegex = try! NSRegularExpression(pattern: #""voltage-states(1-sram|5-sram|8|9)\" = <([0-9a-fA-F]+)>"#)
        let matches = voltageStatesRegex.matches(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent))

        var allPoints: [VoltageDataPoint] = []

        for match in matches {
            if match.numberOfRanges == 3 {
                if let keyRange = Range(match.range(at: 1), in: fileContent) {
                    let key = String(fileContent[keyRange])
                    if let hexDataRange = Range(match.range(at: 2), in: fileContent) {
                        let hexString = String(fileContent[hexDataRange])
                        if let parsedRows = parseHexString(key: key, hexString: hexString, chipModel: chipModel) {
                            let coreType = getCoreType(from: key)
                            allPoints.append(contentsOf: parsedRows.map {
                                VoltageDataPoint(coreType: coreType, frequency: $0.frequency, voltage: $0.voltage)
                            })
                        }
                    }
                }
            }
        }

        self.allVoltageDataPoints = allPoints
    }

    func getCoreType(from key: String) -> String {
        if key == "1-sram" { return "E-core" }
        if key == "5-sram" { return "P-core" }
        if key == "8" { return "ANE" }
        if key == "9" { return "GPU" }
        return "Unknown"
    }

    func parseHexString(key: String, hexString: String, chipModel: String?) -> [VoltageDataPoint]? {
        guard let data = Data(hexString: hexString) else { return nil }
        var voltagePoints: [VoltageDataPoint] = []
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
                let voltageValue = voltage == 0xFFFFFFFF ? 0 : Double(UInt(voltage))

                if freqValue > 0 {
                    voltagePoints.append(VoltageDataPoint(coreType: "Unknown", frequency: freqValue, voltage: voltageValue))
                }
            }
        }
        return voltagePoints
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

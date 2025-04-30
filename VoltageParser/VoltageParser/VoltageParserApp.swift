import SwiftUI
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

struct VoltageDataPoint: Identifiable, Equatable {
    let id = UUID()
    let coreType: String
    let frequency: Double
    let voltage: Double

    static func == (lhs: VoltageDataPoint, rhs: VoltageDataPoint) -> Bool {
        return lhs.id == rhs.id &&
               lhs.coreType == rhs.coreType &&
               lhs.frequency == rhs.frequency &&
               lhs.voltage == rhs.voltage
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
    @State private var selectedFileURL: URL? = nil
    @State private var addedFiles: [URL] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFunction: $selectedFunction,
                addedFiles: $addedFiles,
                isPresentingFilePicker: $isPresentingFilePicker
            )
            #if os(macOS)
            .frame(width: 200)
            .navigationSplitViewColumnWidth(200)
            #else
            .frame(width: 300)
            .navigationSplitViewColumnWidth(300)
            #endif
        } detail: {
            DetailView(
                selectedFunction: selectedFunction,
                outputText: $outputText,
                isLoading: $isLoading
            )
        }
        .navigationSplitViewStyle(.balanced) // 确保平衡布局
        .onAppear {
            #if os(macOS)
            if selectedFunction == .parseCurrentMachine && outputText.isEmpty {
                parseCurrentMachineData()
            }
            #endif
        }
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [.text, .init(filenameExtension: "ioreg")!],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
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
                addedFiles.append(fileURL)
                selectedFunction = .parsedFileContent(fileURL)
            }
        case .failure(_): break
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

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedFunction: Function?
    @Binding var addedFiles: [URL]
    @Binding var isPresentingFilePicker: Bool

    var body: some View {
        List(selection: $selectedFunction) {
            #if os(macOS)
            SidebarItemView(
                value: .parseCurrentMachine,
                icon: "laptopcomputer",
                iconSize: 20,
                title: LocalizedStringKey("sidebar.function.parseCurrent"),
                isSelected: selectedFunction == .parseCurrentMachine
            )
            #endif

            SidebarItemView(
                value: .viewExistingDevices,
                icon: "cpu",
                iconSize: 22,
                title: LocalizedStringKey("sidebar.function.viewDevices"),
                isSelected: selectedFunction == .viewExistingDevices
            )

            if !addedFiles.isEmpty {
                Section(header: Text("sidebar.header.addedFiles")) {
                    ForEach(addedFiles, id: \.self) { fileURL in
                        SidebarItemView(
                            value: .parsedFileContent(fileURL),
                            icon: "doc.text",
                            iconSize: 22,
                            title: LocalizedStringKey(fileURL.lastPathComponent),
                            isSelected: selectedFunction == .parsedFileContent(fileURL)
                        )
                    }
                    #if os(macOS)
                    .onDelete(perform: removeFile)
                    #endif
                }
            }
        }
        .navigationTitle("sidebar.title")
        .listStyle(.sidebar)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        #if os(macOS)
        .padding(.horizontal, 12)
        #endif
        .accentColor(.clear)
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
    }

    #if os(macOS)
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

// MARK: - Sidebar Item View
struct SidebarItemView: View {
    let value: Function
    let icon: String
    let iconSize: CGFloat
    let title: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        NavigationLink(value: value) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundColor(.gray)
                    .frame(width: 20, height: 20)
                    .padding(.trailing, 8)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.black)
            }
            .padding(.vertical, 8)
            .environment(\.colorScheme, .light)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected ? AnyView(selectedBackgroundView()) : AnyView(Color.clear)
        )
    }

    @ViewBuilder
    private func selectedBackgroundView() -> some View {
        #if os(macOS)
        VisualEffectView(material: .selection, blendingMode: .withinWindow)
            .overlay(Color.gray.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        #else
        VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            .overlay(Color.gray.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        #endif
    }
}

// MARK: - Detail View
struct DetailView: View {
    let selectedFunction: Function?
    @Binding var outputText: String
    @Binding var isLoading: Bool

    var body: some View {
        VStack {
            switch selectedFunction {
            case .parseCurrentMachine:
                #if os(macOS)
                CurrentMachineParserView(outputText: $outputText, isLoading: $isLoading)
                #endif
            case .viewExistingDevices:
                Text("detail.placeholder.viewDevices")
                    .foregroundColor(.secondary)
            case .parsedFileContent(let url):
                ParsedFileDetailView(fileURL: url)
                    .id(url)
            case nil:
                Text("detail.placeholder.selectFunction")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        #if os(macOS)
        .background(Color.white)
        #endif
        .navigationTitle(detailViewTitle)
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
}

struct VoltageChart: View {
    let dataPoints: [VoltageDataPoint]
    @State private var selectedPoint: VoltageDataPoint?

    private let coreTypeColors: [String: Color] = [
        "E-core": .blue,
        "P-core": .red,
        "GPU": .green,
        "ANE": .yellow
    ]

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
        .chartForegroundStyleScale([
            "E-core": coreTypeColors["E-core"]!,
            "P-core": coreTypeColors["P-core"]!,
            "GPU": coreTypeColors["GPU"]!,
            "ANE": coreTypeColors["ANE"]!
        ])
        .chartOverlay { proxy in
            GeometryReader { geo in
                TooltipOverlay(
                    proxy: proxy,
                    selectedPoint: $selectedPoint,
                    dataPoints: dataPoints,
                    chartSize: geo.size,
                    coreTypeColors: coreTypeColors
                )
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("Frequency (MHz)", position: .bottom, alignment: .center)
        .chartYAxis {
            AxisMarks {
                AxisValueLabel()
            }
        }
        .chartYAxisLabel("Voltage (mV)", position: .leading, alignment: .center)
        .chartLegend(position: .top, alignment: .leading)
        .frame(minHeight: 200)
        .padding()
        #if os(macOS)
        .background(
            Color(.windowBackgroundColor)
                .opacity(0.8)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        #else
        .background(
            Color(.systemGroupedBackground)
                .opacity(0.8)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        #endif
        .padding(.horizontal, 4)
    }
}

private struct TooltipOverlay: View {
    let proxy: ChartProxy
    @Binding var selectedPoint: VoltageDataPoint?
    let dataPoints: [VoltageDataPoint]
    let chartSize: CGSize
    let coreTypeColors: [String: Color]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            if let (x, y) = proxy.value(at: value.location, as: (Double, Double).self) {
                                selectedPoint = findClosestDataPoint(x: x, y: y)
                            }
                        }
                        .onEnded { _ in
                            selectedPoint = nil
                        }
                )
                #if os(macOS)
                .onHover { isHovering in
                    if !isHovering {
                        selectedPoint = nil
                    }
                }
                #endif
            if let point = selectedPoint {
                TooltipView(
                    point: point,
                    position: proxy.position(for: (x: point.frequency, y: point.voltage)) ?? .zero,
                    chartSize: chartSize,
                    coreTypeColors: coreTypeColors
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: selectedPoint)
            }
        }
    }

    private func findClosestDataPoint(x: Double, y: Double) -> VoltageDataPoint? {
        guard !dataPoints.isEmpty else {
            return nil
        }
        let closest = dataPoints.min(by: {
            let dist1 = pow($0.frequency - x, 2) + pow($0.voltage - y, 2)
            let dist2 = pow($1.frequency - x, 2) + pow($1.voltage - y, 2)
            return dist1 < dist2
        })
        return closest
    }
}

private struct TooltipView: View {
    let point: VoltageDataPoint
    let position: CGPoint
    let chartSize: CGSize
    let coreTypeColors: [String: Color]

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(coreTypeColors[point.coreType] ?? .gray)
                .frame(width: 8, height: 8)
            Text("\(point.coreType)\n\(String(format: "%.0f MHz", point.frequency))\n\(String(format: "%.0f mV", point.voltage))")
                .font(.caption)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .background(
            ZStack {
                #if os(macOS)
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                Color(.windowBackgroundColor).opacity(0.6)
                #else
                VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
                Color(.systemGroupedBackground).opacity(0.6)
                #endif
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
        )
        .position(
            x: calculateXPosition(),
            y: calculateYPosition()
        )
        .fixedSize()
    }

    private func calculateXPosition() -> CGFloat {
        let tooltipWidth: CGFloat = 120
        let offsetX: CGFloat = 10
        let x = position.x + offsetX
        if x + tooltipWidth > chartSize.width {
            return position.x - tooltipWidth - offsetX
        }
        return x
    }

    private func calculateYPosition() -> CGFloat {
        let tooltipHeight: CGFloat = 60
        let offsetY: CGFloat = -10
        let y = position.y + offsetY
        if y - tooltipHeight < 0 {
            return position.y + tooltipHeight + offsetY
        }
        return y
    }
}

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#else
struct VisualEffectView: UIViewRepresentable {
    let effect: UIBlurEffect

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: effect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}
#endif

struct CombinedVoltageChartView: View {
    let allDataPoints: [VoltageDataPoint]
    @Binding var isEcoreVisible: Bool
    @Binding var isPcoreVisible: Bool
    @Binding var isGpuVisible: Bool
    @Binding var isAneVisible: Bool

    private let coreTypeColors: [String: Color] = [
        "E-core": .blue,
        "P-core": .red,
        "GPU": .green,
        "ANE": .yellow
    ]

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
            if !allDataPoints.isEmpty {
                VoltageChart(dataPoints: visibleDataPoints)
                HStack {
                    Toggle("E-core", isOn: $isEcoreVisible)
                        .foregroundColor(isEcoreVisible ? coreTypeColors["E-core"] : .gray)
                    Toggle("P-core", isOn: $isPcoreVisible)
                        .foregroundColor(isPcoreVisible ? coreTypeColors["P-core"] : .gray)
                    Toggle("GPU", isOn: $isGpuVisible)
                        .foregroundColor(isGpuVisible ? coreTypeColors["GPU"] : .gray)
                    Toggle("ANE", isOn: $isAneVisible)
                        .foregroundColor(isAneVisible ? coreTypeColors["ANE"] : .gray)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(outputText, forType: .string)
                        #else
                        UIPasteboard.general.string = outputText
                        #endif
                        isSaving = false
                        isSaveSuccessful = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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

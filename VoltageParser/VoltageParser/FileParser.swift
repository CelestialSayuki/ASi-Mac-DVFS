//
//  FileParser.swift
//  VoltageParser
//
//  Created by Celestial紗雪 on 2025/4/16.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ChipModelMapping: Codable {
    let chipModel: String
    let cpuModel: String
    let isLegacy: Bool
}

struct ParsedFileDetailView: View {
    let fileURL: URL
    @State private var chipModel: String?
    @State private var cpuModel: String = ""
    @State private var isLegacyChip: Bool = false
    @State private var errorMessage: String?
    @State private var allVoltageDataPoints: [VoltageDataPoint] = []
    @State private var isEcoreVisible: Bool = true
    @State private var isPcoreVisible: Bool = true
    @State private var isGpuVisible: Bool = true
    @State private var isAneVisible: Bool = true
    @State private var chipModelMappings: [ChipModelMapping] = []
    @State private var navigationTitleText: String = ""

    private let topPadding: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                if let error = errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                } else if chipModel != nil || !allVoltageDataPoints.isEmpty {
                    VStack {
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .padding(.bottom, 5)

                        if let chip = chipModel, !cpuModel.isEmpty {
                            Text(String(format: NSLocalizedString("parser.cpuModelFormat", comment: "CPU 型号和芯片型号的格式"), cpuModel, chip))
                                .font(.subheadline)
                                .padding(.bottom, 10)
                        } else if !cpuModel.isEmpty {
                            Text("CPU 型号: \(cpuModel)")
                                .font(.subheadline)
                                .padding(.bottom, 10)
                        } else if let chip = chipModel {
                            Text("芯片型号: \(chip)")
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

                        if allVoltageDataPoints.isEmpty && (chipModel != nil || !cpuModel.isEmpty) {
                            Text("未找到电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if chipModel == nil && cpuModel.isEmpty && allVoltageDataPoints.isEmpty {
                            Text("未找到芯片和 CPU 型号信息以及电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if chipModel == nil && !cpuModel.isEmpty && allVoltageDataPoints.isEmpty {
                            Text("未找到芯片型号信息和电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if cpuModel.isEmpty && chipModel != nil && allVoltageDataPoints.isEmpty {
                            Text("未找到 CPU 型号信息和电压数据。")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                } else {
                    Text("未找到芯片和 CPU 型号信息以及电压数据。")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.top, topPadding)
        }
        .navigationTitle(navigationTitleText) // 使用动态的 navigationTitleText
        .onAppear {
            loadChipModelMapping()
            parseFileContent(from: fileURL)
        }
        .onChange(of: cpuModel) { newCPUModel in
            updateNavigationTitle()
        }
        .onChange(of: chipModel) { newChipModel in
            updateNavigationTitle()
        }
    }

    private func updateNavigationTitle() {
        if let chip = chipModel, !cpuModel.isEmpty {
            navigationTitleText = String(format: NSLocalizedString("parser.cpuModelFormat", comment: "CPU 型号和芯片型号的格式"), cpuModel, chip)
        } else if !cpuModel.isEmpty {
            navigationTitleText = cpuModel
        } else if let chip = chipModel {
            navigationTitleText = chip
        } else {
            navigationTitleText = fileURL.lastPathComponent // Fallback to filename if no chip/cpu info
        }
    }

    private func loadChipModelMapping() {
        if let url = Bundle.main.url(forResource: "ChipModelMapping", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                chipModelMappings = try decoder.decode([ChipModelMapping].self, from: data)
            } catch {
                print("Error loading chip model mapping: \(error)")
            }
        } else {
            print("ChipModelMapping.json not found in the bundle.")
        }
    }

    private func getCPUModelAndLegacyStatus(for chip: String?) -> (String, Bool) {
        if let chip = chip {
            if let mapping = chipModelMappings.first(where: { $0.chipModel == chip }) {
                return (mapping.cpuModel, mapping.isLegacy)
            } else {
                return (chip, false) // Default to chip model if no mapping is found
            }
        }
        return ("", false)
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
                (cpuModel, isLegacyChip) = getCPUModelAndLegacyStatus(for: chipModel)
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
                        if let parsedRows = parseHexString(key: key, hexString: hexString, isLegacy: isLegacyChip) {
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

    func parseHexString(key: String, hexString: String, isLegacy: Bool) -> [VoltageDataPoint]? {
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

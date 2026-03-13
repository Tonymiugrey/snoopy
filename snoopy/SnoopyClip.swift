// SnoopyClip.swift

import AVFoundation
import Foundation

class SnoopyClip: NSObject {
    enum ClipType {
        // BP types
        case BP_Node
        case BP_To

        // AP types
        case AP_Intro
        case AP_Loop
        case AP_Outro

        // Transition types
        case CM
        case RPH

        // Fullscreen scenes
        case AS

        // Independent sequences
        case SS_Intro
        case SS_Loop
        case SS_Outro

        // Transition animations
        case ST_Hide
        case ST_Reveal
        case TM_Hide
        case TM_Reveal
        case TM_Hide_Outline
        case TM_Reveal_Outline

        // Random elements
        case VI_Single
        case VI_Intro
        case VI_Loop
        case VI_Outro
        case WE_Single
        case WE_Intro
        case WE_Loop
        case WE_Outro
    }

    // Basic properties
    var type: ClipType
    var fileName: String

    // Node routing
    var from: String?
    var to: String?
    var node: String?

    // Grouping and numbering
    var groupID: String?
    var number: String?
    var variant: String?

    // Playback control
    var repeatCount: Int = 0
    var duration: TimeInterval = 0

    init(type: ClipType, fileName: String) {
        self.type = type
        self.fileName = fileName
        super.init()
        self.configureProperties()
    }

    func configureProperties() {
        // Extract node information
        if let fromRange = fileName.range(of: "_From_") {
            let fromPart = String(fileName[fromRange.upperBound...])
            self.from = String(fromPart.prefix(5))
        }

        if let toRange = fileName.range(of: "_To_") {
            let toPart = String(fileName[toRange.upperBound...])
            self.to = String(toPart.prefix(5))
        }

        // Extract group IDs and numbers
        if let groupMarkerRange = fileName.range(of: "_AP") ?? fileName.range(of: "_WE")
            ?? fileName.range(of: "_VI") ?? fileName.range(of: "_SS")
        {
            let prefixPartString = String(fileName[..<groupMarkerRange.lowerBound])
            let markerPartString = String(fileName[groupMarkerRange])  // e.g., "_SS"
            let remainingAfterMarker = String(fileName[groupMarkerRange.upperBound...])  // e.g., "001_Intro.mov"

            if let numberEndIndexInRemaining = remainingAfterMarker.firstIndex(where: {
                !$0.isNumber
            }) {
                let numberPartString = String(remainingAfterMarker[..<numberEndIndexInRemaining])  // e.g., "001"
                if !numberPartString.isEmpty {
                    self.groupID = prefixPartString + markerPartString + numberPartString  // e.g., "102_SS001"
                    // print("🔧 Set groupID for \(fileName) to \(self.groupID ?? "nil")") // Optional debug
                }
            } else if !remainingAfterMarker.isEmpty
                && remainingAfterMarker.allSatisfy({ $0.isNumber })
            {
                // Handles cases like "101_AP001.mov" (if it ended right after the number)
                let numberPartString = remainingAfterMarker
                self.groupID = prefixPartString + markerPartString + numberPartString
                // print("🔧 Set groupID (all numbers after marker) for \(fileName) to \(self.groupID ?? "nil")") // Optional debug
            }
        }
        // Handle TM clips specially - e.g., "101_TM001_Reveal_Outline"
        else if let tmRange = fileName.range(of: "_TM") {
            let prefixPartString = String(fileName[..<tmRange.lowerBound])  // "101"
            let remainingAfterTM = String(fileName[tmRange.upperBound...])  // "001_Reveal_Outline"

            if let numberEndIndex = remainingAfterTM.firstIndex(where: { !$0.isNumber }) {
                let numberPartString = String(remainingAfterTM[..<numberEndIndex])  // "001"
                if !numberPartString.isEmpty {
                    self.groupID = prefixPartString + "_TM" + numberPartString  // "101_TM001"
                    print("🔧 Set TM groupID for \(fileName) to \(self.groupID ?? "nil")")
                }
            } else if remainingAfterTM.allSatisfy({ $0.isNumber }) {
                // Handle cases where it ends with numbers only
                self.groupID = prefixPartString + "_TM" + remainingAfterTM
                print("🔧 Set TM groupID (all numbers) for \(fileName) to \(self.groupID ?? "nil")")
            }
        }

        if let numberRange = fileName.range(of: "_ST") ?? fileName.range(of: "_TM") {
            let remaining = String(fileName[numberRange.upperBound...])
            if let endIndex = remaining.firstIndex(where: { !$0.isNumber }) {
                self.number = String(remaining[..<endIndex])
            } else if remaining.allSatisfy({ $0.isNumber }) {
                // Handle cases where the string ends with numbers
                self.number = remaining
            }
        }

        // Handle variants
        if fileName.contains("_A.") {
            self.variant = "A"
        } else if fileName.contains("_B.") {
            self.variant = "B"
        }

        // Set repeat counts for loops
        if type == .AP_Loop || type == .VI_Loop || type == .WE_Loop || type == .SS_Loop {
            self.repeatCount = type == .AP_Loop ? Int.random(in: 10...15) : Int.random(in: 5...10)
        } else if type == .BP_Node {
            // Set default repeat count for BP_Node
            self.repeatCount = Int.random(in: 10...20)
        }

        // --- Add Node Property Assignment ---
        if type == .BP_Node {
            // Extract node name like BP001 from 101_BP001.mov
            if let range = fileName.range(of: "_BP") {
                let potentialNode = String(fileName[range.upperBound...].prefix(3))  // Get the 3 digits
                if potentialNode.allSatisfy({ $0.isNumber }) {
                    self.node = "BP" + potentialNode  // Set node to "BP001"
                    print("🔧 Set node for \(fileName) to \(self.node ?? "nil")")  // Debug print
                }
            }
        }
        // --- End Add ---
    }

    static func loadClips() async throws -> [SnoopyClip] {
        guard let resourcePath = Bundle(for: self).resourcePath else { return [] }
        print("🔦 Loading clips from resource path: \\(resourcePath)")

        let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
        var clips: [SnoopyClip] = []
        var tmGroups: [String: [String]] = [:]  // Group TM files by their base pattern

        for file in files {
            let filePath = (resourcePath as NSString).appendingPathComponent(file)
            var isDirectory: ObjCBool = false

            // Check if this is a directory or file
            FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory)
            print("📄 Checking file: \(file), isDirectory: \(isDirectory.boolValue)")  // DEBUG

            if !isDirectory.boolValue {
                print("📄 '\(file)' is a file.")  // DEBUG

                // Handle MOV files (existing logic for non-TM clips)
                if file.hasSuffix(".mov") {
                    guard let url = Bundle(for: self).url(forResource: file, withExtension: nil)
                    else {
                        continue
                    }

                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration)

                    let clipType = determineClipType(for: file)
                    let clip = SnoopyClip(type: clipType, fileName: file)
                    clip.duration = CMTimeGetSeconds(duration)
                    clip.configureProperties()
                    clips.append(clip)
                    print("✅ Loaded MOV clip: \(file)")
                }
                // Handle TM HEIC files - only process files containing "_TM"
                else if file.hasSuffix(".heic") && file.contains("_TM") {
                    print("🎬 Found TM HEIC file: \(file)")

                    // Extract base pattern from filename like "101_TM001_Reveal_Outline_000032.heic"
                    if let basePattern = extractTMBasePattern(from: file) {
                        if tmGroups[basePattern] == nil {
                            tmGroups[basePattern] = []
                        }
                        tmGroups[basePattern]?.append(file)
                        print("  📝 Added to TM group '\(basePattern)': \(file)")
                    } else {
                        print("  ❌ Could not extract base pattern from TM file: \(file)")
                    }
                }
                // Handle IS HEIC files (backgrounds) - only process files containing "_IS"
                else if file.hasSuffix(".heic") && file.contains("_IS") {
                    print("🖼️ Found IS background image: \(file)")
                    // Background images are handled separately
                }
                // Log unrecognized HEIC files
                else if file.hasSuffix(".heic") {
                    print("⚠️ Unrecognized HEIC file (not TM or IS): \(file)")
                }
            } else {
                print("📁 '\(file)' is a directory - skipping.")  // DEBUG
            }
        }

        // Process grouped TM files
        for (basePattern, fileList) in tmGroups {
            print("🎬 Processing TM group: \(basePattern) with \(fileList.count) frames")

            let clipType = determineClipType(for: basePattern + ".heic")
            let clip = SnoopyClip(type: clipType, fileName: basePattern)

            // Calculate duration based on number of frames (assuming 24fps)
            clip.duration = Double(fileList.count) / 24.0
            clip.configureProperties()
            clips.append(clip)

            print(
                "✅ Loaded TM HEIC sequence: \(basePattern) with \(fileList.count) frames (\(clip.duration)s)"
            )
            print(
                "🔍 TM Clip details: type=\(clip.type), number=\(clip.number ?? "nil"), groupID=\(clip.groupID ?? "nil")"
            )
        }

        return clips
    }

    // Helper function to extract base pattern from TM HEIC filenames
    // e.g., "101_TM001_Reveal_Outline_000032.heic" -> "101_TM001_Reveal_Outline"
    private static func extractTMBasePattern(from fileName: String) -> String? {
        let name = fileName.replacingOccurrences(of: ".heic", with: "")

        // 首先检查是否是TM文件
        guard name.contains("_TM") else {
            print("  ⚠️ 不是TM文件: '\(fileName)'")
            return nil
        }

        // 查找类似 "_000032" 的模式（帧号）
        let frameNumberPattern = "_\\d{6}$"
        if let regex = try? NSRegularExpression(pattern: frameNumberPattern, options: []) {
            let range = NSRange(location: 0, length: name.count)
            if let match = regex.firstMatch(in: name, options: [], range: range) {
                let basePattern = String(
                    name[..<name.index(name.startIndex, offsetBy: match.range.location)])
                print("  🎯 从 '\(fileName)' 提取基础模式 '\(basePattern)'")
                return basePattern
            }
        }

        // 尝试第二种模式：如果文件名不包含帧号，但确实是TM文件
        // 例如：可能直接命名为 "101_TM001_Reveal.heic"
        if let tmRange = name.range(of: "_TM") {
            // 查找TM后面的数字部分
            let afterTM = String(name[tmRange.upperBound...])

            if let numberEndIndex = afterTM.firstIndex(where: { !$0.isNumber }) {
                let numberPart = String(afterTM[..<numberEndIndex])

                if !numberPart.isEmpty {
                    // 获取完整的TM标识符：例如"101_TM001"
                    let prefix = String(name[..<tmRange.lowerBound])
                    let basePattern = prefix + "_TM" + numberPart + afterTM[numberEndIndex...]
                    print("  🎯 从不含帧号的TM文件 '\(fileName)' 提取基础模式 '\(basePattern)'")
                    return basePattern
                }
            }
        }

        print("  ❌ 无法从 '\(fileName)' 提取基础模式 - 没有找到有效的模式")
        return nil
    }

    static func determineClipType(for fileName: String) -> ClipType {
        // 首先检查TM HEIC文件的特殊情况
        if fileName.hasSuffix(".heic") && fileName.contains("_TM") {
            if fileName.contains("_Hide_Outline") { return .TM_Hide_Outline }
            if fileName.contains("_Reveal_Outline") { return .TM_Reveal_Outline }
            return fileName.contains("_Hide") ? .TM_Hide : .TM_Reveal
        }

        // 处理基本模式名称 (无扩展名的HEIC基础模式)
        if fileName.contains("_TM") && !fileName.hasSuffix(".mov") {
            if fileName.contains("_Hide_Outline") { return .TM_Hide_Outline }
            if fileName.contains("_Reveal_Outline") { return .TM_Reveal_Outline }
            return fileName.contains("_Hide") ? .TM_Hide : .TM_Reveal
        }

        // 处理其他类型
        if fileName.prefix(9).contains("_BP") {
            return fileName.contains("_To_") ? .BP_To : .BP_Node
        } else if fileName.prefix(9).contains("_AP") {
            if fileName.contains("_Intro") { return .AP_Intro }
            if fileName.contains("_Loop") { return .AP_Loop }
            if fileName.contains("_Outro") { return .AP_Outro }
        } else if fileName.prefix(9).contains("_CM") {
            return .CM
        } else if fileName.prefix(9).contains("_AS") {
            return .AS
        } else if fileName.prefix(9).contains("_SS") {
            if fileName.contains("_Intro") { return .SS_Intro }
            if fileName.contains("_Loop") { return .SS_Loop }
            if fileName.contains("_Outro") { return .SS_Outro }
        } else if fileName.prefix(9).contains("_ST") {
            return fileName.contains("_Hide") ? .ST_Hide : .ST_Reveal
        } else if fileName.prefix(9).contains("_TM") {
            if fileName.contains("_Hide_Outline") { return .TM_Hide_Outline }
            if fileName.contains("_Reveal_Outline") { return .TM_Reveal_Outline }
            return fileName.contains("_Hide") ? .TM_Hide : .TM_Reveal
        } else if fileName.prefix(9).contains("_VI") {
            if fileName.contains("_Intro") { return .VI_Intro }
            if fileName.contains("_Loop") { return .VI_Loop }
            if fileName.contains("_Outro") { return .VI_Outro }
            return .VI_Single
        } else if fileName.prefix(9).contains("_WE") {
            if fileName.contains("_Intro") { return .WE_Intro }
            if fileName.contains("_Loop") { return .WE_Loop }
            if fileName.contains("_Outro") { return .WE_Outro }
            return .WE_Single
        } else if fileName.prefix(9).contains("_RPH") {
            return .RPH
        }

        fatalError("Unknown clip type for file: \(fileName)")
    }

    static func generatePlaySequence(currentNode: String, clips: [SnoopyClip]) -> [String] {
        let transitions = getAvailableTransitions(from: currentNode, clips: clips)

        // --- 修改点：从 BP 节点出发时不随机选择 RPH ---
        // Weighted random selection EXCLUDING RPH for BP continuation
        let nextType = weightedRandomSelection(
            options: [
                (type: "BP_To", weight: 0.3),
                (type: "AP", weight: 0.2),
                (type: "CM", weight: 0.5),
                // (type: "RPH", weight: 0.2)
            ]
        )
        // --- 结束修改 ---

        var sequence: [String] = []  // Initialize sequence

        switch nextType {
        case "BP_To":
            if let transition = transitions.bpTo.randomElement() {  // Use if let for safety
                sequence = [transition.fileName]
            }

        case "AP":
            if let apIntro = transitions.apIntro.randomElement(),
                let apLoop = clips.first(where: {
                    $0.groupID == apIntro.groupID && $0.type == .AP_Loop
                }),
                let apOutro = clips.first(where: {
                    $0.groupID == apIntro.groupID && $0.type == .AP_Outro
                })
            {
                // --- 修改点：只添加一次 AP_Loop ---
                sequence = [apIntro.fileName, apLoop.fileName, apOutro.fileName]
                // --- 结束修改 ---
                print(
                    "✅ 生成 AP 序列: Intro=\(apIntro.fileName), Loop=\(apLoop.fileName), Outro=\(apOutro.fileName)"
                )  // 添加日志
            } else {
                print(
                    "⚠️ 无法为 AP 序列找到完整的 Intro/Loop/Outro (GroupID: \(transitions.apIntro.first?.groupID ?? "未知"))"
                )
                // Fallback logic will handle empty sequence
            }

        case "CM":
            if let cm = transitions.cm.randomElement() {  // Use if let for safety
                sequence = [cm.fileName]
            }

        default:
            break  // Should not happen with current weights
        }

        // Fallback logic: If no transition was selected/found, pick a random BP_Node
        if sequence.isEmpty {
            let allBpNodes = clips.filter { $0.type == .BP_Node }
            if let randomBpNode = allBpNodes.randomElement() {
                print(
                    "Fallback: No specific transition found from \(currentNode). Playing random BP_Node: \(randomBpNode.fileName)"
                )
                sequence = [randomBpNode.fileName]  // Play the BP_Node itself
            } else {
                print("Error: Fallback failed. No BP_Node clips found.")
                // Handle this case appropriately, maybe return a default sequence or error
            }
        }

        return sequence
    }

    // Update the return tuple to include RPH clips
    static func getAvailableTransitions(from currentNode: String, clips: [SnoopyClip]) -> (
        bpTo: [SnoopyClip], apIntro: [SnoopyClip], cm: [SnoopyClip]
    ) {
        let bpTo = clips.filter { clip in
            if clip.type == .BP_To {
                // TODO: 将正则表达式简化为其他地方所使用的方式
                let regex = try! NSRegularExpression(pattern: "_BP(\\d{3})_To_")
                if let match = regex.firstMatch(
                    in: clip.fileName, options: [],
                    range: NSRange(location: 0, length: clip.fileName.utf16.count))
                {
                    if let range = Range(match.range(at: 1), in: clip.fileName) {
                        let nodeNumber = String(clip.fileName[range])
                        if ("BP" + nodeNumber) == currentNode {
                            return true
                        }
                    }
                }
                return false
            }
            return false
        }
        // --- 结束修改 ---

        let apIntro = clips.filter { $0.type == .AP_Intro && $0.from == currentNode }
        let cm = clips.filter { $0.type == .CM && $0.from == currentNode }

        // --- 添加日志 ---
        print("🔍 getAvailableTransitions(from: \(currentNode))")
        print("  Found BP_To: \(bpTo.map { $0.fileName })")
        print("  Found AP_Intro: \(apIntro.map { $0.fileName })")
        print("  Found CM: \(cm.map { $0.fileName })")
        // --- 结束添加 ---

        return (bpTo, apIntro, cm)  // Return RPH clips as well
    }

    static func weightedRandomSelection(options: [(type: String, weight: Double)]) -> String {
        let totalWeight = options.reduce(0) { $0 + $1.weight }
        let randomValue = Double.random(in: 0..<totalWeight)

        var cumulativeWeight = 0.0
        for option in options {
            cumulativeWeight += option.weight
            if randomValue < cumulativeWeight {
                return option.type
            }
        }

        return options.last?.type ?? ""
    }
}

// String extension for path handling
extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}

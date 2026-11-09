import AVFoundation
import AppKit
import Darwin
import Combine
import Foundation

// Darwin 的 struct flock 与 C 函数同名，显式声明其稳定的 C ABI。
@_silgen_name("flock")
private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

// MARK: - 语音播报配置与章节模型

struct TTSConfig: Codable {
    var enabled: Bool?
    var time: String?
    var rate: Int?
    var voice: String?

    var isEnabled: Bool { enabled ?? true }
    var scheduledTime: String {
        let value = (time ?? "").trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "09:10" : value
    }
    var speechRate: Int { rate ?? 200 }
    var speechVoice: String {
        let value = (voice ?? "").trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "Tingting" : value
    }
}

struct TTSChapter: Codable, Identifiable, Equatable {
    let title: String
    let start: Double

    var id: String { "\(title)-\(start)" }

    var startFormatted: String {
        let total = max(0, Int(start.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct TTSRootConfig: Codable {
    var tts: TTSConfig?
}

private struct TTSMetadata: Codable {
    let duration: Double?
    let chars: Int?
    let voice: String?
}

// MARK: - 播放器（AVAudioPlayer 预渲染音频 + 章节刻度 + 记住播放位置 + 定时自动播报）

final class TTSPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var hasAudio: Bool = false
    @Published private(set) var voiceMissing: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var rate: Double = 1.0
    @Published private(set) var autoPlayEnabled: Bool = true
    @Published private(set) var autoPlayTime: String = "09:10"
    @Published private(set) var voiceCode: String = "Tingting"
    @Published private(set) var voiceName: String = "未知音色"
    @Published private(set) var previewingVoice: String?
    @Published private(set) var isGeneratingVoice = false
    @Published private(set) var voiceStatus: String?
    @Published private(set) var chapters: [TTSChapter] = []
    @Published private(set) var scriptText: String = ""
    @Published private(set) var hasSavedPosition: Bool = false
    @Published var showChaptersDrawer: Bool = false
    @Published var showTranscript: Bool = false
    @Published var scrubbingFraction: Double? = nil

    private let fileManager = FileManager.default
    private let baseRoot: URL
    private let dataDirectory: URL
    private var player: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var voiceProcess: Process?
    private var generationDate: String?
    private var progressTimer: Timer?
    private var autoTimer: Timer?
    private var loadedDate: String = ""
    private var loadedGeneration: String = ""
    private var loadedAssets: String = ""
    private var playbackLock: Int32 = -1
    private var observers: [NSObjectProtocol] = []

    private static let savedDurationPrefix = "dailydigest.tts.savedDuration."
    private static let savedPositionPrefix = "dailydigest.tts.savedPosition."

    static let voices: [(id: String, label: String)] = [
        ("zh-CN-YunyangNeural", "云扬 · 男声"),
        ("zh-CN-YunxiNeural", "云希 · 男声"),
        ("zh-CN-XiaoxiaoNeural", "晓晓 · 女声"),
        ("zh-CN-XiaoyiNeural", "晓伊 · 女声"),
    ]

    static let speeds: [(label: String, value: Double)] = [
        ("0.9x", 0.9),
        ("1.0x", 1.0),
        ("1.25x", 1.25),
        ("1.5x", 1.5),
    ]

    override init() {
        let envRoot = ProcessInfo.processInfo.environment["DIGEST_DATA_ROOT"]
        if let envRoot, !envRoot.isEmpty {
            baseRoot = URL(fileURLWithPath: envRoot, isDirectory: true)
        } else {
            baseRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DailyDigest", isDirectory: true)
        }
        dataDirectory = baseRoot.appendingPathComponent("data", isDirectory: true)
        super.init()
        reloadConfig()
        load(date: Self.today())
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveCurrentPosition()
            UserDefaults.standard.synchronize()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAvailability()
            self?.checkAutoPlay()
        })
        startAutoPlayMonitor()
    }

    deinit {
        saveCurrentPosition()
        previewPlayer?.stop()
        progressTimer?.invalidate()
        autoTimer?.invalidate()
        releasePlaybackLock()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: 路径

    var ttsDirectory: URL {
        dataDirectory.appendingPathComponent("tts", isDirectory: true)
    }

    var configURL: URL {
        baseRoot.appendingPathComponent("config.json")
    }

    func audioURL(for date: String) -> URL {
        ttsDirectory.appendingPathComponent("brief-\(date).aiff")
    }

    func textURL(for date: String) -> URL {
        ttsDirectory.appendingPathComponent("brief-\(date).txt")
    }

    func chaptersURL(for date: String) -> URL {
        ttsDirectory.appendingPathComponent("brief-\(date).chapters.json")
    }

    // MARK: 载入

    func load(date: String, generation: String = "") {
        guard !date.isEmpty else { return }
        if date != loadedDate { stopPreview() }
        // 合成期间不读取正在替换的一组文件。
        if isGeneratingVoice && date == generationDate {
            if date != loadedDate {
                saveCurrentPosition()
                stopPlayback(reset: false)
                player = nil
                loadedDate = date
                loadedGeneration = generation
                loadedAssets = ""
                hasAudio = false
                currentTime = 0
                duration = 0
                chapters = []
                scriptText = ""
                voiceName = "未知音色"
            }
            return
        }
        let assets = assetSignature(for: date)
        if date == loadedDate, assets == loadedAssets, player != nil {
            loadedGeneration = generation
            return
        }
        // 同一天增量更新先写 JSON、后写音频；播放期间继续当前音频，暂停后再换新文件。
        if date == loadedDate, isPlaying { return }
        stopPreview()
        saveCurrentPosition()
        stopPlayback(reset: false)
        player = nil
        loadedDate = date
        loadedGeneration = generation
        loadedAssets = assets
        loadError = nil
        currentTime = 0
        duration = 0
        chapters = []
        voiceName = "未知音色"
        hasSavedPosition = false
        reloadConfig()
        scriptText = ((try? String(contentsOf: textURL(for: date), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let audio = audioURL(for: date)
        hasAudio = fileManager.fileExists(atPath: audio.path)
        guard hasAudio else {
            voiceMissing = !voiceCode.hasPrefix("zh-CN-") && !Self.hasChineseVoice()
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: audio)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = Float(rate)
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            voiceMissing = false
            if let voice = metadata(for: date)?.voice {
                voiceName = Self.voiceLabel(voice)
            }
            chapters = loadChapters(for: date)
            let saved = savedPosition(for: date)
            let oldDuration = UserDefaults.standard.double(forKey: Self.savedDurationPrefix + date)
            // 大幅改版（例如两分钟稿升级为完整节目）不把旧位置错套到新内容。
            let comparable = oldDuration <= 0 || abs(oldDuration - duration) <= max(5, duration * 0.1)
            if comparable, saved > 0, saved < max(0, duration - 0.5) {
                newPlayer.currentTime = min(saved, duration)
                currentTime = newPlayer.currentTime
                hasSavedPosition = true
            }
        } catch {
            player = nil
            hasAudio = false
            loadError = "音频无法播放：\(error.localizedDescription)"
            voiceMissing = !voiceCode.hasPrefix("zh-CN-") && !Self.hasChineseVoice()
        }
    }

    /// 以音频和章节文件的修改时间、大小判断；日报 JSON 更新不代表音频已渲染完。
    func reloadIfNeeded(date: String, generation: String) {
        load(date: date, generation: generation)
    }

    private func assetSignature(for date: String) -> String {
        [audioURL(for: date), chaptersURL(for: date), textURL(for: date)].map { url in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return "missing" }
            let stamp = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(stamp):\(attributes[.size] ?? 0)"
        }.joined(separator: "|")
    }

    // MARK: 播放控制

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        startPlayback(refresh: true)
    }

    private func startPlayback(refresh: Bool) {
        stopPreview()
        guard !isGeneratingVoice else { return }
        if refresh, !isPlaying { refreshAvailability() }
        guard let player else {
            loadError = hasAudio ? "音频还没有准备好" : "今天还没有生成播报音频"
            return
        }
        if player.currentTime >= max(0, player.duration - 0.5) {
            player.currentTime = 0
            currentTime = 0
            clearSavedPosition(for: loadedDate)
        }
        guard acquirePlaybackLock() else {
            loadError = "已有一段日报正在播放，请等待或先暂停另一处播报。"
            return
        }
        player.enableRate = true
        player.rate = Float(rate)
        guard player.play() else {
            releasePlaybackLock()
            loadError = "无法开始播放，请稍后再试"
            return
        }
        isPlaying = true
        loadError = nil
        startProgressTimer()
    }

    func restartFromBeginning() {
        guard let player else { return }
        player.currentTime = 0
        currentTime = 0
        hasSavedPosition = false
        clearSavedPosition(for: loadedDate)
        if !isPlaying {
            play()
        }
    }

    func jumpToChapter(_ chapter: TTSChapter) {
        guard let player, duration > 0 else { return }
        let target = min(max(chapter.start, 0), max(0, duration - 0.5))
        player.currentTime = target
        currentTime = target
        saveCurrentPosition()
        if !isPlaying {
            play()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        updateProgress()
        saveCurrentPosition()
        releasePlaybackLock()
        refreshAvailability()
    }

    func stopPlayback(reset: Bool) {
        player?.stop()
        releasePlaybackLock()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        if reset {
            player?.currentTime = 0
            currentTime = 0
        }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        guard fraction.isFinite else { return }
        let clamped = min(max(fraction, 0), 1)
        let time = player.duration * clamped
        player.currentTime = time
        currentTime = time
        hasSavedPosition = time > 3.0
        saveCurrentPosition()
    }

    func skip(by deltaSeconds: Double) {
        guard duration > 0 else { return }
        let target = min(max(currentTime + deltaSeconds, 0), duration)
        seek(to: target / duration)
    }

    func setRate(_ value: Double) {
        guard Self.speeds.contains(where: { abs($0.value - value) < 0.001 }) else { return }
        rate = value
        if let player {
            player.enableRate = true
            player.rate = Float(value)
        }
    }

    // MARK: 章节计算与拖动位置提示

    var activeChapter: TTSChapter? {
        chapter(at: currentTime)
    }

    func chapter(at seconds: TimeInterval) -> TTSChapter? {
        guard !chapters.isEmpty else { return nil }
        var matched = chapters.first
        for ch in chapters {
            if seconds + 0.3 >= ch.start {
                matched = ch
            } else {
                break
            }
        }
        return matched
    }

    func scrubLabel(for fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        let sec = duration * clamped
        let timeStr = Self.format(sec)
        if let ch = chapter(at: sec) {
            return "\(ch.title) \(timeStr)"
        }
        return timeStr
    }

    // MARK: 记忆播放位置

    private func savedPosition(for date: String) -> Double {
        guard !date.isEmpty else { return 0 }
        return UserDefaults.standard.double(forKey: Self.savedPositionPrefix + date)
    }

    func saveCurrentPosition() {
        guard !loadedDate.isEmpty, duration > 0 else { return }
        if currentTime > 0, currentTime < duration - 0.5 {
            UserDefaults.standard.set(currentTime, forKey: Self.savedPositionPrefix + loadedDate)
            UserDefaults.standard.set(duration, forKey: Self.savedDurationPrefix + loadedDate)
            hasSavedPosition = true
        } else {
            clearSavedPosition(for: loadedDate)
        }
    }

    private func clearSavedPosition(for date: String) {
        guard !date.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: Self.savedPositionPrefix + date)
        UserDefaults.standard.removeObject(forKey: Self.savedDurationPrefix + date)
        hasSavedPosition = false
    }

    func refreshAvailability() {
        guard !loadedDate.isEmpty, !isPlaying, !isGeneratingVoice else { return }
        load(date: loadedDate, generation: loadedGeneration)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var durationLabel: String {
        if duration > 0 {
            return "约 \(max(1, Int((duration / 60).rounded()))) 分钟"
        }
        return "约 12 分钟"
    }

    var timeLabel: String {
        "\(Self.format(currentTime)) / \(Self.format(duration))"
    }

    // MARK: 自动播放与配置

    @discardableResult
    func saveScheduledPlayback(enabled: Bool, time: String) -> Bool {
        guard time.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else {
            loadError = "请选择有效的播放时间。"
            return false
        }
        do {
            var payload: [String: Any] = [:]
            if fileManager.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["tts"] == nil || object["tts"] is [String: Any] else {
                    throw CocoaError(.coderReadCorrupt)
                }
                payload = object
            }
            var tts = payload["tts"] as? [String: Any] ?? [:]
            tts["enabled"] = enabled
            tts["time"] = time
            payload["tts"] = tts
            let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: configURL, options: .atomic)
            autoPlayEnabled = enabled
            autoPlayTime = time
            loadError = nil
            return true
        } catch {
            loadError = "保存定时设置失败，请检查配置文件。"
            return false
        }
    }

    func reloadConfig() {
        let configError = "自动播报配置不可用，请检查 config.json；手动播放仍可使用。"
        if !fileManager.fileExists(atPath: configURL.path) {
            autoPlayEnabled = true
            autoPlayTime = "09:10"
            voiceCode = "Tingting"
            if loadError == configError { loadError = nil }
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            if let rawTTS = payload["tts"] {
                guard let fields = rawTTS as? [String: Any],
                      !["enabled", "time", "rate", "voice"].contains(where: { fields[$0] is NSNull }) else {
                    throw CocoaError(.coderReadCorrupt)
                }
            }
            let config = try JSONDecoder().decode(TTSRootConfig.self, from: data)
            let tts = config.tts ?? TTSConfig()
            let time = tts.time ?? "09:10"
            guard time.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil,
                  (80...350).contains(tts.speechRate),
                  !(tts.voice ?? "Tingting").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CocoaError(.coderReadCorrupt)
            }
            autoPlayEnabled = tts.isEnabled
            autoPlayTime = time
            voiceCode = tts.speechVoice
            if loadError == configError { loadError = nil }
        } catch {
            // 损坏或写入中的配置不能意外打开声音；修好后下次轮询自动恢复。
            autoPlayEnabled = false
            loadError = configError
        }
    }

    private func startAutoPlayMonitor() {
        autoTimer?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshAvailability()
            self?.checkAutoPlay()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
        checkAutoPlay()
    }

    private func checkAutoPlay() {
        reloadConfig()
        guard autoPlayEnabled, !isGeneratingVoice, previewingVoice == nil else { return }
        let parts = autoPlayTime.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return }
        let now = Date()
        let calendar = Calendar.current
        guard let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return }
        let delay = now.timeIntervalSince(scheduled)
        guard delay >= 0, delay < 1800 else { return }
        let today = Self.today()
        let marker = ttsDirectory.appendingPathComponent(".spoken-\(today)")
        let previous = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard previous != autoPlayTime else { return }
        // 用户正听历史节目时不抢播；仍在补播窗口内，下次轮询再尝试。
        if isPlaying {
            if loadedDate == today {
                try? (autoPlayTime + "\n").write(to: marker, atomically: true, encoding: .utf8)
            }
            return
        }
        load(date: today)
        guard hasAudio, acquirePlaybackLock() else { return }
        // 在取得共享锁后再查一次，关闭与 LaunchAgent 交接时的检查/播放竞态。
        let underLock = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard underLock != autoPlayTime else {
            releasePlaybackLock()
            return
        }
        startPlayback(refresh: false)
        if isPlaying {
            try? (autoPlayTime + "\n").write(to: marker, atomically: true, encoding: .utf8)
        } else {
            releasePlaybackLock()
        }
    }

    // 试听和正文使用同一把跨进程锁，不能与定时播报或 afplay 重叠。
    func previewVoice(_ voice: String) {
        guard Self.voices.contains(where: { $0.id == voice }) else { return }
        if previewingVoice == voice { stopPreview(); return }
        stopPreview()
        if isPlaying { pause() }
        guard let url = Bundle.main.url(forResource: voice, withExtension: "mp3", subdirectory: "VoicePreviews") else {
            loadError = "找不到试听音频，请重新安装应用。"
            return
        }
        guard acquirePlaybackLock() else {
            loadError = "已有一段日报正在播放，请等待或先暂停另一处播报。"
            return
        }
        do {
            let audition = try AVAudioPlayer(contentsOf: url)
            audition.delegate = self
            previewPlayer = audition
            guard audition.play() else { throw CocoaError(.fileReadUnknown) }
            previewingVoice = voice
            loadError = nil
        } catch {
            previewPlayer = nil
            releasePlaybackLock()
            loadError = "试听失败：\(error.localizedDescription)"
        }
    }

    func stopPreview() {
        guard previewPlayer != nil else { return }
        previewPlayer?.stop()
        previewPlayer = nil
        previewingVoice = nil
        releasePlaybackLock()
    }

    func selectVoice(_ voice: String, date: String) {
        guard !isGeneratingVoice, Self.voices.contains(where: { $0.id == voice }),
              date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return }
        stopPreview()
        if isPlaying { pause() }
        do {
            var payload: [String: Any] = [:]
            if fileManager.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["tts"] == nil || object["tts"] is [String: Any] else {
                    throw CocoaError(.coderReadCorrupt)
                }
                payload = object
            }
            var tts = payload["tts"] as? [String: Any] ?? [:]
            tts["engine"] = "edge"
            tts["voice"] = voice
            payload["tts"] = tts
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
        } catch {
            voiceStatus = "保存音色设置失败：\(error.localizedDescription)"
            return
        }
        voiceCode = voice
        isGeneratingVoice = true
        generationDate = date
        voiceStatus = "正在为 \(date) 重新生成播报，原音频会保留至生成成功。"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["/Users/c/Developer/DailyDigest/backend/tts_brief.py", "--date", date, "--no-ai"]
        process.environment = ProcessInfo.processInfo.environment
        // 输出只用于提取错误类型，不展示播报正文。
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("digest-voice-\(UUID().uuidString).log")
        _ = fileManager.createFile(atPath: outputURL.path, contents: nil)
        let output = try? FileHandle(forWritingTo: outputURL)
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            try? output?.close()
            let raw = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: outputURL)
            let result = raw.split(separator: "\n").reversed().compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }.first
            let detail = (result?["error"] as? String ?? "").lowercased()
            DispatchQueue.main.async {
                guard let self else { return }
                self.voiceProcess = nil
                self.isGeneratingVoice = false
                self.generationDate = nil
                if finished.terminationStatus == 0, self.metadata(for: date)?.voice == voice,
                   self.fileManager.fileExists(atPath: self.audioURL(for: date).path) {
                    self.voiceStatus = "\(date) 播报已更新为\(Self.voiceLabel(voice))。"
                    if self.loadedDate == date { self.load(date: date, generation: self.loadedGeneration) }
                } else {
                    let reason: String
                    if detail.contains("正在生成") {
                        reason = "当天播报正在更新，请稍后重试"
                    } else if detail.contains("分钟") || detail.contains("时长") {
                        reason = "节目时长不符合要求，请调整内容后重试"
                    } else if ["network", "connection", "timeout", "timed out", "websocket", "dns", "网络"].contains(where: { detail.contains($0) }) {
                        reason = "网络连接或在线语音服务不可用，请检查网络后重试"
                    } else {
                        reason = "语音服务或生成过程出错，请稍后重试"
                    }
                    self.voiceStatus = "\(date) 播报生成失败：\(reason)。原音频保留，所选音色已保存。"
                    if self.loadedDate == date { self.load(date: date, generation: self.loadedGeneration) }
                }
            }
        }
        do {
            try process.run()
            voiceProcess = process
        } catch {
            try? output?.close()
            try? fileManager.removeItem(at: outputURL)
            isGeneratingVoice = false
            generationDate = nil
            voiceStatus = "无法启动播报生成：\(error.localizedDescription)；原音频保留。"
        }
    }

    // 与 speak_brief.py 共用系统 flock；进程退出自动释放，避免残留锁和双播。
    private func acquirePlaybackLock() -> Bool {
        if playbackLock >= 0 { return true }
        do { try fileManager.createDirectory(at: ttsDirectory, withIntermediateDirectories: true) }
        catch { return false }
        let fd = Darwin.open(ttsDirectory.appendingPathComponent(".playback.lock").path,
                             O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return false }
        guard systemFlock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            return false
        }
        playbackLock = fd
        return true
    }

    private func releasePlaybackLock() {
        guard playbackLock >= 0 else { return }
        _ = systemFlock(playbackLock, LOCK_UN)
        Darwin.close(playbackLock)
        playbackLock = -1
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func voiceLabel(_ voice: String) -> String {
        [
            "Tingting": "婷婷",
            "Meijia": "美佳",
            "Sinji": "善怡",
            "zh-CN-YunyangNeural": "云扬自然男声",
            "zh-CN-YunxiNeural": "云希自然男声",
            "zh-CN-YunjianNeural": "云健自然男声",
            "zh-CN-XiaoxiaoNeural": "晓晓自然女声",
            "zh-CN-XiaoyiNeural": "晓伊自然女声",
        ][voice] ?? voice
    }

    // MARK: 定时器与代理

    private func startProgressTimer() {
        progressTimer?.invalidate()
        var tickCount = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateProgress()
            tickCount += 1
            if tickCount % 8 == 0 {
                self.saveCurrentPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func updateProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        if duration <= 0 { duration = player.duration }
        if !player.isPlaying && isPlaying {
            isPlaying = false
            progressTimer?.invalidate()
            progressTimer = nil
            releasePlaybackLock()
            saveCurrentPosition()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            if player === self.previewPlayer { self.stopPreview(); return }
            guard player === self.player else { return }
            self.isPlaying = false
            self.releasePlaybackLock()
            self.currentTime = player.duration
            self.clearSavedPosition(for: self.loadedDate)
            self.progressTimer?.invalidate()
            self.progressTimer = nil
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            if player === self.previewPlayer {
                self.stopPreview()
                self.loadError = error?.localizedDescription ?? "试听音频解码失败"
                return
            }
            guard player === self.player else { return }
            self.isPlaying = false
            self.releasePlaybackLock()
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            self.saveCurrentPosition()
            self.loadError = error?.localizedDescription ?? "音频解码失败"
        }
    }

    // MARK: 工具

    private func loadChapters(for date: String) -> [TTSChapter] {
        let url = chaptersURL(for: date)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TTSChapter].self, from: data) else {
            return []
        }
        guard decoded.count >= 2, duration > 0 else { return [] }
        var last: Double = -1
        for chapter in decoded {
            guard !chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  chapter.start.isFinite, chapter.start >= 0, chapter.start < duration,
                  chapter.start > last else { return [] }
            last = chapter.start
        }
        return decoded
    }

    private func metadata(for date: String) -> TTSMetadata? {
        let url = ttsDirectory.appendingPathComponent("brief-\(date).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TTSMetadata.self, from: data)
    }

    private static func hasChineseVoice() -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { voice in
            voice.language.hasPrefix("zh")
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

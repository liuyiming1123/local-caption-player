import SwiftUI
import AVKit
import Speech
import ScreenCaptureKit
import CoreMedia
import UniformTypeIdentifiers

@MainActor final class PlayerModel: ObservableObject {
    @Published var caption = ""
    @Published var status = "打开视频后自动启动字幕"
    @Published var language = "zh-CN"
    @Published var fileName = "未打开视频"
    let player = AVPlayer()
    @Published var showTranscript = false
    @Published var showEndPrompt = false
    @Published var transcriptText = ""
    private var transcript: TranscriptStore?
    private var mediaURL: URL?
    private var originalTask: Task<Void, Never>?
    private var timeline = SubtitleTimeline()
    private var useOriginalAudio = false
    @Published var preparedUntil: Double = 0
    private var originalFinished = false
    private var lastOriginalSave = Date.distantPast
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var endShown = false
    private var transcriptWriteError: String?
    private let backupDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("实时字幕播放器/转录备份", isDirectory: true)

    private func syncOriginalTranscript() -> Bool {
        guard useOriginalAudio, !timeline.cues.isEmpty else { return true }
        do { try transcript?.update(timeline.cues.map(\.text).joined(separator: "\n")); lastOriginalSave = Date(); return true }
        catch { transcriptWriteError = error.localizedDescription; status = "字幕备份失败：\(error.localizedDescription)"; return false }
    }
    func exportTranscript() {
        guard syncOriginalTranscript() else { return }
        guard let transcript, transcript.hasText else { status = "目前还没有可保存的字幕"; return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("播放器字幕", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = (fileName as NSString).deletingPathExtension
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("\(name)-\(stamp)-\(UUID().uuidString.prefix(4)).txt")
            try transcript.document.write(to: url, atomically: true, encoding: .utf8)
            status = "已保存到文稿/播放器字幕：\(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { status = "保存失败：\(error.localizedDescription)" }
    }
    func previewTranscript() {
        guard syncOriginalTranscript() else { return }
        guard let transcript, transcript.hasText else { status = "目前还没有识别到字幕"; return }
        transcriptText = transcript.document; showTranscript = true
    }
    private var stream: SCStream?
    private var output: AudioOutput?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()

    func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }
    func startOriginalAudio() {
        guard let url = mediaURL else { status = "请先打开视频"; return }
        stop(); useOriginalAudio = true; timeline = SubtitleTimeline(); preparedUntil = 0; originalFinished = false; lastOriginalSave = .distantPast
        transcript = TranscriptStore(directory: backupDirectory, videoName: fileName + "（原音预识别）")
        let id = generation; let locale = language
        status = "正在从原始音轨提前生成字幕…"
        originalTask = Task { [weak self] in
            do {
                try await OriginalAudioTranscriber.run(url: url, localeID: locale) { cue in
                    await MainActor.run {
                        guard let self, self.generation == id else { return }
                        self.timeline.cues.append(cue)
                        self.timeline.cues.sort { $0.start < $1.start }
                        self.preparedUntil = max(self.preparedUntil, cue.end)
                        if Date().timeIntervalSince(self.lastOriginalSave) >= 3 {
                            do { try self.transcript?.update(self.timeline.cues.map(\.text).joined(separator: "\n")); self.lastOriginalSave = Date() }
                            catch { self.transcriptWriteError = error.localizedDescription }
                        }
                        if let error = self.transcriptWriteError { self.status = "字幕备份失败：\(error)" }
                        else { self.status = "原音识别中，已生成至 \(Int(self.preparedUntil / 60))分\(Int(self.preparedUntil) % 60)秒" }
                    }
                }
                guard let self, self.generation == id else { return }
                do { try self.transcript?.update(self.timeline.cues.map(\.text).joined(separator: "\n")) }
                catch { self.transcriptWriteError = error.localizedDescription }
                self.originalFinished = true
                self.status = self.transcriptWriteError.map { "字幕备份失败：\($0)" } ?? "原音识别完成；字幕跟随播放进度"
            } catch {
                guard let self, self.generation == id else { return }
                self.status = "原音识别失败：\(error.localizedDescription)，可使用实时识别"
            }
        }
    }
    func load(_ url: URL) {
        guard MediaOpenPolicy.accepts(url) else { status = "无法打开此文件：请选择支持的视频或音频"; return }
        stop()
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = timeObserver { player.removeTimeObserver(observer); timeObserver = nil }
        endShown = false
        mediaURL = url
        fileName = url.lastPathComponent
        transcript = TranscriptStore(directory: backupDirectory, videoName: fileName)
        transcriptWriteError = nil
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.player.currentItem === item, self.transcript?.hasText == true else { return }
                guard !self.endShown else { return }
                self.endShown = true; self.showEndPrompt = true
            }
        }
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak item] time in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item else { return }
                if self.useOriginalAudio {
                    self.caption = CaptionFormatter().latest(self.timeline.text(at: time.seconds))
                    if !self.originalFinished && time.seconds > self.preparedUntil + 1 && self.transcriptWriteError == nil { self.status = "正在准备当前位置的字幕，请稍候" }
                }
                guard !self.endShown,
                      item.duration.seconds.isFinite, item.duration.seconds > 0,
                      time.seconds >= item.duration.seconds - 0.15,
                      self.transcript?.hasText == true else { return }
                self.endShown = true; self.showEndPrompt = true
            }
        }
        player.play()
        startOriginalAudio()
    }
    func stop() {
        if useOriginalAudio, !timeline.cues.isEmpty {
            do { try transcript?.update(timeline.cues.map(\.text).joined(separator: "\n")) }
            catch { transcriptWriteError = error.localizedDescription }
        }
        if let transcript, transcript.hasText {
            do { try transcript.finishSegment() } catch { transcriptWriteError = error.localizedDescription }
        }
        generation = UUID(); originalTask?.cancel(); originalTask = nil; useOriginalAudio = false
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil; output = nil; caption = ""
    }
    func start() async {
        let wasOriginal = useOriginalAudio
        stop()
        if wasOriginal { transcript = TranscriptStore(directory: backupDirectory, videoName: fileName + "（实时识别）") }
        let id = generation
        status = "正在申请语音识别权限…"
        let auth = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard id == generation else { return }
        guard auth == .authorized else { status = "请在系统设置中允许语音识别"; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status = "该语言的本机识别不可用，请检查系统语言模型"; return
        }
        let req = SFSpeechAudioBufferRecognitionRequest(); req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true; req.addsPunctuation = true
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.caption = CaptionFormatter().latest(text)
                    do { try self.transcript?.update(text) } catch { self.transcriptWriteError = error.localizedDescription }
                    self.status = self.transcriptWriteError.map { "字幕备份失败：\($0)" } ?? "本机实时识别中"
                }
                if let error { self.status = "识别中断：\(error.localizedDescription)；可点击重新启动字幕" }
            }
        }
        do {
            status = "正在申请屏幕与音频捕获权限…"
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard id == generation else { return }
            guard let display = content.displays.first, let app = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else { status = "未找到播放器窗口，请重新启动字幕"; return }
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            let config = SCStreamConfiguration(); config.capturesAudio = true; config.excludesCurrentProcessAudio = false; config.sampleRate = 16000; config.channelCount = 1; config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let out = AudioOutput(request: req); let s = SCStream(filter: filter, configuration: config, delegate: nil)
            try s.addStreamOutput(out, type: .audio, sampleHandlerQueue: DispatchQueue(label: "caption.audio"))
            output = out; stream = s; try await s.startCapture()
            guard id == generation else { try? await s.stopCapture(); return }
            status = "正在监听播放器声音（本机识别）"
        } catch { status = "音频捕获失败：\(error.localizedDescription)。请检查屏幕与系统音频录制权限" }
    }
}

// Buffer conversion adapted from SubtitleOverlay, copyright SweelLong, MIT license.
final class AudioOutput: NSObject, SCStreamOutput {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let desc = CMSampleBufferGetFormatDescription(sampleBuffer), CMAudioFormatDescriptionGetStreamBasicDescription(desc) != nil else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        pcm.frameLength = frames
        var ptr: UnsafeMutablePointer<Int8>?; var size = 0
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &size, dataPointerOut: &ptr) == noErr, let ptr else { return }
        let destination = pcm.mutableAudioBufferList.pointee.mBuffers
        guard let data = destination.mData else { return }
        memcpy(data, ptr, min(size, Int(destination.mDataByteSize))); request.append(pcm)
    }
}

struct ContentView: View {
    @StateObject var model = PlayerModel()
    private var hasVideo: Bool { model.fileName != "未打开视频" }
    @State private var controlsVisible = true
    @State private var isPlaying = false
    @State private var hoveringControls = false
    @State private var activity = UUID()
    private let visibilityPolicy = ControlsVisibilityPolicy(delay: 3)
    private func showControls() {
        if !controlsVisible { withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true } }
        activity = UUID()
    }
    var body: some View {
        GeometryReader { layout in
        ZStack(alignment: .top) {
            if hasVideo {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        VideoPlayer(player: model.player).background(Color.black)
                        if !model.caption.isEmpty {
                            Text(model.caption)
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 15).padding(.vertical, 9)
                                .frame(maxWidth: geometry.size.width * 0.75)
                                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.bottom, 58).allowsHitTesting(false)
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.08, green: 0.14, blue: 0.27), Color(red: 0.14, green: 0.19, blue: 0.32), Color(red: 0.06, green: 0.09, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Color.blue.opacity(0.27)).frame(width: 420).blur(radius: 105).offset(x: -260, y: -170)
                    Circle().fill(Color.cyan.opacity(0.16)).frame(width: 360).blur(radius: 115).offset(x: 290, y: 160)
                    welcome
                }.clipped()
            }
            header(compact: layout.size.width < 670)
                .padding(.horizontal, layout.size.width < 670 ? 12 : 22).padding(.top, 48)
                .environment(\.colorScheme, .dark)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
                .onHover { over in hoveringControls = over; showControls() }
        }
        .background(WindowGlassConfiguration(onMouseActivity: { showControls() }))
        .onReceive(model.player.publisher(for: \.timeControlStatus)) { state in
            isPlaying = state == .playing; showControls()
        }
        .onChange(of: hasVideo) { _, _ in showControls() }
        .task(id: activity) {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            if visibilityPolicy.shouldHide(hasVideo: hasVideo, isPlaying: isPlaying, hoveringControls: hoveringControls, idleSeconds: 3) && !model.showTranscript && !model.showEndPrompt {
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
            }
        }
        }
        .frame(minWidth: 480, minHeight: 360)
        .onOpenURL { model.load($0) }
        .sheet(isPresented: $model.showTranscript) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "text.alignleft").font(.title3).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("字幕文稿").font(.headline)
                        Text("本机识别 · 可选择和复制文字").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("保存文稿") { model.showTranscript = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.exportTranscript() } }
                    Button("完成") { model.showTranscript = false }.keyboardShortcut(.defaultAction)
                }.padding(20)
                Divider()
                ScrollView {
                    Text(model.transcriptText).textSelection(.enabled)
                        .font(.system(size: 15)).lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }.frame(minWidth: 440, minHeight: 360)
        }
        .alert("视频播放结束", isPresented: $model.showEndPrompt) {
            Button("保存字幕文档") { model.exportTranscript() }
            Button("稍后再说", role: .cancel) { }
        } message: { Text("是否保存已识别的文字？原音识别可能提前包含尚未观看的部分。") }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                if !compact { VStack(alignment: .leading, spacing: 3) {
                    Text(hasVideo ? (model.fileName as NSString).deletingPathExtension : "实时字幕播放器")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(hasVideo ? model.status : "本机语音识别")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: 260, alignment: .leading) }
            }
            .padding(.horizontal, 17).padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Picker("识别语言", selection: $model.language) {
                    Text("普通话").tag("zh-CN"); Text("粤语").tag("zh-HK"); Text("英语").tag("en-US"); Text("日语").tag("ja-JP")
                }.labelsHidden().frame(width: compact ? 90 : 100).help("选择字幕识别语言；更改后请重新识别")
                Menu {
                    Button { model.previewTranscript() } label: { Label("查看字幕文稿", systemImage: "text.alignleft") }
                    Button { model.exportTranscript() } label: { Label("保存字幕文稿", systemImage: "square.and.arrow.down") }
                    Divider()
                    Button { model.startOriginalAudio() } label: { Label("原音识别", systemImage: "waveform") }
                    Button { Task { await model.start() } } label: { Label("实时识别", systemImage: "captions.bubble") }
                } label: { Label("字幕", systemImage: "captions.bubble") }
                .help("查看、保存或重新识别字幕")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
            Button { model.open() } label: { if compact { Image(systemName: "plus") } else { Label("打开视频", systemImage: "plus") } }
                .help("打开视频")
                .keyboardShortcut("o").buttonStyle(.glassProminent).controlSize(.large)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 47, weight: .light)).foregroundStyle(.white)
                .frame(width: 108, height: 108)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            Text("让观看更清晰")
                .font(.system(size: 27, weight: .semibold)).foregroundStyle(.white).padding(.top, 23)
            Text("打开视频，在本机生成字幕。")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.72)).padding(.top, 8)
            Button { model.open() } label: { Label("选择视频", systemImage: "folder") }
                .buttonStyle(.glassProminent).controlSize(.large).padding(.top, 24)
            Text("支持 macOS 可播放的视频与音频文件")
                .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.top, 16)
        }.padding(30).environment(\.colorScheme, .dark)
    }
}
struct WindowGlassConfiguration: NSViewRepresentable {
    var onMouseActivity: () -> Void
    func makeNSView(context: Context) -> MouseTrackingView {
        let view = MouseTrackingView()
        view.onMouseActivity = onMouseActivity
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .black
        }
        return view
    }
    func updateNSView(_ view: MouseTrackingView, context: Context) { view.onMouseActivity = onMouseActivity }
}
final class MouseTrackingView: NSView {
    var onMouseActivity: (() -> Void)?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self, weak window] event in
            if let self, event.window === window { self.onMouseActivity?() }
            return event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
@main struct CaptionPlayer: App { var body: some Scene { WindowGroup { ContentView() }.windowStyle(.hiddenTitleBar) } }

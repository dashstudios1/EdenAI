import SwiftUI
import AVFoundation
import Speech

@main
struct EdenAIApp: App {
    var body: some Scene {
        WindowGroup {
            EdenHomeView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

// MARK: - Emotions
enum EdenEmotion: Equatable {
    case idle
    case sleeping
    case joltingAwake
    case listening
    case thinking
    case speaking
    case happy
    case helpful
    case empathetic
}

// MARK: - View Model & Voice / Animation Controller
final class EdenViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var emotion: EdenEmotion = .idle
    @Published var isSleeping: Bool = false
    @Published var joltPhase: Int = 0 // Triggers jolt keyframes cleanly

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var inactivityTimer: Timer?
    private var wakeResetTimer: Timer?
    private var lastWakeWordTrigger = Date.distantPast
    private var speechCompletion: (() -> Void)?
    private var isRestartingRecognition = false

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        configureAudioSession()
        requestPermissions()
        resetInactivityTimer()
    }

    deinit {
        inactivityTimer?.invalidate()
        wakeResetTimer?.invalidate()
        stopAudioEngine()
    }

    // MARK: Audio Session & Permissions
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }

    func requestPermissions() {
        AVAudioApplication.requestRecordPermission { [weak self] micGranted in
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if micGranted && speechStatus == .authorized {
                        self.startListeningForWakeWord()
                    } else {
                        print("Permissions not granted — mic: \(micGranted), speech: \(speechStatus.rawValue)")
                    }
                }
            }
        }
    }

    // MARK: Sleep & Wake ("Jolt Awake")
    func resetInactivityTimer(after delay: TimeInterval = 5.0) {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard !self.speechSynthesizer.isSpeaking, self.emotion != .joltingAwake else {
                self.resetInactivityTimer(after: 3.0)
                return
            }
            withAnimation(.easeInOut(duration: 1.1)) {
                self.isSleeping = true
                self.emotion = .sleeping
            }
        }
    }

    func userInteracted() {
        if isSleeping {
            joltAwake(listenAfter: false)
        } else {
            resetInactivityTimer()
        }
    }

    func joltAwake(listenAfter: Bool = true) {
        inactivityTimer?.invalidate()
        wakeResetTimer?.invalidate()
        isSleeping = false

        // Step 1: Sharp startle jolt upward & outward
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 11, initialVelocity: 8)) {
            emotion = .joltingAwake
            joltPhase += 1
        }
        playWakeChime()

        // Step 2: Settle calmly into attentive/idle state
        wakeResetTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                self.emotion = listenAfter ? .listening : .idle
            }
            self.resetInactivityTimer(after: listenAfter ? 7.0 : 5.0)
        }
    }

    // MARK: Speech Recognition (Wake Word & Commands)
    func startListeningForWakeWord() {
        guard !speechSynthesizer.isSpeaking else { return }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }

        stopAudioEngine()
        configureAudioSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine failed to start: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()
                let hasWakeWord = transcript.contains("hey eden") || transcript.contains("eden")

                if hasWakeWord && Date().timeIntervalSince(self.lastWakeWordTrigger) > 1.8 {
                    self.lastWakeWordTrigger = Date()
                    DispatchQueue.main.async {
                        self.handleWakeWordDetected(fullTranscript: transcript)
                    }
                }

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.scheduleRecognitionRestart()
                    }
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.scheduleRecognitionRestart()
                }
            }
        }
    }

    private func handleWakeWordDetected(fullTranscript: String) {
        let cleaned = fullTranscript
            .replacingOccurrences(of: "hey eden", with: "")
            .replacingOccurrences(of: "eden", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isSleeping {
            joltAwake(listenAfter: cleaned.isEmpty)
            if !cleaned.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.processCommand(cleaned)
                }
            }
        } else if !cleaned.isEmpty {
            processCommand(cleaned)
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                emotion = .listening
            }
            resetInactivityTimer(after: 6.0)
        }

        scheduleRecognitionRestart()
    }

    private func scheduleRecognitionRestart() {
        guard !isRestartingRecognition, !speechSynthesizer.isSpeaking else { return }
        isRestartingRecognition = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            self.isRestartingRecognition = false
            if !self.speechSynthesizer.isSpeaking {
                self.startListeningForWakeWord()
            }
        }
    }

    private func stopAudioEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: Assistant Responses & Speech Synthesis
    func processCommand(_ command: String) {
        inactivityTimer?.invalidate()

        withAnimation(.easeInOut(duration: 0.5)) {
            emotion = .thinking
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            let reply: String
            let targetEmotion: EdenEmotion

            if command.contains("light") {
                reply = "I've adjusted the lights for you."
                targetEmotion = .happy
            } else if command.contains("temperature") || command.contains("thermostat") || command.contains("warm") || command.contains("cool") {
                reply = "The thermostat is set to a comfortable temperature."
                targetEmotion = .helpful
            } else if command.contains("tired") || command.contains("rough day") || command.contains("stressed") {
                reply = "Take a slow breath. I'm right here if you need anything."
                targetEmotion = .empathetic
            } else {
                reply = "I'm here and ready to help around the house."
                targetEmotion = .helpful
            }

            withAnimation(.easeInOut(duration: 0.45)) {
                self.emotion = targetEmotion
            }

            self.speak(reply) {
                withAnimation(.easeInOut(duration: 0.7)) {
                    self.emotion = .idle
                }
                self.resetInactivityTimer(after: 5.0)
            }
        }
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        stopAudioEngine()
        configureAudioSession()

        speechCompletion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speechCompletion?()
            self.speechCompletion = nil
            self.scheduleRecognitionRestart()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speechCompletion?()
            self.speechCompletion = nil
            self.scheduleRecognitionRestart()
        }
    }

    private func playWakeChime() {
        AudioServicesPlaySystemSound(1057)
    }
}

// MARK: - Main Full-Screen Pitch-Black Display
struct EdenHomeView: View {
    @StateObject private var vm = EdenViewModel()
    @State private var isBlinking = false
    @State private var calmDrift: CGFloat = 0
    @State private var sleepBreath = false
    @State private var zzzRise = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Calm drifting "z Z z" while sleeping
            if vm.isSleeping {
                VStack {
                    Spacer()
                    HStack(spacing: 36) {
                        Text("z")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(zzzRise ? 0.0 : 0.35))
                            .offset(x: -8, y: zzzRise ? -48 : 0)

                        Text("Z")
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(zzzRise ? 0.0 : 0.45))
                            .offset(x: 4, y: zzzRise ? -72 : -10)

                        Text("z")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(zzzRise ? 0.0 : 0.3))
                            .offset(x: 10, y: zzzRise ? -54 : -4)
                    }
                    .padding(.bottom, 120)
                }
                .onAppear {
                    zzzRise = false
                    withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: false)) {
                        zzzRise = true
                    }
                }
                .onDisappear {
                    zzzRise = false
                }
            }

            // Expressive Ring Eyes
            HStack(spacing: 84) {
                EdenEyeView(
                    emotion: vm.emotion,
                    isBlinking: isBlinking,
                    sleepBreath: sleepBreath,
                    isLeft: true
                )
                EdenEyeView(
                    emotion: vm.emotion,
                    isBlinking: isBlinking,
                    sleepBreath: sleepBreath,
                    isLeft: false
                )
            }
            // Calm breathing in sleep, subtle calm float in idle, sharp jolt on wake
            .offset(
                x: vm.emotion == .joltingAwake ? -4 : calmDrift * 4,
                y: vm.emotion == .joltingAwake ? -22 : (vm.isSleeping ? (sleepBreath ? 6 : -4) : calmDrift * 3)
            )
            .scaleEffect(vm.emotion == .joltingAwake ? 1.14 : 1.0)
            .onChange(of: vm.isSleeping) { _, sleeping in
                if sleeping {
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                        sleepBreath = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        sleepBreath = false
                    }
                }
            }
            .onAppear {
                startCalmAmbientMotion()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.userInteracted()
        }
    }

    private func startCalmAmbientMotion() {
        // Gentle, unhurried ambient drift
        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
            calmDrift = 1.0
        }

        // Calm periodic blinking when awake & idle
        Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in
            guard vm.emotion == .idle && !vm.isSleeping else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isBlinking = false
                }
            }
        }
    }
}

// MARK: - Ring Eye Renderer
struct EdenEyeView: View {
    let emotion: EdenEmotion
    let isBlinking: Bool
    let sleepBreath: Bool
    let isLeft: Bool

    var body: some View {
        ZStack {
            switch emotion {
            case .sleeping:
                // Calm downward eyelid arc
                Path { path in
                    path.addArc(
                        center: CGPoint(x: 56, y: 52),
                        radius: 44,
                        startAngle: .degrees(12),
                        endAngle: .degrees(168),
                        clockwise: false
                    )
                }
                .stroke(
                    Color.white.opacity(sleepBreath ? 0.65 : 0.9),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 112, height: 112)
                .scaleEffect(y: sleepBreath ? 0.62 : 0.75)

            case .happy:
                // Soft upward smile arc
                Path { path in
                    path.addArc(
                        center: CGPoint(x: 56, y: 74),
                        radius: 44,
                        startAngle: .degrees(192),
                        endAngle: .degrees(348),
                        clockwise: false
                    )
                }
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .frame(width: 112, height: 112)

            default:
                // Crisp circular ring eye (O O)
                Circle()
                    .stroke(Color.white, lineWidth: emotion == .joltingAwake ? 18 : 16)
                    .frame(width: 112, height: 112)
                    .scaleEffect(
                        x: emotion == .joltingAwake ? 1.08 : 1.0,
                        y: isBlinking ? 0.05 : (emotion == .joltingAwake ? 1.16 : 1.0)
                    )

                // Soft inner glow when thinking or listening
                if emotion == .thinking || emotion == .listening {
                    Circle()
                        .fill(Color.white.opacity(emotion == .listening ? 0.22 : 0.35))
                        .frame(width: 44, height: 44)
                        .scaleEffect(isBlinking ? 0.85 : 1.08)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isBlinking)
                }
            }
        }
        .frame(width: 120, height: 120)
    }
}

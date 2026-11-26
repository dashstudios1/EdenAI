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

// MARK: - View Model & AI Logic
class EdenViewModel: ObservableObject {
    @Published var emotion: EdenEmotion = .idle
    @Published var isSleeping: Bool = false
    @Published var isWakingUp: Bool = false
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var inactivityTimer: Timer?
    private var zzzOffset: CGFloat = 0
    
    init() {
        requestPermissions()
        resetInactivityTimer()
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    self.startListeningForWakeWord()
                }
            }
        }
    }
    
    func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, self.emotion == .idle && !self.isSleeping else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                self.isSleeping = true
                self.emotion = .sleeping
            }
        }
    }
    
    func userInteracted() {
        if isSleeping {
            wakeUp()
        } else {
            resetInactivityTimer()
        }
    }
    
    func wakeUp() {
        isSleeping = false
        isWakingUp = true
        emotion = .surprised
        playChime()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self.isWakingUp = false
                self.emotion = .idle
            }
            self.resetInactivityTimer()
        }
    }
    
    func startListeningForWakeWord() {
        guard !audioEngine.isRunning else { return }
        
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            guard let result = result else { return }
            let spokenText = result.bestTranscription.formattedString.lowercased()
            
            if spokenText.contains("hey eden") || spokenText.contains("eden") {
                if self.isSleeping {
                    self.wakeUp()
                } else {
                    self.processCommand(spokenText)
                }
                // Reset speech task for next utterance
                self.restartSpeechRecognition()
            }
        }
    }
    
    func restartSpeechRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        startListeningForWakeWord()
    }
    
    func processCommand(_ command: String) {
        resetInactivityTimer()
        withAnimation { emotion = .thinking }
        
        // Simulate Gemini Smart Home response or query
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let responseText: String
            let targetEmotion: EdenEmotion
            
            if command.contains("light") {
                responseText = "I've adjusted the smart lights for you."
                targetEmotion = .happy
            } else if command.contains("temperature") || command.contains("thermostat") {
                responseText = "Thermostat is set to comfortable."
                targetEmotion = .helpful
            } else if command.contains("joke") {
                responseText = "Why did the robot cross the road? Because it was programmed by the chicken!"
                targetEmotion = .happy
            } else {
                responseText = "I'm listening and ready to help with your home."
                targetEmotion = .helpful
            }
            
            withAnimation { self.emotion = targetEmotion }
            self.speak(responseText) {
                withAnimation { self.emotion = .idle }
                self.resetInactivityTimer()
            }
        }
    }
    
    func speak(_ text: String, completion: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.1
        
        // Observe speech finish via delegate or simple timer fallback
        speechSynthesizer.speak(utterance)
        
        let duration = Double(text.split(separator: " ").count) * 0.35 + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 2.0)) {
            completion()
        }
    }
    
    func playChime() {
        let systemSoundID: SystemSoundID = 1057
        AudioServicesPlaySystemSound(systemSoundID)
    }
}

// MARK: - Emotions Enum
enum EdenEmotion {
    case idle, sleeping, waking, thinking, happy, surprised, helpful, empathetic
}

// MARK: - Main View
struct EdenHomeView: View {
    @StateObject private var vm = EdenViewModel()
    @State private var blinkState = false
    @State private var zzzAnim = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Sleep Zzz Particles
            if vm.isSleeping {
                VStack {
                    Spacer()
                    HStack(spacing: 40) {
                        Text("z")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: zzzAnim ? -40 : 0)
                        Text("Z")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.gray.opacity(0.8))
                            .offset(y: zzzAnim ? -70 : 0)
                        Text("z")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.gray.opacity(0.5))
                            .offset(y: zzzAnim ? -50 : 0)
                    }
                    .padding(.bottom, 120)
                }
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) {
                        zzzAnim.toggle()
                    }
                }
            }
            
            // Robot Face (Eyes)
            HStack(spacing: 80) {
                EdenEyeView(emotion: vm.emotion, blinkState: blinkState, isLeft: true)
                EdenEyeView(emotion: vm.emotion, blinkState: blinkState, isLeft: false)
            }
            .onAppear {
                startBlinkTimer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.userInteracted()
        }
    }
    
    func startBlinkTimer() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            guard vm.emotion == .idle && !vm.isSleeping else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                blinkState = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.12)) {
                    blinkState = false
                }
            }
        }
    }
}

// MARK: - Individual Eye View Renderer
struct EdenEyeView: View {
    var emotion: EdenEmotion
    var blinkState: Bool
    var isLeft: Bool
    
    var body: some View {
        ZStack {
            if emotion == .sleeping {
                // Sleeping Eyelid Arc (U U)
                Path { path in
                    path.addArc(center: CGPoint(x: 55, y: 55),
                                radius: 45,
                                startAngle: .degrees(0),
                                endAngle: .degrees(180),
                                clockwise: false)
                }
                .stroke(Color.white, lineWidth: 14)
                .frame(width: 110, height: 110)
                .scaleEffect(y: 0.7)
            } else if emotion == .happy {
                // Happy Arc (^ ^)
                Path { path in
                    path.addArc(center: CGPoint(x: 55, y: 75),
                                radius: 45,
                                startAngle: .degrees(180),
                                endAngle: .degrees(360),
                                clockwise: false)
                }
                .stroke(Color.white, lineWidth: 14)
                .frame(width: 110, height: 110)
            } else {
                // Standard Ring Eye (O O) with blink support
                Circle()
                    .stroke(Color.white, lineWidth: 16)
                    .frame(width: 110, height: 110)
                    .scaleEffect(y: blinkState ? 0.05 : 1.0)
                
                // Thinking Inner Pulse
                if emotion == .thinking {
                    Circle()
.fill(Color.white.opacity(0.4))
.frame(width: 50, height: 50)
.scaleEffect(blinkState ? 1.2 : 0.8)
.animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: blinkState)
}
}
}
.frame(width: 120, height: 120)
}
}

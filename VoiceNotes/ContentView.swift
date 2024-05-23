import SwiftUI
import AVFoundation
import Speech
import WatchConnectivity

class VoiceMemosData: NSObject, ObservableObject, WCSessionDelegate {
    @Published var voiceMemos: [VoiceMemo] = []
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var audioData: Data?
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        
        requestSpeechRecognitionPermission()
    }
    
    private var audioRecorder: AVAudioRecorder?

    func getAudioFilename() -> String {
        let timestamp = Date().timeIntervalSince1970
        return "memo_\(timestamp).m4a"
    }
    
    func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied:
                    print("Speech recognition denied")
                case .restricted:
                    print("Speech recognition restricted")
                case .notDetermined:
                    print("Speech recognition not determined")
                @unknown default:
                    print("Unknown speech recognition authorization status")
                }
            }
        }
    }
    
    func startRecording() {
        print("Start recording...")
        isRecording = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default)
        try? audioSession.setActive(true)
        
        let audioFilename = getAudioFilename()
        let audioFileURL = getDocumentsDirectory().appendingPathComponent(audioFilename)
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFileURL, settings: settings)
            audioRecorder?.record()
            
            let newMemo = VoiceMemo(id: UUID(), timestamp: Date(), audioURL: audioFileURL, transcription: "", transcriptionStatus: "Transcription in progress...")
            self.voiceMemos.append(newMemo)
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        print("Stop recording...")
        audioRecorder?.stop()
        isRecording = false
        isPaused = false

        if let audioFileURL = audioRecorder?.url {
            print("Audio file URL: \(audioFileURL)")

            if let index = self.voiceMemos.firstIndex(where: { $0.audioURL == audioFileURL }) {
                Task {
                    do {
                        let transcription = try await transcribeAudio(fromURL: audioFileURL)
                        DispatchQueue.main.async {
                            self.voiceMemos[index].transcription = transcription
                            self.voiceMemos[index].transcriptionStatus = "Transcription completed"
                            self.voiceMemos[index].timestamp = Date()
                            print("Sending transcribed memo to watch: \(self.voiceMemos[index])")
                            self.sendTranscribedMemoToWatch(self.voiceMemos[index])
                        }
                    } catch {
                        print("Transcription failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.voiceMemos[index].transcriptionStatus = "Transcription failed"
                        }
                    }
                }
            }
        } else {
            print("Audio file URL is nil")
        }

        audioRecorder = nil
    }
    
    func pauseRecording() {
        print("Pause recording...")
        audioRecorder?.pause()
        isPaused = true
    }
    
    func resumeRecording() {
        print("Resume recording...")
        audioRecorder?.record()
        isPaused = false
    }

    func transcribeAudio(fromURL audioURL: URL) async throws -> String {
        print("Transcribing audio from URL: \(audioURL)")
        
        guard let recognizer = SFSpeechRecognizer() else {
            print("Speech recognition is not available on this device")
            throw NSError(domain: "TranscriptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available on this device"])
        }
        
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: audioURL)
        recognitionRequest.shouldReportPartialResults = false
        
        print("Starting recognition task...")
        
        return try await withCheckedThrowingContinuation { continuation in
            let recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let error = error {
                    print("Transcription failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    print("Transcription result is nil")
                    continuation.resume(throwing: NSError(domain: "TranscriptionError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Transcription result is nil"]))
                    return
                }
                
                let transcription = result.bestTranscription.formattedString
                print("Transcription: \(transcription)")
                continuation.resume(returning: transcription)
            }
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func playAudio(audioURL: URL) -> AVAudioPlayer? {
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer.play()
            return audioPlayer
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
            return nil
        }
    }
    
    func deleteVoiceMemo(_ memo: VoiceMemo) {
        DispatchQueue.main.async {
            if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                self.voiceMemos.remove(at: index)
                try? FileManager.default.removeItem(at: memo.audioURL)
            }
        }
    }
    
    func startExtendingRecording(_ memo: VoiceMemo) {
        print("Start extending recording...")
        isRecording = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default)
        try? audioSession.setActive(true)
        
        let audioFilename = getAudioFilename()
        let audioFileURL = getDocumentsDirectory().appendingPathComponent(audioFilename)
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFileURL, settings: settings)
            audioRecorder?.record()
            
            if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                self.voiceMemos[index].transcriptionStatus = "Transcription in progress..."
            }
        } catch {
            print("Could not start extending recording: \(error.localizedDescription)")
        }
    }

    func stopExtendingRecording(_ memo: VoiceMemo) {
        print("Stop extending recording...")
        audioRecorder?.stop()
        isRecording = false
        
        if let audioFileURL = audioRecorder?.url {
            print("Extended audio file URL: \(audioFileURL)")
            
            Task {
                do {
                    let mergedURL = try await mergeAudioFiles(originalURL: memo.audioURL, extendedURL: audioFileURL)
                    
                    // Get the duration of the original audio
                    let originalAsset = AVAsset(url: memo.audioURL)
                    let originalDuration = try await originalAsset.load(.duration)
                    
                    // Trim the merged audio to get only the newly added portion
                    let trimmedURL = try await trimAudio(audioURL: mergedURL, startTime: originalDuration)
                    
                    // Transcribe the trimmed audio
                    let transcription = try await transcribeAudio(fromURL: trimmedURL)
                    
                    if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                        self.voiceMemos[index].audioURL = mergedURL
                        
                        // Add a space or break between the existing and new transcriptions
                        if !self.voiceMemos[index].transcription.isEmpty {
                            self.voiceMemos[index].transcription += "\n\n" // Add two line breaks
                        }
                        self.voiceMemos[index].transcription += transcription
                        self.voiceMemos[index].transcriptionStatus = "Transcription completed"
                        self.voiceMemos[index].timestamp = Date()
                    }
                } catch {
                    print("Error merging audio files or transcribing: \(error.localizedDescription)")
                    if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                        self.voiceMemos[index].transcriptionStatus = "Transcription failed"
                    }
                }
            }
        } else {
            print("Extended audio file URL is nil")
        }
        
        audioRecorder = nil
    }

    func mergeAudioFiles(originalURL: URL, extendedURL: URL) async throws -> URL {
        let originalAsset = AVAsset(url: originalURL)
        let extendedAsset = AVAsset(url: extendedURL)
        
        let composition = AVMutableComposition()
        
        guard let originalTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let extendedTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Failed to add tracks to composition")
            throw NSError(domain: "MergeAudioError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to add tracks to composition"])
        }
        
        do {
            let originalDuration = try await originalAsset.load(.duration)
            let extendedDuration = try await extendedAsset.load(.duration)
            
            let originalAudioTracks = try await originalAsset.loadTracks(withMediaType: .audio)
            let extendedAudioTracks = try await extendedAsset.loadTracks(withMediaType: .audio)
            
            try originalTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: originalDuration), of: originalAudioTracks[0], at: .zero)
            try extendedTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: extendedDuration), of: extendedAudioTracks[0], at: originalDuration)
        } catch {
            print("Failed to insert time ranges: \(error.localizedDescription)")
            throw error
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            print("Failed to create export session")
            throw NSError(domain: "MergeAudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        let mergedAudioFilename = "merged_\(Date().timeIntervalSince1970).m4a"
        let mergedAudioFileURL = getDocumentsDirectory().appendingPathComponent(mergedAudioFilename)
        
        exportSession.outputURL = mergedAudioFileURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true
        
        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    print("Audio files merged successfully")
                    continuation.resume(returning: mergedAudioFileURL)
                case .failed:
                    print("Failed to merge audio files: \(exportSession.error?.localizedDescription ?? "")")
                    continuation.resume(throwing: exportSession.error ?? NSError(domain: "MergeAudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to merge audio files"]))
                case .cancelled:
                    print("Audio file merging cancelled")
                    continuation.resume(throwing: NSError(domain: "MergeAudioError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio file merging cancelled"]))
                default:
                    print("Audio file merging status unknown")
                    continuation.resume(throwing: NSError(domain: "MergeAudioError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio file merging status unknown"]))
                }
            }
        }
    }
    
    func trimAudio(audioURL: URL, startTime: CMTime) async throws -> URL {
        let asset = AVAsset(url: audioURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        
        let trimmedAudioFilename = "trimmed_\(Date().timeIntervalSince1970).m4a"
        let trimmedAudioFileURL = getDocumentsDirectory().appendingPathComponent(trimmedAudioFilename)
        
        exportSession?.outputURL = trimmedAudioFileURL
        exportSession?.outputFileType = .m4a
        exportSession?.timeRange = CMTimeRangeMake(start: startTime, duration: CMTimeSubtract(asset.duration, startTime))
        
        return try await withCheckedThrowingContinuation { continuation in
            exportSession?.exportAsynchronously {
                switch exportSession?.status {
                case .completed:
                    continuation.resume(returning: trimmedAudioFileURL)
                case .failed:
                    continuation.resume(throwing: exportSession?.error ?? NSError(domain: "TrimAudioError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to trim audio"]))
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "TrimAudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Trim audio cancelled"]))
                default:
                    continuation.resume(throwing: NSError(domain: "TrimAudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown trim audio status"]))
                }
            }
        }
    }
    
    func saveVoiceMemos() {
        // Save voice memos to disk
    }
    
    func loadVoiceMemos() {
        // Load voice memos from disk
    }
    
    func transcribeVoiceMemo(_ memo: VoiceMemo) {
        Task {
            do {
                let transcription = try await transcribeAudio(fromURL: memo.audioURL)
                if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                    self.voiceMemos[index].transcription = transcription
                                        self.voiceMemos[index].transcriptionStatus = "Transcription completed"
                                        self.sendTranscribedMemoToWatch(self.voiceMemos[index])
                                        print("Transcription completed for memo: \(memo.id)")
                                    }
                                } catch {
                                    print("Transcription failed for memo: \(memo.id), error: \(error.localizedDescription)")
                                    if let index = self.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                                        self.voiceMemos[index].transcriptionStatus = "Transcription failed"
                                    }
                                }
                            }
                        }
                        
                        func sendTranscribedMemoToWatch(_ memo: VoiceMemo) {
                            if let data = try? JSONEncoder().encode(memo) {
                                let session = WCSession.default
                                if session.activationState == .activated && session.isReachable {
                                    session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
                                        print("Error sending transcribed memo to watchOS app: \(error.localizedDescription)")
                                    })
                                } else {
                                    print("WCSession is not activated or watchOS app is not reachable")
                                }
                            } else {
                                print("Failed to encode transcribed memo")
                            }
                        }
                        
                        // MARK: - WCSessionDelegate methods
                        
                        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
                            if let error = error {
                                print("WCSession activation failed with error: \(error.localizedDescription)")
                            } else {
                                print("WCSession activated with state: \(activationState.rawValue)")
                            }
                        }
                        
                        func sessionDidBecomeInactive(_ session: WCSession) {
                            print("WCSession did become inactive")
                        }

                        func sessionDidDeactivate(_ session: WCSession) {
                            print("WCSession did deactivate")
                        }
                        
                        func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
                            print("Received message from watchOS app: \(message)")
                            
                            if let voiceMemoData = message["voiceMemo"] as? Data,
                               let voiceMemo = try? JSONDecoder().decode(VoiceMemo.self, from: voiceMemoData) {
                                DispatchQueue.main.async {
                                    self.voiceMemos.append(voiceMemo)
                                    self.transcribeVoiceMemo(voiceMemo)
                                    print("Received voice memo from watchOS app: \(voiceMemo.id)")
                                }
                            } else {
                                print("Failed to decode voice memo from watchOS app")
                            }
                        }
    
                        func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
                            print("Received user info from watchOS app: \(userInfo)")
                            
                            if let voiceMemoData = userInfo["voiceMemo"] as? Data {
                                print("Received voice memo data: \(voiceMemoData)")
                                
                                if let voiceMemo = try? JSONDecoder().decode(VoiceMemo.self, from: voiceMemoData) {
                                    print("Decoded voice memo: \(voiceMemo)")
                                    
                                    DispatchQueue.main.async {
                                        self.voiceMemos.append(voiceMemo)
                                        self.transcribeVoiceMemo(voiceMemo)
                                        print("Received voice memo from watchOS app: \(voiceMemo.id)")
                                    }
                                } else {
                                    print("Failed to decode voice memo")
                                }
                            } else {
                                print("Failed to extract voice memo data from user info")
                            }
                        }
                    }

                    struct ContentView: View {
                        @StateObject private var voiceMemosData = VoiceMemosData()
                        
                        var body: some View {
                            NavigationView {
                                VStack {
                                    List {
                                        ForEach(voiceMemosData.voiceMemos.sorted(by: { $0.timestamp > $1.timestamp })) { memo in
                                            NavigationLink(destination: VoiceMemoDetailView(memo: memo)) {
                                                VoiceMemoCell(memo: memo)
                                            }
                                        }
                                    }
                                    
                                    HStack {
                                        if voiceMemosData.isRecording {
                                            if voiceMemosData.isPaused {
                                                Button(action: {
                                                    voiceMemosData.resumeRecording()
                                                }) {
                                                    Image(systemName: "play.circle")
                                                }
                                                .padding()
                                            } else {
                                                Button(action: {
                                                    voiceMemosData.pauseRecording()
                                                }) {
                                                    Image(systemName: "pause.circle")
                                                }
                                                .padding()
                                            }
                                            
                                            Button(action: {
                                                voiceMemosData.stopRecording()
                                            }) {
                                                Image(systemName: "stop.circle")
                                            }
                                            .padding()
                                        } else {
                                            Button(action: {
                                                voiceMemosData.startRecording()
                                            }) {
                                                Image(systemName: "mic")
                                            }
                                            .padding()
                                        }
                                    }
                                    .padding()
                                }
                                .navigationTitle("Voice Memos")
                            }
                            .environmentObject(voiceMemosData)
                        }
                    }

                    struct VoiceMemoCell: View {
                        let memo: VoiceMemo
                        @State private var isPlaying = false
                        @State private var audioPlayer: AVAudioPlayer?
                        @EnvironmentObject private var voiceMemosData: VoiceMemosData
                        
                        var body: some View {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(memo.timestamp, style: .date)
                                    Text(memo.timestamp, style: .time)
                                    Text(memo.transcription)
                                        .font(.subheadline)
                                        .lineLimit(2) // Preview of the transcription
                                    Text(memo.transcriptionStatus)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if isPlaying {
                                        audioPlayer?.stop()
                                    } else {
                                        audioPlayer = voiceMemosData.playAudio(audioURL: memo.audioURL)
                                    }
                                    isPlaying.toggle()
                                }) {
                                    Image(systemName: isPlaying ? "stop.circle" : "play.circle")
                                }
                            }
                            .contextMenu {
                                Button(action: {
                                    voiceMemosData.deleteVoiceMemo(memo)
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    struct VoiceMemoDetailView: View {
                        @State var memo: VoiceMemo
                        @State private var isPlaying = false
                        @State private var audioPlayer: AVAudioPlayer?
                        @State private var isTranscribing = false
                        @EnvironmentObject private var voiceMemosData: VoiceMemosData
                        
                        var body: some View {
                            VStack {
                                TextEditor(text: $memo.transcription)
                                    .font(.body)
                                    .padding()
                                    .navigationTitle("Edit Transcription")
                                
                                if isTranscribing {
                                    Text("Transcription in progress...")
                                        .foregroundColor(.gray)
                                        .padding()
                                }
                                
                                HStack {
                                    Button(action: {
                                        audioPlayer?.currentTime -= 10
                                    }) {
                                        Image(systemName: "gobackward.10")
                                    }
                                    .padding()
                                    
                                    Button(action: {
                                        if isPlaying {
                                            audioPlayer?.pause()
                                            isPlaying = false
                                        } else {
                                            if audioPlayer == nil {
                                                audioPlayer = try? AVAudioPlayer(contentsOf: memo.audioURL)
                                                audioPlayer?.delegate = PlayerDelegate(isPlayingBinding: $isPlaying)
                                            }
                                            audioPlayer?.currentTime = 0
                                            audioPlayer?.play()
                                            isPlaying = true
                                        }
                                    }) {
                                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                                    }
                                    .padding()
                                    
                                    Button(action: {
                                        audioPlayer?.currentTime += 10
                                    }) {
                                        Image(systemName: "goforward.10")
                                    }
                                    .padding()
                                    
                                    Button(action: {
                                        if voiceMemosData.isRecording {
                                            voiceMemosData.stopExtendingRecording(memo)
                                        } else {
                                            voiceMemosData.startExtendingRecording(memo)
                                        }
                                    }) {
                                        Image(systemName: voiceMemosData.isRecording ? "stop" : "plus")
                                    }
                                    .padding()
                                }
                                .padding()
                                
                                Spacer()
                            }
                            .onDisappear {
                                audioPlayer?.stop()
                                audioPlayer = nil
                            }
                            .onReceive(voiceMemosData.$isRecording) { isRecording in
                                isTranscribing = isRecording
                            }
                            .onAppear {
                                // Update the memo transcription in the main list when the view disappears
                                if let index = voiceMemosData.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                                    voiceMemosData.voiceMemos[index].transcription = memo.transcription
                                }
                            }
                        }
                    }

                    class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
                        var isPlayingBinding: Binding<Bool>
                        
                        init(isPlayingBinding: Binding<Bool>) {
                            self.isPlayingBinding = isPlayingBinding
                        }
                        
                        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
                            isPlayingBinding.wrappedValue = false
                            player.currentTime = 0
                        }
                    }

                    #Preview {
                        ContentView()
                    }

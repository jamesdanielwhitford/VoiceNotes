import SwiftUI
import AVFoundation
import Speech

struct VoiceMemo: Identifiable {
    let id = UUID()
    let timestamp: Date
    let audioURL: URL
    var transcription: String
}

class VoiceMemosData: ObservableObject {
    @Published var voiceMemos: [VoiceMemo] = []
    @Published var isRecording = false
    @Published var audioData: Data?
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    init() {
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
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        print("Stop recording...")
        audioRecorder?.stop()
        isRecording = false
        
        if let audioFileURL = audioRecorder?.url {
            print("Audio file URL: \(audioFileURL)")
            let newMemo = VoiceMemo(timestamp: Date(), audioURL: audioFileURL, transcription: "Transcription in progress...")
            self.voiceMemos.append(newMemo)
            transcribeAudio(fromURL: audioFileURL) { transcription in
                if let index = self.voiceMemos.firstIndex(where: { $0.audioURL == audioFileURL }) {
                    self.voiceMemos[index].transcription = transcription
                }
            }
        } else {
            print("Audio file URL is nil")
        }
        
        audioRecorder = nil
    }

    func transcribeAudio(fromURL audioURL: URL, completion: @escaping (String) -> Void) {
        print("Transcribing audio from URL: \(audioURL)")
        
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: audioURL)
        recognitionRequest.shouldReportPartialResults = false
        
        print("Starting recognition task...")
        let recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let error = error {
                print("Transcription failed: \(error.localizedDescription)")
                completion("")
                return
            }
            
            guard let result = result else {
                print("Transcription result is nil")
                completion("")
                return
            }
            
            let transcription = result.bestTranscription.formattedString
            print("Transcription: \(transcription)")
            completion(transcription)
        }
        
        print("Recognition task started.")
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
        if let index = voiceMemos.firstIndex(where: { $0.id == memo.id }) {
            voiceMemos.remove(at: index)
            try? FileManager.default.removeItem(at: memo.audioURL)
        }
    }
}

struct ContentView: View {
    @StateObject private var voiceMemosData = VoiceMemosData()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(voiceMemosData.voiceMemos) { memo in
                    NavigationLink(destination: VoiceMemoDetailView(memo: memo)) {
                        VoiceMemoCell(memo: memo)
                    }
                }
            }
            .navigationTitle("Voice Memos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if voiceMemosData.isRecording {
                            voiceMemosData.stopRecording()
                        } else {
                            voiceMemosData.startRecording()
                        }
                    }) {
                        Image(systemName: voiceMemosData.isRecording ? "stop.circle" : "mic")
                    }
                }
            }
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
                Text(memo.transcription)
                    .font(.subheadline)
                    .lineLimit(2) // Preview of the transcription
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
    @EnvironmentObject private var voiceMemosData: VoiceMemosData
    
    var body: some View {
        VStack {
            TextEditor(text: $memo.transcription)
                .font(.body)
                .padding()
                .navigationTitle("Edit Transcription")
            
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
                    } else {
                        if audioPlayer == nil {
                            audioPlayer = try? AVAudioPlayer(contentsOf: memo.audioURL)
                        }
                        audioPlayer?.play()
                    }
                    isPlaying.toggle()
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
                    // TODO: Implement extending the voice memo
                    print("Extend voice memo")
                }) {
                    Image(systemName: "plus")
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
        .onAppear {
            // Update the memo transcription in the main list when the view disappears
            if let index = voiceMemosData.voiceMemos.firstIndex(where: { $0.id == memo.id }) {
                voiceMemosData.voiceMemos[index].transcription = memo.transcription
            }
        }
    }
}

#Preview {
    ContentView()
}

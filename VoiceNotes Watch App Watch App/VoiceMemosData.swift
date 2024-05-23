import Foundation
import AVFoundation
import WatchConnectivity

class VoiceMemosData: NSObject, ObservableObject, WCSessionDelegate {
    @Published var voiceMemos: [VoiceMemo] = []
    @Published var isRecording = false
    @Published var isPaused = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    var session: WCSession?
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("\(Date().timeIntervalSince1970).m4a")
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session category and mode: \(error.localizedDescription)")
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
    }
    
    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        
        if let audioRecorder = audioRecorder {
            let voiceMemo = VoiceMemo(id: UUID(), timestamp: Date(), audioURL: audioRecorder.url, transcription: "", transcriptionStatus: "Transcription in progress...")
            print("Saved audio file URL: \(audioRecorder.url)")
            voiceMemos.append(voiceMemo)
            sendVoiceMemoToiOS(voiceMemo)
        }
        
        audioRecorder = nil
    }
    func playVoiceMemo(_ memo: VoiceMemo) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: memo.audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            print("Error loading audio file: \(error.localizedDescription)")
            print("Audio file URL: \(memo.audioURL)")
            // Handle the error, e.g., show an error message to the user
        }
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer = nil
    }
    
    func startExtendingRecording(_ memo: VoiceMemo) {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("\(Date().timeIntervalSince1970).m4a")
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session category and mode: \(error.localizedDescription)")
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Could not start extending recording: \(error.localizedDescription)")
        }
    }
    
    func stopExtendingRecording(_ memo: VoiceMemo) {
        audioRecorder?.stop()
        isRecording = false
        
        if let audioRecorder = audioRecorder {
            let extendedMemo = VoiceMemo(id: memo.id, timestamp: Date(), audioURL: audioRecorder.url, transcription: "", transcriptionStatus: "Transcription in progress...")
            sendVoiceMemoToiOS(extendedMemo)
        }
        
        audioRecorder = nil
    }
    
    func sendVoiceMemoToiOS(_ memo: VoiceMemo) {
        if let data = try? JSONEncoder().encode(memo) {
            print("Encoded voice memo data: \(data)")
            if let session = session, session.isReachable {
                print("iOS app is reachable")
                session.sendMessage(["voiceMemo": data], replyHandler: nil, errorHandler: { error in
                    print("Error sending voice memo to iOS app: \(error.localizedDescription)")
                })
            } else {
                print("iOS app not reachable")
            }
        } else {
            print("Failed to encode voice memo")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        print("Received message data from iOS app")
        if let voiceMemo = try? JSONDecoder().decode(VoiceMemo.self, from: messageData) {
            DispatchQueue.main.async {
                if let index = self.voiceMemos.firstIndex(where: { $0.id == voiceMemo.id }) {
                    self.voiceMemos[index] = voiceMemo
                    print("Updated transcribed memo in watchOS app: \(voiceMemo.id)")
                } else {
                    self.voiceMemos.append(voiceMemo)
                    print("Received new transcribed memo in watchOS app: \(voiceMemo.id)")
                }
            }
        } else {
            print("Failed to decode transcribed memo in watchOS app")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func requestVoiceMemosFromiOS() {
        if let session = session, session.isReachable {
            session.sendMessage(["request": "voiceMemos"], replyHandler: { replyData in
                if let voiceMemosData = replyData["voiceMemos"] as? Data,
                   let voiceMemos = try? JSONDecoder().decode([VoiceMemo].self, from: voiceMemosData) {
                    DispatchQueue.main.async {
                        self.voiceMemos = voiceMemos
                    }
                }
            }, errorHandler: nil)
        }
    }
}

extension VoiceMemosData: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}

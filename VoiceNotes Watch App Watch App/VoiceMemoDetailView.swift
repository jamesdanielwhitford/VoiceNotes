// VoiceMemoDetailView.swift (Watch app)

import SwiftUI

struct VoiceMemoDetailView: View {
    @StateObject private var voiceMemosData = VoiceMemosData()
    @State var memo: VoiceMemo
    @State private var isPlaying = false
    
    var body: some View {
        VStack {
            Text(memo.transcription)
                .font(.body)
                .padding()
            
            HStack {
                Button(action: {
                    if isPlaying {
                        voiceMemosData.pausePlayback()
                        isPlaying = false
                    } else {
                        voiceMemosData.playVoiceMemo(memo)
                        isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                
                Button(action: {
                    voiceMemosData.stopPlayback()
                    isPlaying = false
                }) {
                    Image(systemName: "stop.fill")
                }
            }
            
            Button(action: {
                voiceMemosData.startExtendingRecording(memo)
            }) {
                Text("Extend Recording")
            }
        }
        .navigationBarTitle("Voice Memo")
    }
}

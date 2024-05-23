// RecordButton.swift (Watch app)

import SwiftUI

struct RecordButton: View {
    @ObservedObject var voiceMemosData: VoiceMemosData
    
    var body: some View {
        HStack {
            if voiceMemosData.isRecording {
                if voiceMemosData.isPaused {
                    Button(action: {
                        voiceMemosData.resumeRecording()
                    }) {
                        Image(systemName: "play.fill")
                    }
                } else {
                    Button(action: {
                        voiceMemosData.pauseRecording()
                    }) {
                        Image(systemName: "pause.fill")
                    }
                }
                
                Button(action: {
                    voiceMemosData.stopRecording()
                }) {
                    Image(systemName: "stop.fill")
                }
            } else {
                Button(action: {
                    voiceMemosData.startRecording()
                }) {
                    Image(systemName: "record.circle")
                }
            }
        }
    }
}

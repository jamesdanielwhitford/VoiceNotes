// ContentView.swift (Watch app)

import SwiftUI

struct ContentView: View {
    @StateObject private var voiceMemosData = VoiceMemosData()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(voiceMemosData.voiceMemos.sorted(by: { $0.timestamp > $1.timestamp }), id: \.id) { memo in
                    NavigationLink(destination: VoiceMemoDetailView(memo: memo)) {
                        VStack(alignment: .leading) {
                            Text(memo.timestamp.formatted())
                            Text(memo.transcription)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationBarTitle("Voice Memos")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    RecordButton(voiceMemosData: voiceMemosData)
                }
            }
        }
        .onAppear {
            voiceMemosData.session?.delegate = voiceMemosData
            voiceMemosData.session?.activate()
            voiceMemosData.requestVoiceMemosFromiOS()
        }
    }
}

#Preview {
    ContentView()
}

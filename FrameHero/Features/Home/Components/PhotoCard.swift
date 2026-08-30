import SwiftUI

struct PhotoCard: View {
    let record: PhotoRecord
    let thumbnailProvider: (UUID) -> UIImage?
    @State private var thumbnail: UIImage?

    /// 角标优先用点评的综合分，没点过评则回退到拍摄时的构图评分
    private var displayScore: Int? { record.critique?.score ?? record.compositionScore }

    var body: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(DesignSystem.Colors.backgroundSecondary)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let displayScore {
                    Text("\(displayScore)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(5)
                }
            }
            .clipped()
            .onAppear {
                guard thumbnail == nil else { return }
                DispatchQueue.global(qos: .utility).async {
                    let image = thumbnailProvider(record.id)
                    DispatchQueue.main.async {
                        thumbnail = image
                    }
                }
            }
    }
}

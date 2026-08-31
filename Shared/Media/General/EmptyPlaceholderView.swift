//
//  EmptyPlaceholderView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 21.08.2022.
//

import SwiftUI

struct EmptyPlaceholderView: View {

    let text: String
    let image: Image?
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            if let image {
                image
                    .font(.system(size: 48))
                    .foregroundStyle(RezkaPalette.tertiaryText)
            }

            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(RezkaPalette.secondaryText)

            if let caption {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(RezkaPalette.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
        }
        .padding(40)
    }
}

struct EmptyPlaceholderView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyPlaceholderView(text: "No Bookmarks", image: Image(systemName: "bookmark"))
    }
}

//
//  RetryView.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 21.08.2022.
//

import SwiftUI

struct RetryView: View {

    let text: String
    let retryAction: () -> ()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(RezkaPalette.secondaryText)

            Text("Connection failed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(RezkaPalette.primaryText)

            Text(text)
                .font(.callout)
                .foregroundStyle(RezkaPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Text("Server: \(RezkaConstantsApi.server)")
                .font(.footnote)
                .foregroundStyle(RezkaPalette.tertiaryText)

            Button(action: retryAction) {
                Text("Try again")
            }
        }
        .padding(40)
    }
}

struct RetryView_Previews: PreviewProvider {
    static var previews: some View {
        RetryView(text: "Server returned HTTP 403") {}
    }
}

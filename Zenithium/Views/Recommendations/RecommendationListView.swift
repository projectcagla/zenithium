//
//  RecommendationListView.swift
//  Zenithium
//
//  Renders the list of daily evidence-backed recommendations on the Today screen.
//  Faz 34 Bölüm B.
//

import SwiftUI

struct RecommendationListView: View {

    let recommendations: [Recommendation]

    var body: some View {
        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("GÜNLÜK ÖNERİLER VE KANITLAR")
                        .zenithiumEyebrow()

                    Spacer()

                    Text("\(recommendations.count) Değerlendirme")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }

                VStack(spacing: ZenithiumSpacing.m) {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
            }
        }
    }
}

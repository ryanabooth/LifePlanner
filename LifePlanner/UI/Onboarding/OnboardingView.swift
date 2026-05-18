import SwiftUI

struct OnboardingView: View {

    let onComplete: (_ openGoals: Bool) -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                ForEach(OnboardingPage.all.indices, id: \.self) { i in
                    let p = OnboardingPage.all[i]
                    PageCard(page: p, isLast: i == OnboardingPage.all.count - 1,
                             onNext:       {
                                 withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                     page = i + 1
                                 }
                             },
                             onGetStarted: { onComplete(true) },
                             onSkip:       { onComplete(false) })
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Custom page dots
            HStack(spacing: 7) {
                ForEach(OnboardingPage.all.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.white : Color.white.opacity(0.4))
                        .frame(width: i == page ? 20 : 7, height: 7)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
                }
            }
            .padding(.top, 56)
            .accessibilityHidden(true)

            // Skip button — hidden on last page
            if page < OnboardingPage.all.count - 1 {
                HStack {
                    Spacer()
                    Button("Skip") { onComplete(false) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 48)
                        .padding(.trailing, 20)
                        .accessibilityLabel("Skip onboarding")
                }
            }
        }
    }
}

// MARK: - Page card

private struct PageCard: View {
    let page: OnboardingPage
    let isLast: Bool
    let onNext: () -> Void
    let onGetStarted: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            page.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Illustration
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 180, height: 180)
                    Image(systemName: page.symbol)
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.hierarchical)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 44)

                // Text
                VStack(spacing: 14) {
                    Text(page.headline)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                Spacer()

                // CTA
                if isLast {
                    VStack(spacing: 14) {
                        Button(action: onGetStarted) {
                            Text("Create my first goal")
                                .font(.headline)
                                .foregroundStyle(page.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        Button("Maybe later", action: onSkip)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
                } else {
                    Button(action: onNext) {
                        Image(systemName: "arrow.right")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(page.background)
                            .frame(width: 60, height: 60)
                            .background(.white, in: Circle())
                    }
                    .accessibilityLabel("Next")
                    .padding(.bottom, 52)
                }
            }
        }
    }
}

// MARK: - Page model

private struct OnboardingPage {
    let symbol: String
    let headline: String
    let body: String
    let background: Color

    static let all: [OnboardingPage] = [
        .init(
            symbol: "leaf.fill",
            headline: "Welcome to Tiller",
            body: "A productivity tracker disguised as a farming game. Your habits and goals literally grow crops.",
            background: .green
        ),
        .init(
            symbol: "target",
            headline: "Goals become plots",
            body: "Every goal you create claims a patch of land on your farm. More goals, more growing.",
            background: Color(red: 0.18, green: 0.58, blue: 0.55)
        ),
        .init(
            symbol: "checklist",
            headline: "Tasks and habits feed your farm",
            body: "Complete them to pump health into the matching plot. Neglect means decay — and eventually death.",
            background: Color(red: 0.20, green: 0.40, blue: 0.70)
        ),
        .init(
            symbol: "scroll.fill",
            headline: "Quests pay gold",
            body: "Three daily quests and a weekly bonus auto-claim when you hit their goal. Streak bonuses stack up fast.",
            background: Color(red: 0.80, green: 0.45, blue: 0.10)
        ),
        .init(
            symbol: "dollarsign.circle.fill",
            headline: "Spend gold wisely",
            body: "Unlock more farm plots to pursue more goals, or buy cosmetics to personalize your farmer.",
            background: Color(red: 0.50, green: 0.20, blue: 0.70)
        ),
        .init(
            symbol: "arrow.right.circle.fill",
            headline: "Ready to farm?",
            body: "Create your first goal to plant a plot and start growing. Your farm is waiting.",
            background: Color(red: 0.25, green: 0.35, blue: 0.65)
        ),
    ]
}

#Preview {
    OnboardingView(onComplete: { _ in })
}

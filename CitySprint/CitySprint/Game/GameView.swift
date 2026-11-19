import SpriteKit
import SwiftUI
import CitySprintCore

struct GameView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GameViewModel
    let onExit: (_ next: (CityID, Int)?) -> Void

    init(launch: GameLaunch, app: AppModel, onExit: @escaping ((CityID, Int)?) -> Void) {
        _model = State(initialValue: GameViewModel(level: launch.level, app: app))
        self.onExit = onExit
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: model.scene, isPaused: model.phase != .playing || model.showTutorial,
                           preferredFramesPerSecond: 60,
                           options: [.ignoresSiblingOrder], debugOptions: [])
                    .ignoresSafeArea()
                    .onAppear { model.scene.safeInsets = geo.safeAreaInsets.uiInsets }
                    .onChange(of: geo.safeAreaInsets) { _, insets in model.scene.safeInsets = insets.uiInsets }
                    .accessibilityLabel(Text("Game. Swipe left or right to change lanes, tap to sprint, swipe down to brake."))
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityIdentifier("gameView")

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            model.pause()
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.title3.weight(.bold))
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.4), in: Circle())
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(Text("Pause"))
                        .accessibilityIdentifier("pauseButton")
                        .padding(.trailing, 12)
                        .padding(.top, 52)
                    }
                    Spacer()
                    controlsForAssistiveTech
                }

                if model.showTutorial {
                    TutorialCard { model.dismissTutorial() }
                        .transition(.opacity)
                }

                switch model.phase {
                case .playing:
                    EmptyView()
                case .paused:
                    PauseOverlay(title: model.title,
                                 onResume: model.resume,
                                 onRestart: model.retry,
                                 onQuit: { onExit(nil) })
                case .finished(let result, let outcome):
                    ResultsView(result: result, outcome: outcome, attempts: model.attempts,
                                hasNext: model.nextLevel() != nil,
                                onRetry: model.retry,
                                onNext: { onExit(model.nextLevel()) },
                                onExit: { onExit(nil) })
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
    }

    /// On-screen buttons shown only when VoiceOver or Switch Control is
    /// running, so the game can be played without gestures.
    @ViewBuilder
    private var controlsForAssistiveTech: some View {
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning {
            HStack(spacing: 12) {
                controlButton("arrow.left", "Move left", .moveLeft)
                controlButton("arrow.down", "Brake", .brake)
                controlButton("bolt.fill", "Sprint", .sprint)
                controlButton("arrow.right", "Move right", .moveRight)
            }
            .padding(.bottom, 40)
        }
    }

    private func controlButton(_ symbol: String, _ label: LocalizedStringKey, _ command: PlayerCommand) -> some View {
        Button {
            model.scene.perform(command)
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .frame(width: 60, height: 60)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(Text(label))
    }
}

private extension EdgeInsets {
    var uiInsets: UIEdgeInsets { UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing) }
}

struct TutorialCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("How to ride")
                .font(.title2.bold())
            Label("Swipe left or right to change lanes", systemImage: "arrow.left.and.right")
            Label("Tap to sprint (uses stamina)", systemImage: "bolt.fill")
            Label("Swipe down to brake — stop for red lights", systemImage: "arrow.down")
            Label("Tuck in behind a bus, then pull out for a slingshot", systemImage: "wind")
            Button("Let's ride", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("tutorialDismiss")
        }
        .font(.body)
        .multilineTextAlignment(.leading)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

struct PauseOverlay: View {
    let title: String
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused").font(.largeTitle.bold())
                Text(title).font(.headline).foregroundStyle(.secondary)
                Button(action: onResume) { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("resumeButton")
                Button(action: onRestart) { Label("Restart", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("restartButton")
                Button(role: .destructive, action: onQuit) { Label("Quit to map", systemImage: "map").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("quitButton")
            }
            .controlSize(.large)
            .padding(28)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
    }
}

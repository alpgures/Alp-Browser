//
//  QuitConfirmationView.swift
//  Alp Browser
//
//  The in-window "Quit Alp Browser?" card shown on the first ⌘Q. Original Alp Browser design.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

struct QuitConfirmationView: View {
    @EnvironmentObject var browserState: BrowserState

    private var detail: String {
        let (tabs, spaces) = browserState.quitSummary
        guard tabs > 0 else { return "Your spaces and tabs are saved and will be here when you come back." }
        let tabText = tabs == 1 ? "1 open tab" : "\(tabs) open tabs"
        let spaceText = spaces == 1 ? "1 space" : "\(spaces) spaces"
        return "\(tabText) across \(spaceText) will be saved and restored next time you open Alp Browser."
    }

    private func cancel() {
        withAnimation(.easeOut(duration: 0.15)) { browserState.isQuitConfirmationPresented = false }
    }

    private func confirm() {
        // The flag stays up on purpose: applicationShouldTerminate sees it and lets the quit through.
        NSApp.terminate(nil)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { cancel() }

            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text("Quit Alp Browser?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: cancel) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(action: confirm) {
                        Text("Quit").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(browserState.activeTheme.effectiveAccentColor)
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)

                Text("Press ⌘Q again to quit")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(22)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            )
            .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
        }
    }
}

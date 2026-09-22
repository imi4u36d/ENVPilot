import ENVPilotCore
import Foundation
import SwiftUI

@MainActor
final class EnvironmentCheckStore: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var checks = EnvironmentSetupCheckKind.allCases.map(EnvironmentSetupCheckResult.pending)
    @Published private(set) var message: String?
    @Published private(set) var isChecking = false
    @Published private(set) var isRepairing = false

    private let runtimeStore: NodeRuntimeStore
    private let aiStore: AIEnvironmentStore
    private let service: EnvironmentSetupService

    init(
        runtimeStore: NodeRuntimeStore,
        aiStore: AIEnvironmentStore,
        service: EnvironmentSetupService = EnvironmentSetupService()
    ) {
        self.runtimeStore = runtimeStore
        self.aiStore = aiStore
        self.service = service
    }

    var isBusy: Bool {
        isChecking || isRepairing
    }

    var needsRepair: Bool {
        checks.contains { $0.status == .needsRepair || $0.status == .failed }
    }

    func present() {
        isPresented = true
        Task { await refresh() }
    }

    func dismiss() {
        guard !isBusy else {
            return
        }
        isPresented = false
    }

    func refresh() async {
        guard !isBusy else {
            return
        }
        isChecking = true
        message = nil
        checks = EnvironmentSetupCheckKind.allCases.map(EnvironmentSetupCheckResult.pending)

        await aiStore.refreshIfNeededAndWait()
        let statuses = aiStore.statuses
        let service = self.service
        let report = await Task.detached(priority: .userInitiated) {
            service.check(aiStatuses: statuses)
        }.value

        checks = report.checks
        message = report.message
        isChecking = false
    }

    func repair() async {
        guard !isBusy else {
            return
        }
        isRepairing = true
        message = nil

        let statuses = aiStore.statuses
        let service = self.service
        let report = await Task.detached(priority: .userInitiated) {
            service.repair(aiStatuses: statuses)
        }.value

        await runtimeStore.refresh()
        await aiStore.refresh()
        checks = report.checks
        message = report.message
        isRepairing = false
    }
}

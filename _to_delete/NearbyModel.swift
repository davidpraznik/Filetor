import SwiftUI
import Observation

/// UI side of Send to Mac: polls the network service and shows progress in the transfer indicator.
@Observable
final class NearbyModel {
    var peers: [NearbyPeer] = []
    var incoming: IncomingRequest?
    var error: String?

    private let service = NearbyService()
    private var jobs: [UInt64: TransferJob] = [:]
    private var started = false

    func start(transfers: TransferManager) {
        guard !started else { return }
        started = true
        applyIdentity()
        service.start()
        error = service.startError
        Task { @MainActor [weak self] in
            while let self {
                self.poll(transfers)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func applyIdentity() {
        let d = UserDefaults.standard
        let typed = (d.string(forKey: "deviceName") ?? "").trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty ? (Host.current().localizedName ?? "Mac") : typed
        let folder = d.string(forKey: "receiveFolder") ?? (NSHomeDirectory() + "/Downloads")
        service.shared.setIdentity(name: name, receiveDir: URL(filePath: folder), receiving: d.bool(forKey: "receiveFromMacs"))
    }

    private func poll(_ transfers: TransferManager) {
        applyIdentity()
        peers = service.shared.peers()
        if incoming == nil { incoming = service.shared.firstIncoming() }

        for t in service.shared.transfers() {
            let job: TransferJob
            if let existing = jobs[t.id] {
                job = existing
            } else {
                job = TransferJob(title: t.label)
                jobs[t.id] = job
                transfers.jobs.append(job)
            }
            job.fraction = t.total > 0 ? min(Double(t.done) / Double(t.total), 1) : (t.finished ? 1 : 0)
            if t.finished && !job.isFinished {
                job.isFinished = true
                job.fraction = 1
                if let e = t.error { transfers.onError?(e) }
                transfers.onFinished?()
                service.shared.removeTransfer(t.id)
                jobs[t.id] = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    transfers.jobs.removeAll { $0.id == job.id }
                }
            }
        }
    }

    func answer(_ accept: Bool) {
        incoming?.answer(accept)
        incoming = nil
    }

    func send(to peer: NearbyPeer, urls: [URL]) {
        guard !urls.isEmpty else { return }
        service.send(to: peer, urls: urls)
    }
}

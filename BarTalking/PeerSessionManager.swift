import Foundation
import MultipeerConnectivity

@MainActor
final class PeerSessionManager {

    static let shared = PeerSessionManager()

    var onPeerFound: ((MCPeerID, [String: String]?) -> Void)?
    var onPeerLost: ((MCPeerID) -> Void)?
    var onInvitationReceived: ((MCPeerID, @escaping (Bool) -> Void) -> Void)?
    var onProgressUpdate: ((ProgressSnapshot, String, Set<ObjectIdentifier>) -> Void)?

    private init() {}

    func peerFound(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        onPeerFound?(peerID, discoveryInfo)
    }

    func peerLost(_ peerID: MCPeerID) {
        onPeerLost?(peerID)
    }

    func browserFailed(_ error: Error) {}

    func receivedInvitation(from peerID: MCPeerID, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void, session: MCSession?) {
        onInvitationReceived?(peerID) { accepted in
            invitationHandler(accepted, accepted ? session : nil)
        }
    }

    func notifyProgress(snapshot: ProgressSnapshot, filename: String, peers: Set<ObjectIdentifier>) {
        Task { @MainActor in
            onProgressUpdate?(snapshot, filename, peers)
        }
    }
}
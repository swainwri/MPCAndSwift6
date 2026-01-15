import Foundation
import MultipeerConnectivity

actor MPCActor {
    // MARK: - Properties
    private(set) var session: MCSession?
    private(set) var advertiser: MCNearbyServiceAdvertiser?
    private(set) var browser: MCNearbyServiceBrowser?

    let myPeerID: MCPeerID
    let serviceType: String

    // MARK: - Initialization
    init(myPeerID: MCPeerID, serviceType: String) {
        self.myPeerID = myPeerID
        self.serviceType = serviceType
    }

    // MARK: - Setup
    func setupSession() {
        guard session == nil else { return }
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session = s
    }

    func setupAdvertiser() {
        guard advertiser == nil else { return }
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
    }

    func setupBrowser() {
        guard browser == nil else { return }
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    }

    // MARK: - Peer Events
    func foundPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        PeerSessionManager.shared.peerFound(peerID, discoveryInfo: discoveryInfo)
    }

    func lostPeer(_ peerID: MCPeerID) {
        PeerSessionManager.shared.peerLost(peerID)
    }

    func browserFailed(_ error: Error) {
        PeerSessionManager.shared.browserFailed(error)
    }

    func handleInvitation(from peerID: MCPeerID, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        PeerSessionManager.shared.receivedInvitation(from: peerID, context: context, invitationHandler: invitationHandler, session: session)
    }

    func updateProgress(fractionCompleted: Double, filename: String, peers: Set<ObjectIdentifier>) {
        let snapshot = ProgressSnapshot(fractionCompleted: fractionCompleted,
                                        completedUnitCount: 0,
                                        totalUnitCount: 1)
        PeerSessionManager.shared.notifyProgress(snapshot: snapshot, filename: filename, peers: peers)
    }
}

// MARK: - Progress Snapshot
struct ProgressSnapshot {
    let fractionCompleted: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64
}
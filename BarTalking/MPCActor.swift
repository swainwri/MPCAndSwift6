//
//  MPCActor.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//

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

    func start(session: MCSession, advertiser: MCNearbyServiceAdvertiser, browser: MCNearbyServiceBrowser) {
        guard self.session == nil else { return }

        self.session = session
        self.advertiser = advertiser
        self.browser = browser

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser?.stopAdvertisingPeer();
        browser?.stopBrowsingForPeers();
        session?.disconnect()
    }
    
    // MARK: - Shutdown
    
    func shutdown() {
        // Stop discovery first
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        // Disconnect session
        session?.disconnect()
        // Break delegate retain cycles
        session?.delegate = nil
        browser?.delegate = nil
        advertiser?.delegate = nil
        // Release everything
        session = nil
        browser = nil
        advertiser = nil
    }

    // MARK: - Peer Events
    
    func foundPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        Task { @MainActor in
            await PeerSessionManager.shared.peerFound(peerID, discoveryInfo: discoveryInfo)
        }
    }

    func lostPeer(_ peerID: MCPeerID) {
        Task { @MainActor in
            await PeerSessionManager.shared.peerLost(peerID)
        }
    }

    func browserFailed(_ error: Error) {
        Task { @MainActor in
            await PeerSessionManager.shared.browserFailed(error)
        }
    }

    func handleInvitation(from peerID: MCPeerID, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            await PeerSessionManager.shared.receivedInvitation(from: peerID, context: context, invitationHandler: invitationHandler, session: session)
        }
    }

    func updateProgress(fractionCompleted: Double, filename: String, peers: Set<ObjectIdentifier>) {
        let snapshot = ProgressSnapshot(fractionCompleted: fractionCompleted, completedUnitCount: 0, totalUnitCount: 1)
        Task { @MainActor in
            await PeerSessionManager.shared.notifyProgress(snapshot: snapshot, filename: filename, peers: peers)
        }
    }
    
    func invitePeer(_ peer: MCPeerID) {
        guard let session, let browser else { return }

        browser.invitePeer(peer, to: session, withContext: nil, timeout: 20)
        print("MPC Invitation sent to \(peer.displayName)")
    }
    
    func peerStateChanged(_ peerID: MCPeerID, state: MCSessionState) {
        Task { @MainActor in
            PeerSessionManager.shared.peerStateChanged(peerID, state: state)
        }
    }
    
    func receivedFile(url: URL, from peerID: MCPeerID, error: Error?) async {
        await PeerSessionManager.shared.fileReceived(url: url, from: peerID, error: error)
    }
    
    func receivedMessage(_ data: Data, from peerID: MCPeerID) async {
        await PeerSessionManager.shared.messageReceived(data, from: peerID)
    }
    
    // MARK: - Send message (small data)
    func sendMessage(_ data: Data, to peer: MCPeerID) {
        guard let session, session.connectedPeers.contains(peer) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    // MARK: - Send file (resource)
    
    func sendFile(at url: URL, to peer: MCPeerID) {
        guard let session, session.connectedPeers.contains(peer) else { return }
        if let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer, withCompletionHandler: { /*[weak self]*/ error in
            if let error {
                print("MPC send file error:", error)
            } else {
                print("MPC file sent to \(peer.displayName)")
            }
            Task {
                await PeerSessionManager.shared.resourceSendCompleted(to: peer, error: error)
            }
        }) {
            Task {
                await PeerSessionManager.shared.resourceSendStarted(peer: peer, progress: progress)
            }
        }
    }
    
    func sendAck(to peer: MCPeerID) {
        guard let session else { return }

        let ack = Data("ACK".utf8)
        try? session.send(ack, toPeers: [peer], with: .reliable)
    }

}

// MARK: - Progress Snapshot

struct ProgressSnapshot {
    let fractionCompleted: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64
}

//
//  MCSessionDelegateBridge.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//


import Foundation
import MultipeerConnectivity

final class MCSessionDelegateBridge: NSObject, MCSessionDelegate {
    
    unowned let actor: MPCActor

    init(actor: MPCActor) {
        self.actor = actor
        super.init()
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        actor.peerStateChangedFromDelegate(peerID, state: state)
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
//        actor.receivedMessage(stream, from: peerID)
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        actor.receivedMessageFromDelegate(data, from: peerID)
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: ProgressSnapshot) {
        let objectIdentifier = ObjectIdentifier(peerID)
        Task { @MainActor in
            await actor.updateProgress(fractionCompleted: progress.fractionCompleted, filename: resourceName, peers: [objectIdentifier])
        }
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let url = localURL {
            actor.receivedFileFromDelegate(url: url, from: peerID, error: error)
        }
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
}


final class MPCAdvertiserDelegateBridge: NSObject, MCNearbyServiceAdvertiserDelegate {
    
    nonisolated(unsafe) var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?
    private let session: MCSession
    private weak var manager: PeerSessionManager?

    init(session: MCSession, manager: PeerSessionManager) {
        self.session = session
        self.manager = manager
        super.init()
    }

    @MainActor
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Capture everything synchronously
        guard let manager = self.manager,
                  let session = manager.session
            else {
                print("❌ NO SESSION AVAILABLE – rejecting invite")
                invitationHandler(false, nil)
                return
            }

            print("📨 INVITE RECEIVED from:", peerID.displayName)
            print("📦 SESSION USED FOR INVITE:", ObjectIdentifier(session))

            // ✅ THIS MUST BE THE SAME SESSION AS start()
//            invitationHandler(true, session)

            Task { @MainActor in
                if let snapshot = await manager.mpcActorSnapshot(for: peerID) {
                    manager.invitationReceived(from: snapshot) { accept in
                        invitationHandler(accept, accept ? session : nil)
                    }
                }
            }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("Failed to advertise: \(error.localizedDescription)")
        }
    }
    
    func resolveInvitation(accept: Bool) {
        if let session = self.manager?.session {
            guard let handler = pendingInvitationHandler else { return }
            
            handler(accept, accept ? session : nil)
            pendingInvitationHandler = nil
        }
    }
}


final class MPCBrowserDelegateBridge: NSObject, MCNearbyServiceBrowserDelegate {
    unowned let actor: MPCActor

    init(actor: MPCActor) {
        self.actor = actor
        super.init()
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("FOUND PEER:", peerID.displayName)
        actor.foundPeerFromDelegate(peerID: peerID, discoveryInfo: info)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        actor.lostPeerFromDelegate(peerID: peerID)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            await actor.browserFailed(error)
        }
    }
}

//
//  MCSessionDelegateBridge.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//


import Foundation
import MultipeerConnectivity

@MainActor
final class MCSessionDelegateBridge: NSObject, MCSessionDelegate {
    unowned let actor: MPCActor

    init(actor: MPCActor) {
        self.actor = actor
        super.init()
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

@MainActor
final class MPCAdvertiserDelegateBridge: NSObject, MCNearbyServiceAdvertiserDelegate {
    unowned let actor: MPCActor

    init(actor: MPCActor) {
        self.actor = actor
        super.init()
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task {
            await actor.handleInvitation(from: peerID, context: context, invitationHandler: invitationHandler)
        }
    }
}

@MainActor
final class MPCBrowserDelegateBridge: NSObject, MCNearbyServiceBrowserDelegate {
    unowned let actor: MPCActor

    init(actor: MPCActor) {
        self.actor = actor
        super.init()
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task {
            await actor.foundPeer(peerID, discoveryInfo: info)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task {
            await actor.lostPeer(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task {
            await actor.browserFailed(error)
        }
    }
}
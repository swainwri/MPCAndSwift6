//
//  PeerSessionManager.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//

import Foundation
import MultipeerConnectivity

enum PeerConnectionState {
    case notConnected
    case connecting
    case connected
}

struct PeerUIState: Hashable {
    let peerID: MCPeerID
    var state: MCSessionState
}



@MainActor
final class PeerSessionManager {
    
    enum WireMessage {
        case message(String)
        case ack
    }

    static let shared = PeerSessionManager()
    
    // MARK: - Properties
    private(set) var peers: [MCPeerID] = []
    private(set) var administrator: MCPeerID?
    private(set) var peerStates: [MCPeerID: PeerConnectionState] = [:]
    private(set) var peersUIState: [PeerUIState] = []
    private(set) var progressByPeer: [MCPeerID: Progress] = [:]

    private var sessionBridge: MCSessionDelegateBridge?
    private var advertiserBridge: MPCAdvertiserDelegateBridge?
    private var browserBridge: MPCBrowserDelegateBridge?
    
    private var mpc: MPCActor?     // <-- Actor instance
    private var myPeerID: MCPeerID?
    private var hostName: String?
    private var serviceType: String?

    var onPeerFound: ((MCPeerID, [String: String]?) -> Void)?
    var onPeerLost: ((MCPeerID) -> Void)?
    var onInvitationReceived: ((MCPeerID, @escaping (Bool) -> Void) -> Void)?
    var onProgressUpdate: ((ProgressSnapshot, String, Set<ObjectIdentifier>) -> Void)?
    var onPeerStateChanged: (() -> Void)?
    var onPeersUpdated: (() -> Void)?
    var onMessageReceived: ((MCPeerID, String) -> Void)?
    var onFileReceived: ((MCPeerID, URL, String) -> Void)?
    var onSendResource: ((MCPeerID, Progress?) -> Void)?
    
    private init() {}
    
    func setup() {
        let name = UIDevice.current.name
        self.hostName = name
        let peerID = MCPeerID(displayName: PeerSessionManager.makeSafeDeviceName(name))

        let defaultServiceType: String = {
            let raw = (Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String])?.first ?? "_fallback._tcp"
            let trimmed = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .components(separatedBy: ".")
                .first ?? "fallback"
            return trimmed.lowercased()
        }()
        self.serviceType = defaultServiceType
        self.myPeerID = peerID
    }
    
    func start() {
        if let myPeerID,
           let serviceType {
            self.mpc = MPCActor(myPeerID: myPeerID, serviceType: serviceType)
            if let mpc {
                let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
                let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
                let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
                
                let sessionBridge = MCSessionDelegateBridge(actor: mpc)
                let advertiserBridge = MPCAdvertiserDelegateBridge(actor: mpc)
                let browserBridge = MPCBrowserDelegateBridge(actor: mpc)
                
                session.delegate = sessionBridge
                advertiser.delegate = advertiserBridge
                browser.delegate = browserBridge
                
                self.sessionBridge = sessionBridge
                self.advertiserBridge = advertiserBridge
                self.browserBridge = browserBridge
                
                Task {
                    await mpc.start(session: session, advertiser: advertiser, browser: browser)
                }
            }
        }
    }
    
    func reset() async {
        if let mpc {
            await mpc.shutdown()
        }
        start()
    }
    
    // MARK: - Peer Events
        
    func peerFound(_ peerID: MCPeerID, discoveryInfo: [String: String]?) async {
        if !peers.contains(peerID) {
            peers.append(peerID)
            onPeerFound?(peerID, discoveryInfo)
        }
    }

    func peerLost(_ peerID: MCPeerID) async {
        if let idx = peers.firstIndex(of: peerID) {
            peers.remove(at: idx)
            // if lost admin, clear
            if peerID == administrator {
                administrator = nil
            }
            onPeerLost?(peerID)
        }
    }

    func browserFailed(_ error: Error) async {}

    func receivedInvitation(from peerID: MCPeerID, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void, session: MCSession?) async {
        print("📨 Invitation received from \(peerID.displayName)")
        onInvitationReceived?(peerID) { accepted in
            invitationHandler(accepted, accepted ? session : nil)
        }
    }

    func notifyProgress(snapshot: ProgressSnapshot, filename: String, peers: Set<ObjectIdentifier>) async {
        Task { @MainActor in
            onProgressUpdate?(snapshot, filename, peers)
        }
    }
    
    // MARK: - Message
    func sendTestMessage(to peer: MCPeerID) {
        let text = "Hello from \(UIDevice.current.name)"
        let data = Data(text.utf8)

        Task {
            await mpc?.sendMessage(data, to: peer)
        }
    }
    
    // MARK: - File
    func sendTestFile(to peer: MCPeerID) {
        guard let url = Bundle.main.url(forResource: "test", withExtension: "txt") else {
            print("Test file missing")
            return
        }
        Task {
            await mpc?.sendFile(at: url, to: peer)
        }
    }    
    
    func fileReceived(url: URL, from peer: MCPeerID, error: Error?) {
        Task { @MainActor in
            if let error {
                print("File receive error:", error)
            } else {
                print("File received from \(peer.displayName): \(url.lastPathComponent)")
                onFileReceived?(peer, url, "test.txt")
            }
        }
        sendAck(to: peer)
    }
        
    func messageReceived(_ data: Data, from peer: MCPeerID) {
        let text = String(decoding: data, as: UTF8.self)
        Task { @MainActor in
            print("Message received from \(peer.displayName): \(text)")
        }
        switch parse(text) {
            case .ack:
                print("ACK received from \(peer.displayName)")

            case .message(let body):
                print("Message received:", body)
                onMessageReceived?(peer, body)
                sendAck(to: peer)
        }
    }
        
    private func sendAck(to peer: MCPeerID) {
        Task {
            await mpc?.sendAck(to: peer)
        }
    }
    
    // MARK: - Admin
    func assignAdministrator(_ peerID: MCPeerID) {
        if peers.contains(peerID) {
            administrator = peerID
        }
    }

    func clearAdministrator() {
        administrator = nil
    }
    
    // MARK: - Miscellaneous Utility Methods
    
    static func makeSafeDeviceName(_ rawName: String?) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces)
        if let safeName = rawName?
            .components(separatedBy: allowedCharacters.inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")
            .lowercased() {
            
            return safeName
        }
        else {
            return UUID().uuidString
        }
    }
    
    func parse(_ text: String) -> WireMessage {
        if text == "ACK" { return .ack }
        return .message(text)
    }
}

extension PeerSessionManager {
    
    func invite(peer: MCPeerID) async {
        guard let mpc, let _ = await mpc.session, let _ = await mpc.browser else { return }

        // Use MCNearbyServiceAdvertiser to send invitation
        //mpc.invitePeer(peer, to: session, withContext: nil, timeout: 20)
        print("PeerSession Manager Invitation sent to \(peer.displayName)")
        await mpc.invitePeer(peer)
    }
    
    func sendMessage(_ text: String, to peer: MCPeerID) async {
        guard let mpc, let session = await mpc.session else { return }
        let data = Data(text.utf8)
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        }
        catch {
            print("Failed to send message: \(error)")
        }
    }
    
    func receiveMessage(_ text: String, from peer: MCPeerID) {
        print("Message from \(peer.displayName): \(text)")
        onMessageReceived?(peer, text)
    }
    
    func sendFile(url: URL, to peer: MCPeerID) async {
        guard let mpc, let session = await mpc.session else { return }
        let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer) { [weak self] error in
            if let error = error {
                print("File send failed: \(error)")
            } else {
                print("File sent successfully to \(peer.displayName)")
            }
//            Task {
//                await self?.resourceSendCompleted(to: peer, error: error)
//            }
            self?.resourceSendCompleted(to: peer, error: error)
        }
        progressByPeer[peer] = progress
        onSendResource?(peer, progress)
    }
    
    func fileReceived(url: URL, from peer: MCPeerID) {
        print("Received file \(url.lastPathComponent) from \(peer.displayName)")
        onFileReceived?(peer, url, "test.txt")
    }
    
    @MainActor
    func peerStateChanged(_ peerID: MCPeerID, state: MCSessionState) {
        let mapped: PeerConnectionState
        switch state {
            case .connected:
                mapped = .connected
            case .connecting:
                mapped = .connecting
            case .notConnected:
                mapped = .notConnected
            @unknown default:
                mapped = .notConnected
        }
        peerStates[peerID] = mapped
        onPeerStateChanged?()
        
        if let index = peersUIState.firstIndex(where: { $0.peerID == peerID }) {
            peersUIState[index].state = state
        } else {
            peersUIState.append(PeerUIState(peerID: peerID, state: state))
        }
        onPeersUpdated?()
    }
    
    func resourceSendStarted(peer: MCPeerID, progress: Progress) {
        progressByPeer[peer] = progress
        onSendResource?(peer, progress)
    }

    func resourceSendCompleted(to peer: MCPeerID, error: Error?) {
        progressByPeer[peer] = nil
        onSendResource?(peer, nil)
    }
    
}

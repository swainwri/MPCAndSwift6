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

struct PeerSnapshot: Sendable, Hashable {
    let id: UUID
    let displayName: String
}

struct PeerUIState: Hashable {
    let peerSnapshot: PeerSnapshot
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
    @MainActor
    private(set) var peers: [PeerSnapshot] = []
    
    private(set) var administrator: PeerSnapshot?
    private(set) var peerStates: [UUID: PeerConnectionState] = [:]
    private(set) var peersUIState: [PeerUIState] = []
    private(set) var progressByPeer: [UUID: Progress] = [:]
    private var pendingInvitationID: UUID?
    private var invitationHandlers: [UUID: (Bool, MCSession?) -> Void] = [:]
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var pendingInvitationRespond: ((Bool) -> Void)?
    
    private var sessionBridge: MCSessionDelegateBridge?
    private var advertiserBridge: MPCAdvertiserDelegateBridge?
    private var browserBridge: MPCBrowserDelegateBridge?
    
    var session: MCSession?   // ← REQUIRED
    private var mpc: MPCActor?     // <-- Actor instance
    private var myPeerID: MCPeerID?
    private var hostName: String?
    private var serviceType: String?

    var onPeerFound: ((PeerSnapshot, [String: String]?) -> Void)?
    var onPeerLost: ((PeerSnapshot) -> Void)?
    var onInvitationReceived: ((PeerSnapshot) -> Void)?
    var onProgressUpdate: ((ProgressSnapshot, String, Set<ObjectIdentifier>) -> Void)?
    var onPeerStateChanged: (() -> Void)?
    var onPeersUpdated: (() -> Void)?
    var onMessageReceived: ((PeerSnapshot, String) -> Void)?
    var onFileReceived: ((PeerSnapshot, URL, String) -> Void)?
    var onSendResource: ((PeerSnapshot, Progress?) -> Void)?
    
    private init() {}
    
    func setup() async {
        let name = UIDevice.current.name
        self.hostName = name
        let peerID = MCPeerID(displayName: PeerSessionManager.makeSafeDeviceName(name))

        let defaultServiceType: String = {
            let raw = (Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String])?.first ?? "_fallback._tcp"
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "_")).components(separatedBy: ".").first ?? "fallback"
            return trimmed.lowercased()
        }()
        self.serviceType = defaultServiceType
        self.myPeerID = peerID
        print(self.serviceType ?? "Unknown")
    }
    
    func start() async {
        if let myPeerID,
           let serviceType {
            
            // ✅ CREATE SESSION HERE
            let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            self.session = session
            print("SESSION CREATED:", ObjectIdentifier(session))
            
            let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
            self.advertiser = advertiser
            let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            self.browser = browser
            
            // Actor does NOT create session
            let mpc = MPCActor(myPeerID: myPeerID, serviceType: serviceType)
            self.mpc = mpc
            await mpc.setSession(session)
            await mpc.setEventHandler { [weak self] (event: MPCEvent) in
                guard let self else { return }
                Task { @MainActor in
                    self.handle(event)
                }
            }
            
            let sessionBridge = MCSessionDelegateBridge(actor: mpc)
            self.sessionBridge = sessionBridge
            let advertiserBridge = MPCAdvertiserDelegateBridge(session: session, manager: self)
            self.advertiserBridge = advertiserBridge
            let browserBridge = MPCBrowserDelegateBridge(actor: mpc)
            self.browserBridge = browserBridge
            
            session.delegate = sessionBridge
            advertiser.delegate = advertiserBridge
            browser.delegate = browserBridge
            
            bindActor()
//            Task {
//                await mpc.start(session: session, advertiser: advertiser, browser: browser)
//            }
            advertiser.startAdvertisingPeer()
            browser.startBrowsingForPeers()
        }
        if let session {
            print("Manager session:", ObjectIdentifier(session))
        }
        Task {
            if let session = await self.mpc?.session {
                print("Actor session:", ObjectIdentifier(session))
            }
        }
        print("Peers:", peers.map(\.id))
        print("States:", peerStates)
    }
    
    func reset() async {
        peers.removeAll()
        peerStates.removeAll()
        peersUIState.removeAll()
        progressByPeer.removeAll()
        invitationHandlers.removeAll()

        shutdown()
        await start()
    }
    
    func shutdown() {
        // Stop discovery first
        self.browser?.stopBrowsingForPeers()
        self.advertiser?.stopAdvertisingPeer()
        // Disconnect session
        self.session?.disconnect()
    }
    
    // MARK: - Handler Events
    
    @MainActor
    private func handle(_ event: MPCEvent) {
        switch event {
            case .peersChanged(let snapshots):
                self.peers = snapshots
                self.onPeersUpdated?()

            case .stateChanged(let uuid, let state):
                self.peerStates[uuid] = state
                self.onPeerStateChanged?()
        }
    }
    
    // MARK: - Peer Events
        
    func peerFound(_ peerSnapShot: PeerSnapshot, discoveryInfo: [String: String]?) async {
        if !containsPeer(id: peerSnapShot.id) {
            peers.append(peerSnapShot)
            onPeerFound?(peerSnapShot, discoveryInfo)
        }
    }

    func peerLost(_ peerSnapShot: PeerSnapshot) async {
        if let idx = peers.map({ $0.id }).firstIndex(of: peerSnapShot.id) {
            peers.remove(at: idx)
            // if lost admin, clear
            if peerSnapShot == administrator {
                administrator = nil
            }
            onPeerLost?(peerSnapShot)
        }
    }

    func browserFailed(_ error: Error) async {}

    func receivedInvitation(from peerSnapshot: PeerSnapshot, context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void, session: MCSession?) async {
        print("📨 Invitation received from \(peerSnapshot.displayName)")
        onInvitationReceived?(peerSnapshot) /*{ accepted in
            invitationHandler(accepted, accepted ? session : nil)
        }*/
    }

    func notifyProgress(snapshot: ProgressSnapshot, filename: String, peers: Set<ObjectIdentifier>) async {
        Task { @MainActor in
            onProgressUpdate?(snapshot, filename, peers)
        }
    }
    
    // MARK: - Message
    func sendTestMessage(to peerSnapshot: PeerSnapshot) {
        let text = "Hello from \(UIDevice.current.name)"
        let data = Data(text.utf8)

        Task {
            try await mpc?.sendMessage(data, to: peerSnapshot)
        }
    }
    
    // MARK: - File
    func sendTestFile(to peerSnapshot: PeerSnapshot) {
        guard let url = Bundle.main.url(forResource: "test", withExtension: "txt") else {
            print("Test file missing")
            return
        }
        Task {
            await mpc?.sendFile(at: url, to: peerSnapshot)
        }
    }    
    
    func fileReceived(url: URL, from peerSnapshot: PeerSnapshot, error: Error?) {
        Task { @MainActor in
            if let error {
                print("File receive error:", error)
            } else {
                print("File received from \(peerSnapshot.displayName): \(url.lastPathComponent)")
                onFileReceived?(peerSnapshot, url, "test.txt")
            }
        }
        sendAck(to: peerSnapshot)
    }
        
    func messageReceived(_ data: Data, from peerSnapshot: PeerSnapshot) {
        let text = String(decoding: data, as: UTF8.self)
        Task { @MainActor in
            print("Message received from \(peerSnapshot.displayName): \(text)")
        }
        switch parse(text) {
            case .ack:
                print("ACK received from \(peerSnapshot.displayName)")

            case .message(let body):
                print("Message received:", body)
                onMessageReceived?(peerSnapshot, body)
                sendAck(to: peerSnapshot)
        }
    }
        
    private func sendAck(to peerSnapshot: PeerSnapshot) {
        Task {
            await mpc?.sendACK(to: peerSnapshot)
        }
    }
    
    // MARK: - Admin
    func assignAdministrator(_ peerSnapshot: PeerSnapshot) {
        if peers.contains(peerSnapshot) {
            administrator = peerSnapshot
        }
    }

    func clearAdministrator() {
        administrator = nil
    }
    
    // MARK: - Invitations
    
    func registerInvitation(id: UUID, handler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandlers[id] = handler
    }

//    func resolveInvitation(id: UUID, accept: Bool) {
//        guard let handler = invitationHandlers.removeValue(forKey: id) else { return }
//        handler(accept, accept ? session : nil)
//    }
    
    func invitationReceived(from peer: PeerSnapshot, respond: @escaping (Bool) -> Void) {
        pendingInvitationRespond = respond
        onInvitationReceived?(peer)
    }

    func acceptInvitation(_ accept: Bool) {
        pendingInvitationRespond?(accept)
        pendingInvitationRespond = nil
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
    
    private func containsPeer(id: UUID) -> Bool {
        peers.contains { $0.id == id }
    }
    
    func mpcActorSnapshot(for peerID: MCPeerID) async -> PeerSnapshot? {
        return await mpc?.didDiscoverPeer(peerID)
    }
    
}

// MARK:- Extensions

extension PeerSessionManager {
    
    @MainActor
    func bindActor() {
        Task {
            await self.mpc?.setOnCommand { [weak self] command in
                Task { @MainActor in
                    self?.handle(command)
                }
            }
        }
    }
    
    @MainActor
    private func handle(_ command: MPCActor.Command) {
        guard let session else { return }

        switch command {
            case .invite(let peerID):
                browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
                print("PeerSession Manager Invitation sent to \(peerID.displayName) through onCommand handle from MPCActor.")

            case .sendData(let peerID, let data):
                guard session.connectedPeers.contains(peerID) else { return }
                try? session.send(data, toPeers: [peerID], with: .reliable)
                print("PeerSession Manager sends message to \(peerID.displayName) through onCommand handle from MPCActor.")
                
            case .sendFile(let peerID, let snapshot, let url):
                if let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peerID, withCompletionHandler: { [weak self] error in
                    print("PeerSession Manager sends file to \(peerID.displayName) through onCommand handle from MPCActor.")
                    Task {
                        await self?.mpc?.resourceSendCompleted(snapshot.id, error)
                    }
                }) {
                    onSendResource?(snapshot, progress)
                }
        }
    }
 
    func invite(peerSnapshot: PeerSnapshot) async {
        if let mpc {
            print("PeerSession Manager Invitation sent to \(peerSnapshot.displayName)")
            await mpc.invitePeer(peerSnapshot)
        }
    }
    
    @MainActor
    func invitationReceived(from peerSnapshot: PeerSnapshot, invitationID: UUID)/*, respond: @escaping (Bool) -> Void)*/ {
        pendingInvitationID = invitationID
        onInvitationReceived?(peerSnapshot)//, respond)
    }
    
    func sendMessage(_ text: String, to peerSnapshot: PeerSnapshot) async {
        if let mpc {
            let data = Data(text.utf8)
            do {
                try await mpc.sendMessage(data, to: peerSnapshot)
            }
            catch {
                print("Failed to send message:", error)
            }
        }
    }
    
    func receiveMessage(_ text: String, from peerSnapshot: PeerSnapshot) {
        print("Message from \(peerSnapshot.displayName): \(text)")
        onMessageReceived?(peerSnapshot, text)
    }
    
    func sendFile(url: URL, to peerSnapshot: PeerSnapshot) async {
        if let mpc {
            await mpc.sendFile(at: url, to: peerSnapshot)
        }
//        let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer) { [weak self] error in
//            if let error = error {
//                print("File send failed: \(error)")
//            } else {
//                print("File sent successfully to \(peerSnapshot.displayName)")
//            }
////            Task {
////                await self?.resourceSendCompleted(to: peer, error: error)
////            }
//            self?.resourceSendCompleted(to: peerSnapshot, error: error)
//        }
//        progressByPeer[peerSnapshot.id] = progress
//        onSendResource?(peerSnapshot, progress)
    }
    
    func fileReceived(url: URL, from peerSnapshot: PeerSnapshot) {
        print("Received file \(url.lastPathComponent) from \(peerSnapshot.displayName)")
        onFileReceived?(peerSnapshot, url, "test.txt")
    }
    
    func resourceSendStarted(peerSnapshot: PeerSnapshot, progress: Progress) {
        progressByPeer[peerSnapshot.id] = progress
        onSendResource?(peerSnapshot, progress)
    }

    func resourceSendCompleted(to peerSnapshot: PeerSnapshot, error: Error?) {
        progressByPeer[peerSnapshot.id] = nil
        onSendResource?(peerSnapshot, nil)
    }
    
}

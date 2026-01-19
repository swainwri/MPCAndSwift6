//
//  MPCActor.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//

import Foundation
import MultipeerConnectivity

enum MPCEvent {
    case peersChanged(peers: [PeerSnapshot])
    case stateChanged(uuid: UUID, state:PeerConnectionState)
}

actor MPCActor {
    
    private struct PeerRecord {
        let id: UUID
        let peerID: MCPeerID
        var snapshot: PeerSnapshot
    }
    
    enum Command {
        case invite(peerID: MCPeerID)
        case sendData(peerID: MCPeerID, data: Data)
        case sendFile(peerID: MCPeerID, snapshot: PeerSnapshot, url: URL)
    }
    
    // MARK: - Properties

    private let myPeerID: MCPeerID
    private let serviceType: String
    
    /*private*/ var session: MCSession?
    private var peersByID: [UUID: PeerRecord] = [:]
    private var peerIDByUUID: [UUID: MCPeerID] = [:]
    private var uuidByPeerID: [MCPeerID: UUID] = [:]
    private var invitationHandlers: [UUID: (Bool) -> Void] = [:]
    private var commandHandler: (@Sendable (Command) -> Void)?
    private var eventHandler: (@Sendable (MPCEvent) -> Void)?

    var onSendResource: ((UUID, Progress) -> Void)?
    var onResourceSendCompleted: ((UUID, Error?) -> Void)?
    var onCommand: (@Sendable (Command) -> Void)?

    // MARK: - Initialization

    init(myPeerID: MCPeerID, serviceType: String) {
        self.myPeerID = myPeerID
        self.serviceType = serviceType
    }
        
    func setSession(_ session: MCSession) {
        self.session = session
    }
    
    func didDiscoverPeer(_ peerID: MCPeerID) -> PeerSnapshot {
        if let uuid = uuidByPeerID[peerID],
           let snapshot = peersByID[uuid]?.snapshot {
            return snapshot
        }

        let uuid = UUID()
        let snapshot = PeerSnapshot(id: uuid, displayName: peerID.displayName)
        let record = PeerRecord(id: uuid, peerID: peerID, snapshot: snapshot)

        uuidByPeerID[peerID] = uuid
        peerIDByUUID[uuid] = peerID
        peersByID[uuid] = record

        emit(.peersChanged(peers: peersByID.values.map { $0.snapshot }))

        return snapshot
    }
    
    func didLosePeer(_ peerID: MCPeerID) {
        if let uuid = uuidByPeerID.removeValue(forKey: peerID),
           let _ = peersByID.removeValue(forKey: uuid) {
            peerIDByUUID.removeValue(forKey: uuid)
            emit(.peersChanged(peers: peersByID.values.map { $0.snapshot }))
        }
    }

    func peerID(for snapshot: PeerSnapshot) -> MCPeerID? {
        peerIDByUUID[snapshot.id]
    }
    
    func setOnCommand(_ handler: @Sendable @escaping (Command) -> Void) {
        self.onCommand = handler
    }
    
    // MARK: - Event & Command Handling
    
    func setEventHandler(_ handler: @escaping @Sendable (MPCEvent) -> Void) {
        self.eventHandler = handler
    }
    
    func setCommandHandler(_ handler: @escaping @Sendable (Command) -> Void) {
        self.commandHandler = handler
    }

    private func emit(_ event: MPCEvent) {
        eventHandler?(event)
    }

    // MARK: - Peer Events
    
    nonisolated func foundPeerFromDelegate(peerID: MCPeerID, discoveryInfo: [String: String]?) {
        // Immediately hop back into the actor
        Task {
            await self._foundPeer(peerID: peerID, discoveryInfo: discoveryInfo)
        }
    }

    private func _foundPeer(peerID: MCPeerID, discoveryInfo: [String: String]?) {
//        let snapshot = snapshot(for: peerID)
        let snapshot = didDiscoverPeer(peerID)
        print("\(snapshot.id): \(snapshot)")
        Task { @MainActor in
            await PeerSessionManager.shared.peerFound(snapshot, discoveryInfo: discoveryInfo)
        }
    }
    
    nonisolated func lostPeerFromDelegate(peerID: MCPeerID) {
        Task {
            await self._lostPeer(peerID: peerID)
        }
    }
    
    private func _lostPeer(peerID: MCPeerID) {
        let snapshot = snapshot(for: peerID)
        Task { @MainActor in
            await PeerSessionManager.shared.peerLost(snapshot)
        }
    }

    func browserFailed(_ error: Error) {
        Task { @MainActor in
            await PeerSessionManager.shared.browserFailed(error)
        }
    }
    
    func handleInvitation(peerID: MCPeerID, invitationID: UUID) {
        let snapshot = snapshot(for: peerID)

        Task { @MainActor in
            PeerSessionManager.shared.invitationReceived(from: snapshot, invitationID: invitationID)
        }
    }

    func updateProgress(fractionCompleted: Double, filename: String, peers: Set<ObjectIdentifier>) {
        let snapshot = ProgressSnapshot(fractionCompleted: fractionCompleted, completedUnitCount: 0, totalUnitCount: 1)
        Task { @MainActor in
            await PeerSessionManager.shared.notifyProgress(snapshot: snapshot, filename: filename, peers: peers)
        }
    }
    
    func invitePeer(_ snapshot: PeerSnapshot) {
        if let peerID = peerIDByUUID[snapshot.id] {
            onCommand?(.invite(peerID: peerID))
        }
    }
    
    nonisolated func peerStateChangedFromDelegate(_ peerID: MCPeerID, state: MCSessionState) {
        Task {
//            await self._peerStateChanged(peerID: peerID, state: state)
            await handlePeerStateChange(peerID: peerID, state: state)
        }
    }
    
//    private func _peerStateChanged(peerID: MCPeerID, state: MCSessionState) {
//        let snapshot = snapshot(for: peerID)
//        Task { @MainActor in
//            PeerSessionManager.shared.peerStateChanged(snapshot, state: state)
//        }
//    }
    
    private func handlePeerStateChange(peerID: MCPeerID, state: MCSessionState) {
        guard let uuid = uuidByPeerID[peerID] else {
            return   // peer not known yet — ignore safely
        }
        let mapped: PeerConnectionState
        switch state {
            case .connected:    mapped = .connected
            case .connecting:   mapped = .connecting
            case .notConnected: mapped = .notConnected
            @unknown default:   mapped = .notConnected
        }
        emit(.stateChanged(uuid: uuid, state: mapped))
    }
    
    nonisolated func receivedFileFromDelegate(url: URL, from peerID: MCPeerID, error: Error?) {
        Task {
            await self._receivedFile(url: url, from: peerID, error: error)
        }
    }
        
    private func _receivedFile(url: URL, from peerID: MCPeerID, error: Error?) {
        let snapshot = snapshot(for: peerID)
        Task { @MainActor in
            PeerSessionManager.shared.fileReceived(url: url, from: snapshot, error: error)
        }
    }
    
    nonisolated func receivedMessageFromDelegate(_ data: Data, from peerID: MCPeerID) {
        Task {
            await self._receivedMessage(data, from: peerID)
        }
    }
        
    private func _receivedMessage(_ data: Data, from peerID: MCPeerID) {
        let snapshot = snapshot(for: peerID)
        Task { @MainActor in
            PeerSessionManager.shared.messageReceived(data, from: snapshot)
        }
    }
    
    // MARK: - Send message (small data)
 
    func sendMessage(_ data: Data, to snapshot: PeerSnapshot) throws {
        if let peerID = peerIDByUUID[snapshot.id] {
            try? onCommand?(.sendData(peerID: peerID, data: data))
        }
    }

    // MARK: - Send file (resource)
    
    func sendFile(at url: URL, to snapshot: PeerSnapshot) {
        if let peerID = peerIDByUUID[snapshot.id] {
            onCommand?(.sendFile(peerID: peerID, snapshot: snapshot, url: url))
        }
    }
    
    func resourceSendCompleted(_ peerUUID: UUID, _ error: Error?) {
        onResourceSendCompleted?(peerUUID, error)
    }
    
//    let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer) { [weak self] error in
//        if let error = error {
//            print("File send failed: \(error)")
//        } else {
//            print("File sent successfully to \(peerSnapshot.displayName)")
//        }
////            Task {
////                await self?.resourceSendCompleted(to: peer, error: error)
////            }
//        self?.resourceSendCompleted(to: peerSnapshot, error: error)
//    }
//    progressByPeer[peerSnapshot.id] = progress
//    onSendResource?(peerSnapshot, progress)
//    
//    func sendFile(at url: URL, to peer: MCPeerID) {
//        guard let session, session.connectedPeers.contains(peer) else { return }
//        let snapshot = snapshot(for: peer)
//        if let progress = session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer, withCompletionHandler: { /*[weak self]*/ error in
//            if let error {
//                print("MPC send file error:", error)
//            } else {
//                print("MPC file sent to \(peer.displayName)")
//            }
//            Task {
//                await PeerSessionManager.shared.resourceSendCompleted(to: snapshot, error: error)
//            }
//        }) {
//            Task {
//                await PeerSessionManager.shared.resourceSendStarted(peerSnapshot: snapshot, progress: progress)
//            }
//        }
//    }
    
    func sendACK(to peerSnapshot: PeerSnapshot) {
        if let session,
           let peerID = peerIDByUUID[peerSnapshot.id],
           session.connectedPeers.contains(peerID) {
            let ack = Data("ACK".utf8)
            try? session.send(ack, toPeers: [peerID], with: .reliable)
            print("Send ACK to \(peerSnapshot.displayName)")
        }
    }
    
    func snapshot(for peerID: MCPeerID) -> PeerSnapshot {
    
//        if let existing = peersByID.first(where: { $0.value.peerID == peerID }) {
//            return existing.value.snapshot
//        }
        if let id = uuidByPeerID[peerID],
           let record = peersByID[id] {
            return record.snapshot
        }

        let id = UUID()
        let snapshot = PeerSnapshot(id: id, displayName: peerID.displayName)
        let record = PeerRecord(id: id, peerID: peerID, snapshot: snapshot)

        peerIDByUUID[id] = peerID
        peersByID[id] = record

        return snapshot
    }
    
}

// MARK: - Progress Snapshot

struct ProgressSnapshot {
    let fractionCompleted: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64
}

extension MCPeerID: @unchecked @retroactive Sendable {}
extension MCSession: @unchecked @retroactive Sendable {}

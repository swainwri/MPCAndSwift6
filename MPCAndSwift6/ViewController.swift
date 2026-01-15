//
//  ViewController 2.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//


import UIKit
import MultipeerConnectivity

class ViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView?
    
    var peers: [MCPeerID] = []
    var administrator: MCPeerID?
    
    // MPCActor instance
    var mpc: MPCActor?
    var sessionBridge: MCSessionDelegateBridge?
    var advertiserBridge: MPCAdvertiserDelegateBridge?
    var browserBridge: MPCBrowserDelegateBridge?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView?.frame = view.bounds
        tableView?.dataSource = self
        tableView?.delegate = self

//        setupMPCActor()
        PeerSessionManager.shared.setup()
        setupPeerSessionCallbacks()
        
        //tableView?.register(UITableViewCell.self, forCellReuseIdentifier: "PeerCell")
    }

    // MARK: - PeerSessionManager callbacks
    
    func setupPeerSessionCallbacks() {
        
        PeerSessionManager.shared.setup()
        PeerSessionManager.shared.start()
        
        PeerSessionManager.shared.onPeerFound = { [weak self] peerID, _ in
                self?.peers.append(peerID)
                self?.tableView?.reloadData()
                self?.flashAlert("Found peer: \(peerID.displayName)")
            }

        PeerSessionManager.shared.onPeerLost = { [weak self] peerID in
                self?.peers.removeAll { $0 == peerID }
                self?.tableView?.reloadData()
                self?.flashAlert("Lost peer: \(peerID.displayName)")
            }

        PeerSessionManager.shared.onInvitationReceived = { [weak self] peerName, respond in
                guard let self else { return }
                print("🖥 Showing invite UI for \(peerName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "Connection Request",
                        message: "\(peerName) wants to connect.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
                        respond(true)
                    })
                    alert.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in
                        respond(false)
                    })
                    self.present(alert, animated: true)
                }
            }

        PeerSessionManager.shared.onProgressUpdate = { snapshot, filename, peers in
                print("Progress for \(filename): \(snapshot.fractionCompleted)")
            }
        
        PeerSessionManager.shared.onPeerStateChanged = { [weak self] in
            self?.tableView?.reloadData()
        }
        
        PeerSessionManager.shared.onPeersUpdated = { [weak self] in
            self?.tableView?.reloadData()
        }
        
        PeerSessionManager.shared.onMessageReceived = { [weak self] peerID, message in
                guard let self else { return }
                print("🖥 Showing UI messaged received from \(peerID.displayName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "Message from \(peerID.displayName)",
                        message: "\(message)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
                    self.present(alert, animated: true)
                }
            }
        
        PeerSessionManager.shared.onFileReceived = { [weak self] peerID, url, name in
                guard let self else { return }
                print("🖥 Showing UI file received from \(peerID.displayName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "File from \(peerID.displayName)",
                        message: "\(name)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
                    self.present(alert, animated: true)
                }
            }
        
        PeerSessionManager.shared.onSendResource = { [weak self] peer, progress in
            Task { @MainActor in
                guard let self else { return }

                if let progress {
                    self.observe(progress, for: peer)
                }
                self.tableView?.reloadData()
            }
        }
    }

    func flashAlert(_ message: String) {
        let alert = UIAlertController(title: "Info", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            alert.dismiss(animated: true)
        }
    }

    @IBAction func resetTapped(_ sender: UIButton) {
        Task {
            await PeerSessionManager.shared.reset()
        }
    }
    
    // MARK: - Peer Retrieve File/Message progress
    
    func updateProgress(_ value: Double, for peer: MCPeerID) {
        guard let row = peers.firstIndex(of: peer) else { return }
        let indexPath = IndexPath(row: row, section: 0)

        if let cell = tableView?.cellForRow(at: indexPath) as? PeerCell {
            cell.progressView?.isHidden = false
            cell.progressView?.progress = Float(value)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
       // guard let progress = object as? Progress else { return }

        Task { @MainActor in
            self.tableView?.reloadData()
        }
    }
    
    // MARK: - Observation of Peer Progress
    
    private func observe(_ progress: Progress, for peer: MCPeerID) {
        progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: [.new], context: nil)
    }

}

extension ViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let ps = PeerSessionManager.shared
        return /*(ps.administrator != nil ? 1 : 0) +*/ ps.peers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath) as? PeerCell {
            let ps = PeerSessionManager.shared
//            if let admin = ps.administrator, indexPath.row == 0 {
//                cell.nameLabel?.text = "👑 \(admin.displayName)" // mark admin with crown
//                return cell
//            }
            
            let peerIndex = /*(ps.administrator != nil) ? indexPath.row - 1 :*/ indexPath.row
            let peerID = ps.peers[indexPath.row]
            let state = PeerSessionManager.shared.peerStates[peerID] ?? .notConnected
            
            cell.nameLabel?.text = peerID.displayName
            
            switch state {
                case .connected:
                    cell.messageButton?.isHidden = false
                    cell.fileButton?.isHidden = false
                    cell.statusLabel?.text = "Connected"
                case .connecting:
                    cell.messageButton?.isHidden = true
                    cell.fileButton?.isHidden = true
                    cell.statusLabel?.text = "Connecting…"
                case .notConnected:
                    cell.messageButton?.isHidden = true
                    cell.fileButton?.isHidden = true
                    cell.statusLabel?.text = "Not connected"
            }
            
            cell.onSendMessage = {
                PeerSessionManager.shared.sendTestMessage(to: peerID)
            }
            cell.onSendFile = {
                PeerSessionManager.shared.sendTestFile(to: peerID)
            }
            if let progress = PeerSessionManager.shared.progressByPeer[peerID] {
                cell.progressView?.isHidden = false
                cell.progressView?.progress = Float(progress.fractionCompleted)
            }
            else {
                cell.progressView?.isHidden = true
            }
            
            return cell
        }
        else {
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 75.0
    }
    
}

extension ViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let peer = PeerSessionManager.shared.peers[indexPath.row]
        Task {
            await PeerSessionManager.shared.invite(peer: peer)
        }
    }
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        let ps = PeerSessionManager.shared
//        let peerIndex = (ps.administrator != nil) ? indexPath.row - 1 : indexPath.row
//        let peer = ps.peers[peerIndex]
//        ps.assignAdministrator(peer)
//        tableView.reloadData()
//    }
    
}



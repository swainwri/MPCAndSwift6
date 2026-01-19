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
    
    var peers: [PeerSnapshot] = []
    var administrator: PeerSnapshot?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView?.frame = view.bounds
        tableView?.dataSource = self
        tableView?.delegate = self

        setupPeerSessionCallbacks()
    }

    // MARK: - PeerSessionManager callbacks
    
    func setupPeerSessionCallbacks() {
        
        Task {
            await PeerSessionManager.shared.setup()
            await PeerSessionManager.shared.start()
        }
        PeerSessionManager.shared.onPeerFound = { [weak self] peerSnapshot, _ in
                self?.peers.append(peerSnapshot)
                self?.tableView?.reloadData()
            self?.flashAlert("Found peer: \(peerSnapshot.displayName)")
            }

        PeerSessionManager.shared.onPeerLost = { [weak self] peerSnapshot in
                self?.peers.removeAll { $0 == peerSnapshot }
                self?.tableView?.reloadData()
                self?.flashAlert("Lost peer: \(peerSnapshot.displayName)")
            }

        PeerSessionManager.shared.onInvitationReceived = { [weak self] peerSnapshot in
                guard let self else { return }
                print("🖥 Showing invite UI for \(peerSnapshot.displayName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "Connection Request",
                        message: "\(peerSnapshot.displayName) wants to connect.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
                        Task {
                            PeerSessionManager.shared.acceptInvitation(true)
                        }
                    })
                    alert.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in
                        Task {
                            PeerSessionManager.shared.acceptInvitation(false)
                        }
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
        
        PeerSessionManager.shared.onMessageReceived = { [weak self] peerSnapshot, message in
                guard let self else { return }
                print("🖥 Showing UI messaged received from \(peerSnapshot.displayName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "Message from \(peerSnapshot.displayName)",
                        message: "\(message)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
                    self.present(alert, animated: true)
                }
            }
        
        PeerSessionManager.shared.onFileReceived = { [weak self] peerSnapshot, url, name in
                guard let self else { return }
                print("🖥 Showing UI file received from \(peerSnapshot.displayName)")
                Task { @MainActor in
                    let alert = UIAlertController(
                        title: "File from \(peerSnapshot.displayName)",
                        message: "\(name)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
                    self.present(alert, animated: true)
                }
            }
        
        PeerSessionManager.shared.onSendResource = { [weak self] peerSnapshot, progress in
            Task { @MainActor in
                guard let self else { return }

                if let progress {
                    self.observe(progress, for: peerSnapshot)
                }
                self.tableView?.reloadData()
            }
        }
    }

    func flashAlert(_ message: String) {
        let alert = UIAlertController(title: "Info", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            alert.dismiss(animated: true)
        }
    }

    @IBAction func resetTapped(_ sender: UIButton) {
        Task {
            await PeerSessionManager.shared.reset()
        }
    }
    
    // MARK: - Peer Retrieve File/Message progress
    
    func updateProgress(_ value: Double, for peerSnapshot: PeerSnapshot) {
        if let row = peers.map({ $0.id }).firstIndex(of: peerSnapshot.id) {
            let indexPath = IndexPath(row: row, section: 0)
            
            if let cell = tableView?.cellForRow(at: indexPath) as? PeerCell {
                cell.progressView?.isHidden = false
                cell.progressView?.progress = Float(value)
            }
        }
    }
    
    nonisolated
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
       // guard let progress = object as? Progress else { return }

        Task { @MainActor in
            self.tableView?.reloadData()
        }
    }
    
    // MARK: - Observation of Peer Progress
    
    private func observe(_ progress: Progress, for peer: PeerSnapshot) {
        progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: [.new], context: nil)
    }

}

extension ViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let ps = PeerSessionManager.shared
        print("Peers: \(ps.peers.count)")
        return /*(ps.administrator != nil ? 1 : 0) +*/ ps.peers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let ps = PeerSessionManager.shared
        if let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath) as? PeerCell,
           ps.peers.count > 0 {
            
//            if let admin = ps.administrator, indexPath.row == 0 {
//                cell.nameLabel?.text = "👑 \(admin.displayName)" // mark admin with crown
//                return cell
//            }
            print("peerStates read in manager:", ObjectIdentifier(ps))
            //let peerIndex = /*(ps.administrator != nil) ? indexPath.row - 1 :*/ indexPath.row
            let peerSnapshot = ps.peers[indexPath.row]
            let state = ps.peerStates[peerSnapshot.id] ?? .notConnected
    
            cell.nameLabel?.text = peerSnapshot.displayName
            
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
                PeerSessionManager.shared.sendTestMessage(to: peerSnapshot)
            }
            cell.onSendFile = {
                PeerSessionManager.shared.sendTestFile(to: peerSnapshot)
            }
            if let progress = PeerSessionManager.shared.progressByPeer[peerSnapshot.id] {
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
        let peerSnapshot = PeerSessionManager.shared.peers[indexPath.row]
        Task {
            await PeerSessionManager.shared.invite(peerSnapshot: peerSnapshot)
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



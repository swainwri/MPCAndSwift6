//
//  ViewController 2.swift
//  BarTalking
//
//  Created by Steve Wainwright on 13/01/2026.
//


import UIKit
import MultipeerConnectivity

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    let tableView = UITableView()
    var peers: [MCPeerID] = []
    var administrator: MCPeerID?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.dataSource = self
        tableView.delegate = self

        PeerSessionManager.shared.onPeerFound = { [weak self] peerID, _ in
            DispatchQueue.main.async {
                self?.peers.append(peerID)
                self?.tableView.reloadData()
                self?.flashAlert("Found peer: \(peerID.displayName)")
            }
        }

        PeerSessionManager.shared.onPeerLost = { [weak self] peerID in
            DispatchQueue.main.async {
                self?.peers.removeAll { $0 == peerID }
                self?.tableView.reloadData()
                self?.flashAlert("Lost peer: \(peerID.displayName)")
            }
        }

        PeerSessionManager.shared.onInvitationReceived = { [weak self] peerID, respond in
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Invitation", message: "Peer \(peerID.displayName) wants to connect", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Accept", style: .default, handler: { _ in respond(true) }))
                alert.addAction(UIAlertAction(title: "Decline", style: .cancel, handler: { _ in respond(false) }))
                self?.present(alert, animated: true)
            }
        }
    }

    func flashAlert(_ message: String) {
        let alert = UIAlertController(title: "Info", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            alert.dismiss(animated: true)
        }
    }

    // MARK: - TableView
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var count = peers.count
        if administrator != nil { count += 1 }
        return count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.row == 0, let admin = administrator {
            cell.textLabel?.text = "Administrator: \(admin.displayName)"
        } else {
            let peerIndex = administrator != nil ? indexPath.row - 1 : indexPath.row
            cell.textLabel?.text = peers[peerIndex].displayName
        }
        return cell
    }
}
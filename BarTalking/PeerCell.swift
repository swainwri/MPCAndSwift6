//
//  PeerCell.swift
//  BarTalking
//
//  Created by Steve Wainwright on 14/01/2026.
//
import UIKit

final class PeerCell: UITableViewCell {

    @IBOutlet weak var nameLabel: UILabel?
    @IBOutlet weak var statusLabel: UILabel?
    @IBOutlet weak var messageButton: UIButton?
    @IBOutlet weak var fileButton: UIButton?
    @IBOutlet weak var progressView: UIProgressView?

    var onSendMessage: (() -> Void)?
    var onSendFile: (() -> Void)?

    @IBAction func sendMessageTapped() { onSendMessage?() }
    @IBAction func sendFileTapped() { onSendFile?() }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        configureAccessibility()
    }

    private func configureAccessibility() {
        messageButton?.accessibilityLabel = "Send message"
        messageButton?.accessibilityHint = "Sends a text message to this peer"

        fileButton?.accessibilityLabel = "Send file"
        fileButton?.accessibilityHint = "Sends a file to this peer"
        
        messageButton?.isAccessibilityElement = true
        fileButton?.isAccessibilityElement = true
    }
    
    func update(for state: PeerConnectionState) {
        let enabled = (state == .connected)

        messageButton?.isEnabled = enabled
        fileButton?.isEnabled = enabled

        messageButton?.accessibilityValue = enabled ? "Connected" : "Not connected"
        fileButton?.accessibilityValue = enabled ? "Connected" : "Not connected"
    }
}
